module JavaScript
  JS_FUNCTIONS = [] of Nil

  JS_TYPE_READERS = {} of Nil => Nil

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

              type_size = {
                Int8 => 1, UInt8 => 1,
                Int16 => 2, UInt16 => 2,
                Int32 => 4, UInt32 => 4,
                Int64 => 8, UInt64 => 8
              }

              js_mem_read = {
                Int8 => "mem.getInt8($POS$)",
                UInt8 => "mem.getUint8($POS$)",
                Int16 => "mem.getInt16($POS$, true)",
                UInt16 => "mem.getUint16($POS$, true)",
                Int32 => "mem.getInt32($POS$, true)",
                UInt32 => "mem.getUint32($POS$, true)",
                Int64 => "mem.getBigInt64($POS$, true)",
                UInt64 => "mem.getBigUint64($POS$, true)",
              }

              js_prepare = ""
              js_body = "\n"
              js_args = [] of Nil
              cr_prepare = ""
              cr_args = [] of Nil
              fun_args_decl = [] of Nil
              fun_name = "_js#{::JavaScript::JS_FUNCTIONS.size+1}".id
              literal = true
              var_counter = 0

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
                  elsif piece.class_name == "Var" && method.args.find(&.name.id.== piece.id) && method.args.find(&.internal_name.id.== piece.id).restriction
                    index = method.args.map_with_index {|arg, idx| [arg, idx] }.find(&.[0].internal_name.id.== piece.id)[1]
                    arg_type = method.args[index].restriction.resolve
                    method.splat_index == index ? parse_type("Enumerable(#{arg_type.id})").resolve : arg_type
                  else
                    piece.raise "Can't infer the type of this JavaScript argument: '#{piece.id}' (#{piece.class_name.id})"
                  end

                  type_information = {type: type, value: piece}
                  types_to_process = [type_information]
                  types_to_expand = [type_information]

                  types_to_process.each do |info|
                    info[:js_prepare] = ""
                    info[:js_body] = ""
                    info[:js_args] = [] of Nil
                    info[:cr_prepare] = ""
                    info[:cr_args] = [] of Nil
                    info[:fun_args_decl] = [] of Nil

                    if info[:type] <= ::JavaScript::Reference
                      arg = "arg#{var_counter += 1}".id
                      info[:js_args] << arg
                      info[:fun_args_decl] << [arg, Int32]
                      info[:js_body] += "heap[#{arg}]"
                      info[:cr_args] << "#{info[:value].id}.@extern_ref.index".id
                    elsif info[:type] <= ::Enumerable
                      base_type = ([info[:type]] + info[:type].ancestors).select { |x| x <= Enumerable }.last.type_vars[0]
                      info[:type] = parse_type("Enumerable(#{base_type.id})").resolve
                      info[:base_type] = {type: base_type, value: "e".id}
                      types_to_process << info[:base_type]
                      types_to_expand.unshift info[:base_type]
                    elsif [Int8, Int16, Int32, UInt8, UInt16, UInt32].includes? info[:type]
                      arg = "arg#{var_counter += 1}".id
                      info[:js_args] << arg
                      info[:fun_args_decl] << [arg, info[:type]]
                      info[:js_body] += "#{arg}"
                      info[:cr_args] << info[:value]
                    elsif info[:type] == ::Bool
                      arg = "arg#{var_counter += 1}".id
                      info[:js_args] << arg
                      info[:fun_args_decl] << [arg, UInt8]
                      info[:js_body] += "(#{arg} === 1)"
                      info[:cr_args] << "((#{info[:value].id}) ? 1 : 0)".id
                    elsif info[:type] == ::String
                      arg_buf = "arg#{var_counter += 1}".id
                      arg_len = "arg#{var_counter += 1}".id
                      info[:js_args] << arg_buf
                      info[:js_args] << arg_len
                      info[:fun_args_decl] << [arg_buf, UInt32]
                      info[:fun_args_decl] << [arg_len, Int32]
                      info[:js_body] += "read_string(#{arg_buf}, #{arg_len})"
                      tmp_var = "__var#{var_counter += 1}"
                      info[:cr_prepare] += "#{tmp_var.id} = (#{info[:value].id})\n"
                      info[:cr_args] << "#{tmp_var.id}.to_unsafe.address.to_u32".id
                      info[:cr_args] << "#{tmp_var.id}.bytesize".id
                    else
                      piece.raise "Can't handle type '#{info[:type]}' as a JavaScript argument."
                    end

                    if types_to_process.size > 10
                      piece.raise "Can't handle type '#{type_information[:type]}' as a JavaScript argument, it is too deep."
                    end
                  end

                  types_to_expand.each do |info|
                    if info[:type] <= ::Enumerable
                      arg_buf = "arg#{var_counter += 1}".id
                      arg_len = "arg#{var_counter += 1}".id
                      info[:js_args] << arg_buf
                      info[:js_args] << arg_len
                      info[:fun_args_decl] << [arg_buf, UInt32]
                      info[:fun_args_decl] << [arg_len, Int32]
                      size_per_element = info[:base_type][:fun_args_decl].map { |(_, type)| type_size[type] }.reduce(0) { |a, b| a + b }
                      value_var = "__var#{var_counter += 1}"
                      size_var = "__var#{var_counter += 1}"
                      buf_var = "__var#{var_counter += 1}"
                      index_var = "__var#{var_counter += 1}"
                      info[:cr_prepare] += "#{value_var.id} = (#{info[:value].id})\n"
                      info[:cr_prepare] += "#{size_var.id} = #{value_var.id}.size\n"
                      info[:cr_prepare] += "#{buf_var.id} = GC.malloc_atomic(#{size_per_element} * #{size_var.id}).as(UInt8*)\n"
                      info[:cr_prepare] += "#{index_var.id} = 0\n"
                      info[:cr_prepare] += "#{value_var.id}.each do |e|\n"
                      info[:cr_prepare] += info[:base_type][:cr_prepare] + "\n"
                      info[:base_type][:fun_args_decl].each_with_index do |(var, type), idx|
                        info[:cr_prepare] += "(#{buf_var.id} + #{index_var.id}).as(#{type}*).value = (#{info[:base_type][:cr_args][idx]})\n"
                        info[:cr_prepare] += "#{index_var.id} += #{type_size[type]}\n"
                      end
                      info[:cr_prepare] += "end\n"
                      info[:cr_args] << "#{buf_var.id}.address.to_u32".id
                      info[:cr_args] << size_var.id
                      unless ::JavaScript::JS_TYPE_READERS[info[:type]]
                        name = "__read_type_#{::JavaScript::JS_TYPE_READERS.size+1}"
                        reader_function = "  function #{name.id}(buf, size) { // #{info[:type]}\n"
                        reader_function += "    return Array.from({length: size}, () => {\n"
                        info[:base_type][:fun_args_decl].each_with_index do |(var, type), idx|
                          reader_function += "      const #{info[:base_type][:js_args][idx]} = #{js_mem_read[type].gsub(/\$POS\$/, "buf").id};\n"
                          reader_function += "      buf += #{type_size[type]};\n"
                        end
                        reader_function += "      return #{info[:base_type][:js_body].id};\n"
                        reader_function += "    });\n"
                        reader_function += "  }"
                        ::JavaScript::JS_TYPE_READERS[info[:type]] = [name, reader_function]
                      end
                      info[:js_body] += "#{::JavaScript::JS_TYPE_READERS[info[:type]][0].id}(#{arg_buf}, #{arg_len})"
                    end
                  end

                  js_prepare += type_information[:js_prepare]
                  js_body += type_information[:js_body]
                  js_args += type_information[:js_args]
                  cr_prepare += type_information[:cr_prepare]
                  cr_args += type_information[:cr_args]
                  fun_args_decl += type_information[:fun_args_decl]
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

              js_code = "#{fun_name}(#{js_args.join(", ").id}) { #{js_prepare.id} #{js_body.id} }"
              ::JavaScript::JS_FUNCTIONS << [fun_name, fun_args_decl, fun_ret, js_code, false]
            %}
            def \{{ method.receiver ? "#{method.receiver.id}.".id : "".id }}\{{ method.name }}(\{{
              *method.args.map_with_index do |arg, index|
                (
                  (index == method.splat_index ? "*" : "") +
                  "#{arg.name}" +
                  (arg.name != arg.internal_name ? " #{arg.internal_name}" : "") +
                  (arg.restriction.class_name == "Nop" ? "" : " : #{arg.restriction}") +
                  (arg.default_value.class_name == "Nop" ? "" : " = #{arg.default_value}")
                ).id
              end
            }}) : \{{method.return_type || Nil}}
              \\{%
                fun_name = \{{fun_name.stringify}}
                ::JavaScript::JS_FUNCTIONS.find {|x| x[0] == fun_name }[4] = true
              %}

              \{{ cr_prepare.id }}

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

    END

    ::JavaScript::JS_TYPE_READERS.values.each do |pair|
      js += "\n#{pair[1].id}\n"
    end

    js += <<-END

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
