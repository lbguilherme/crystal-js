module JavaScript
  JS_FUNCTIONS = [] of Nil

  annotation Method
  end

  abstract class Value
    struct ExternalReferenceIndex
      getter index : Int32

      def initialize(@index)
      end
    end

    def initialize(@extern_ref : ExternalReferenceIndex)
    end

    def inspect(io)
      to_s(io)
    end

    @[JavaScript::Method]
    def finalize
      <<-js
        drop_ref(#{@extern_ref.index.as(Int32)});
      js
    end

    macro js_getter(decl)
      @[::JavaScript::Method]
      def {{decl.var.stringify.underscore.id}} : {{decl.type}}
        <<-js
          return #{self}.{{decl.var.id}};
        js
      end
    end

    macro js_setter(decl)
      @[::JavaScript::Method]
      private def internal_setter_{{decl.var.stringify.underscore.id}}(value : {{decl.type}})
        <<-js
          return #{self}.{{decl.var.id}} = #{value};
        js
      end

      def {{decl.var.stringify.underscore.id}}=(value : {{decl.type}})
        internal_setter_{{decl.var.stringify.underscore.id}}(value)
        value
      end
    end

    macro js_property(decl)
      js_getter(decl)
      js_setter(decl)
    end

    macro js_method(call, ret = Nil)
      @[::JavaScript::Method]
      def {{call.name.stringify.underscore.id}}({{*call.args}}) : {{ret}}
        <<-js
          return #{self}.{{call.name.id}}({{*call.args.map { |arg| "\#{#{arg.var}}".id }}});
        js
      end
    end
  end

  module ExpandMethods
    macro included
      macro finished
        \{% for method in @type.methods + @type.class.methods %}
          \{% if method.annotation(::JavaScript::Method) %}
            \{%
              pieces = if method.body.class_name == "StringLiteral"
                [method.body]
              elsif method.body.class_name == "StringInterpolation"
                method.body.expressions
              else
                method.raise "The body of the method '#{method.name}' must be a single string of JavaScript code."
              end

              if method.receiver && (method.receiver.class_name != "Var" || method.receiver.id != "self")
                method.raise "If present, the method receiver can't be anything other than 'self'."
              end

              js_body = "\n"
              js_args = [] of Nil
              cr_vars = [] of Nil
              cr_args = [] of Nil
              fun_name = "_js#{::JavaScript::JS_FUNCTIONS.size+1}".id
              fun_args_decl = [] of Nil
              literal = true

              pieces.each do |piece|
                if literal
                  js_body += piece
                else
                  type = if piece.class_name == "Var" && piece.id == "self"
                    @type
                  elsif piece.class_name == "Cast"
                    piece.to.resolve
                  elsif piece.class_name == "StringLiteral"
                    String
                  elsif piece.class_name == "Var" && method.args.find(&.name.id.== piece.id) && method.args.find(&.name.id.== piece.id).restriction
                    method.args.find(&.name.id.== piece.id).restriction.resolve
                  else
                    piece.raise "Can't infer the type of this JavaScript argument: '#{piece.id}' (#{piece.class_name.id})"
                  end

                  if type.ancestors.includes? ::JavaScript::Value
                    arg = "arg#{js_args.size+1}"
                    js_args << arg
                    fun_args_decl << "#{arg.id} : Int32".id
                    js_body += "heap[#{arg.id}]"
                    cr_args << "#{piece.id}.@extern_ref.index".id
                  elsif [Int8, Int16, Int32, UInt8, UInt16, UInt32].includes? type
                    arg = "arg#{js_args.size+1}"
                    js_args << arg
                    fun_args_decl << "#{arg.id} : #{type.id}".id
                    js_body += arg
                    cr_args << piece
                  elsif type == String
                    arg_buf = "arg#{js_args.size+1}"
                    js_args << arg_buf
                    arg_len = "arg#{js_args.size+1}"
                    js_args << arg_len
                    fun_args_decl << "#{arg_buf.id} : Int32".id
                    fun_args_decl << "#{arg_len.id} : Int32".id
                    js_body += "read_string(#{arg_buf.id}, #{arg_len.id})"
                    var = "__var#{cr_vars.size+1}"
                    cr_vars << "#{var.id} = #{piece.id}"
                    cr_args << "#{var.id}.to_unsafe.address".id
                    cr_args << "#{var.id}.bytesize".id
                  else
                    piece.raise "Can't handle type '#{type}' as a JavaScript argument."
                  end
                end

                literal = !literal
              end

              js_body += "\n"

              return_type = method.return_type ? method.return_type.resolve : Nil
              if return_type == Nil
                fun_ret = "Void".id
              elsif return_type.ancestors.includes? ::JavaScript::Value
                fun_ret = "Int32".id
                js_body = "return make_ref((() => { #{js_body.id} })());"
              elsif [Int8, Int16, Int32, UInt8, UInt16, UInt32].includes? return_type
                fun_ret = return_type
              else
                method.return_type.raise "Can't handle type '#{return_type}' as a JavaScript return type."
              end

              js_code = "#{fun_name}(#{js_args.join(", ").id}) { #{js_body.id} }"
              ::JavaScript::JS_FUNCTIONS << [fun_name, fun_args_decl, fun_ret, js_code, false]
            %}
            def \{{ method.receiver ? "#{method.receiver.id}.".id : "".id }}\{{ method.name }}(\{{*method.args}}) : \{{method.return_type || Nil}}
              \\{%
                fun_name = \{{fun_name.stringify}}
                ::JavaScript::JS_FUNCTIONS.find {|x| x[0] == fun_name }[4] = true
              %}

              \{{ cr_vars.join("\n").id }}
              \{% if [Int8, Int16, Int32, UInt8, UInt16, UInt32, Nil].includes? return_type %}
                ::LibJavaScript.\{{ fun_name }}(\{{*cr_args}})
              \{% elsif return_type.ancestors.includes? ::JavaScript::Value %}
                ref = ::LibJavaScript.\{{ fun_name }}(\{{*cr_args}})
                \{{return_type}}.new(::JavaScript::Value::ExternalReferenceIndex.new(ref))
              \{% end %}
            end
          \{% end %}
        \{% end %}
      end
    end
  end

  class Value
    include ExpandMethods

    macro inherited
      include ::JavaScript::ExpandMethods
    end
  end
end

private def generate_output_js_file
  {%
    js = <<-END
    async function runCrystalApp(wasmHref) {
      const heap = [null];
      const free = [];
      let instance;
      let mem;

      function make_ref(element) {
        const index = free.length ? free.pop() : heap.length;
        heap[index] = element;
        return index;
      }

      function drop_ref(index) {
        if (index === 0) return;
        heap[index] = undefined;
        free.push(index);
      }

      function read_string(pos, len) {
        return String.fromCharCode.apply(null, new Uint8Array(mem.buffer, pos, len))
      }

      const imports = {
        env: {

    END

    ::JavaScript::JS_FUNCTIONS.map(&.[3]).each do |func|
      js += "      #{func.id},\n"
    end

    js += <<-END
        },
        wasi_snapshot_preview1: {
          fd_close() {
            throw new Error("fd_close");
          },
          fd_fdstat_get(fd, buf) {
            if (fd > 2) return 8;
            mem.setUint8(buf, 4, true); // WASI_FILETYPE_REGULAR_FILE
            mem.setUint16(buf + 2, 0, true);
            mem.setUint16(buf + 4, 0, true);
            mem.setBigUint64(buf + 8, BigInt(0), true);
            mem.setBigUint64(buf + 16, BigInt(0), true);
            return 0;
          },
          fd_fdstat_set_flags(fd) {
            if (fd > 2) return 8;
            throw new Error("fd_fdstat_set_flags");
          },
          fd_filestat_get(fd, buf) {
            if (fd > 2) return 8;
            mem.setBigUint64(buf, BigInt(0), true);
            mem.setBigUint64(buf + 8, BigInt(0), true);
            mem.setUint8(buf + 16, 4, true); // WASI_FILETYPE_REGULAR_FILE
            mem.setBigUint64(buf + 24, BigInt(1), true);
            mem.setBigUint64(buf + 32, BigInt(0), true);
            mem.setBigUint64(buf + 40, BigInt(0), true);
            mem.setBigUint64(buf + 48, BigInt(0), true);
            mem.setBigUint64(buf + 56, BigInt(0), true);
            return 0;
          },
          fd_seek() {
            throw new Error("fd_seek");
          },
          fd_write(fd, iovs, length, bytes_written_ptr) {
            if (fd < 1 || fd > 2) return 8;
            let bytes_written = 0;
            for (let i = 0; i < length; i++) {
              const buf = mem.getUint32(iovs + i * 8, true);
              const len = mem.getUint32(iovs + i * 8 + 4, true);
              bytes_written += len;
              (fd === 1 ? console.log : console.error)(read_string(buf, len));
            }
            mem.setUint32(bytes_written_ptr, bytes_written, true);
            return 0;
          },
          proc_exit() {
            throw new Error("proc_exit");
          },
          random_get(buf, len) {
            crypto.getRandomValues(new Uint8Array(mem.buffer, buf, len));
            return 0;
          },
        }
      };

      const wasm = await WebAssembly.instantiate(await (await fetch(wasmHref)).arrayBuffer(), imports);
      instance = wasm.instance;
      mem = new DataView(instance.exports.memory.buffer)
      instance.exports.__crystal_main(0, 0);
    }

    END

    `printf #{js} > #{env("JAVASCRIPT_OUTPUT_FILE") || "web.js"}`
  %}
end

macro finished
  macro finished
    generate_output_js_file

    lib LibJavaScript
      \{% for func in JavaScript::JS_FUNCTIONS %}
        \{{ "fun #{func[0]}(#{func[1].join(", ").id}) : #{func[2]}".id }}
      \{% end %}
    end
  end
end
