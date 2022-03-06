module JavaScript
  JS_FUNCTIONS = [] of Nil

  annotation Method
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
                    index = method.args.map_with_index {|arg, idx| [arg, idx] }.find(&.[0].name.id.== piece.id)[1]
                    arg_type = method.args[index].restriction.resolve
                    method.splat_index == index ? parse_type("Enumerable(#{arg_type.id})").resolve : arg_type
                  else
                    piece.raise "Can't infer the type of this JavaScript argument: '#{piece.id}' (#{piece.class_name.id})"
                  end

                  if type <= ::JavaScript::Reference
                    arg = "arg#{js_args.size+1}"
                    js_args << arg
                    fun_args_decl << [arg.id, "Int32".id]
                    js_body += "heap[#{arg.id}]"
                    cr_args << "#{piece.id}.@extern_ref.index".id
                  elsif type <= ::Enumerable
                    base_type = ([type] + type.ancestors).select {|x| x <= Enumerable }.last.type_vars[0]
                    piece.raise "TODO: Enumerable of #{base_type}"
                  elsif [Int8, Int16, Int32, UInt8, UInt16, UInt32].includes? type
                    arg = "arg#{js_args.size+1}"
                    js_args << arg
                    fun_args_decl << [arg.id, type.id]
                    js_body += arg
                    cr_args << piece
                  elsif type == ::Bool
                    arg = "arg#{js_args.size+1}"
                    js_args << arg
                    fun_args_decl << [arg.id, "UInt8".id]
                    js_body += "(#{arg.id} === 1)"
                    cr_args << "((#{piece.id}) ? 1 : 0)".id
                  elsif type == ::String
                    arg_buf = "arg#{js_args.size+1}"
                    js_args << arg_buf
                    arg_len = "arg#{js_args.size+1}"
                    js_args << arg_len
                    fun_args_decl << [arg_buf.id, "Int32".id]
                    fun_args_decl << [arg_len.id, "Int32".id]
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

              return_type = method.return_type ? method.return_type.class_name == "Self" ? @type : method.return_type.resolve : Nil
              if return_type == Nil
                fun_ret = "Void".id
              elsif return_type < ::JavaScript::Reference
                fun_ret = "Int32".id
                js_body = "return make_ref((() => { #{js_body.id} })());"
              elsif [Int8, Int16, Int32, UInt8, UInt16, UInt32].includes? return_type
                fun_ret = return_type
              elsif return_type == Bool
                fun_ret = "UInt8".id
                js_body = "return (() => { #{js_body.id} })() ? 1 : 0;"
              elsif return_type == ::String
                fun_ret = "Void*".id
                js_body = "return make_string((() => { #{js_body.id} })());"
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
              \{% elsif return_type < ::JavaScript::Reference %}
                ref = ::LibJavaScript.\{{ fun_name }}(\{{*cr_args}})
                \{{return_type}}.new(::JavaScript::Reference::ReferenceIndex.new(ref))
              \{% elsif return_type == ::String %}
                ::LibJavaScript.\{{ fun_name }}(\{{*cr_args}}).as(::String)
              \{% elsif return_type == Bool %}
                ::LibJavaScript.\{{ fun_name }}(\{{*cr_args}}) == 1
              \{% end %}
            end
          \{% end %}
        \{% end %}
      end
    end
  end

  class Reference
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
      const encoder = new TextEncoder();
      const decoder = new TextDecoder();
      const heap = [null];
      const free = [];
      let instance;
      let mem;
      let malloc_atomic;
      let malloc;
      let string_type_id;

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
        return decoder.decode(new Uint8Array(mem.buffer, pos, len))
      }

      function make_string(str) {
        const data = encoder.encode(str);
        const ptr = malloc_atomic(13 + data.byteLength);
        mem.setUint32(ptr, string_type_id, true);
        mem.setUint32(ptr + 4, data.byteLength, true);
        mem.setUint32(ptr + 8, str.length, true);
        for (let i = 0; i < data.byteLength; i++) {
          mem.setUint8(ptr + 12 + i, data[i]);
        }
        mem.setUint8(ptr + 12 + data.byteLength, 0);
        return ptr;
      }

      const imports = {
        env: {

    END

    ::JavaScript::JS_FUNCTIONS.each do |func|
      js += "      #{func[3].id},\n" if func[4]
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
          fd_prestat_get() {
            return 8; // WASI_EBADF
          },
          fd_prestat_dir_name() {
            return 8; // WASI_EBADF
          },
          fd_seek() {
            throw new Error("fd_seek");
          },
          fd_read() {
            throw new Error("fd_read");
          },
          path_create_directory() {
            throw new Error("path_create_directory");
          },
          path_filestat_get() {
            throw new Error("path_filestat_get");
          },
          path_open() {
            throw new Error("path_open");
          },
          fd_write(fd, iovs, length, bytes_written_ptr) {
            if (fd < 1 || fd > 2) return 8;
            let bytes_written = 0;
            for (let i = 0; i < length; i++) {
              const buf = mem.getUint32(iovs + i * 8, true);
              const len = mem.getUint32(iovs + i * 8 + 4, true);
              bytes_written += len;
              #{if env("CRYSTAL_WEB_EMIT_DENO")
                  "Deno.writeAllSync(fd === 1 ? Deno.stdout : Deno.stderr, new Uint8Array(mem.buffer, buf, len));".id
                else
                  "(fd === 1 ? console.log : console.error)(read_string(buf, len));".id
                end}
            }
            mem.setUint32(bytes_written_ptr, bytes_written, true);
            return 0;
          },
          proc_exit(exitcode) {
            throw new Error("proc_exit " + exitcode);
          },
          random_get(buf, len) {
            crypto.getRandomValues(new Uint8Array(mem.buffer, buf, len));
            return 0;
          },
          environ_get() {
            return 0;
          },
          environ_sizes_get(count_ptr, buf_size_ptr) {
            mem.setUint32(count_ptr, 0, true);
            mem.setUint32(buf_size_ptr, 0, true);
            return 0;
          },
          clock_time_get(clock_id, precision, time_ptr) {
            const time = BigInt((clock_id === 0 ? Date.now() : performance.now()) * 1000000);
            mem.setBigUint64(time_ptr, time, true);
            return 0;
          },
          args_sizes_get(argc_ptr, argv_buf_size_ptr) {
            mem.setUint32(argc_ptr, 1, true);
            mem.setUint32(argv_buf_size_ptr, encoder.encode(wasmHref).length + 1, true);
          },
          args_get(argv_ptr, argv_buf_ptr) {
            mem.setUint32(argv_ptr, argv_buf_ptr, true);
            const data = encoder.encode(wasmHref);
            for (let i = 0; i < data.length; i++) {
              mem.setUint8(argv_buf_ptr + i, data[i]);
            }
            mem.setUint8(argv_buf_ptr + data.length, 0);
          }
        }
      };

      const wasm = await WebAssembly.instantiateStreaming(fetch(wasmHref), imports);
      instance = wasm.instance;
      instance.exports.memory.grow(1);
      mem = new DataView(instance.exports.memory.buffer);
      malloc_atomic = instance.exports.__js_bridge_malloc_atomic;
      malloc = instance.exports.__js_bridge_malloc;
      string_type_id = instance.exports.__js_bridge_get_type_id(0);
      instance.exports.__original_main();
    }

    END

    system("printf #{js} > #{env("JAVASCRIPT_OUTPUT_FILE") || "web.js"}")
  %}
end

macro finished
  macro finished
    generate_output_js_file

    lib LibJavaScript
      \{% for func in JavaScript::JS_FUNCTIONS %}
        \{{ "fun #{func[0]}(#{func[1].map { |(arg, type)| "#{arg} : #{type}".id }.join(", ").id}) : #{func[2]}".id }}
      \{% end %}
    end
  end
end

fun __js_bridge_malloc_atomic(size : UInt32) : Void*
  GC.malloc_atomic(size)
end

fun __js_bridge_malloc(size : UInt32) : Void*
  GC.malloc(size)
end

fun __js_bridge_get_type_id(type : Int32) : Int32
  case type
  when 0
    String::TYPE_ID
  else
    0
  end
end
