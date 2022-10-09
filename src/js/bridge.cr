module JS
  FUNCTIONS = [] of Nil

  EXPORTS = [] of Nil

  HELPERS = {} of Nil => Nil

  annotation Method
  end

  module ExpandMethods
    macro included
      macro finished
        \{% for method in @type.methods + @type.class.methods %}
          \{% if method.annotation(::JS::Method) %}
            \{%
              pieces = if method.body.is_a?(StringLiteral)
                [method.body]
              elsif method.body.is_a?(StringInterpolation)
                method.body.expressions
              else
                method.raise "The body of the method '#{method.name}' must be a single string of JavaScript code."
              end

              if method.receiver && (!method.receiver.is_a?(Var) || method.receiver.id != "self")
                method.raise "If present, the method receiver can't be anything other than 'self'."
              end

              type_size = {
                Int8 => 1, UInt8 => 1,
                Int16 => 2, UInt16 => 2,
                Int32 => 4, UInt32 => 4,
                Int64 => 8, UInt64 => 8
              }

              js_mem_read = {
                Int8 => "__memory.getInt8($POS$)",
                UInt8 => "__memory.getUint8($POS$)",
                Int16 => "__memory.getInt16($POS$, true)",
                UInt16 => "__memory.getUint16($POS$, true)",
                Int32 => "__memory.getInt32($POS$, true)",
                UInt32 => "__memory.getUint32($POS$, true)",
                Int64 => "__memory.getBigInt64($POS$, true)",
                UInt64 => "__memory.getBigUint64($POS$, true)",
              }

              js_prepare = ""
              js_body = "\n"
              js_args = [] of Nil
              cr_prepare = ""
              cr_args = [] of Nil
              fun_args_decl = [] of Nil
              fun_name = "_js#{::JS::FUNCTIONS.size+1}".id
              literal = true
              var_counter = 0

              required_helpers = [] of Nil

              pieces.each do |piece|
                if literal
                  js_body += piece
                else
                  piece = piece.resolve if piece.is_a?(Path)

                  type = if piece.is_a?(Var) && piece.id == "self"
                    @type
                  elsif piece.is_a?(Cast)
                    piece.to.resolve
                  elsif piece.is_a?(StringLiteral)
                    String
                  elsif piece.is_a?(Var) && method.args.find(&.name.id.== piece.id) && method.args.find(&.internal_name.id.== piece.id).restriction
                    index = method.args.map_with_index {|arg, idx| [arg, idx] }.find(&.[0].internal_name.id.== piece.id)[1]
                    arg_type = method.args[index].restriction
                    arg_type = arg_type.is_a?(Self) ? @type : arg_type.resolve
                    method.splat_index == index ? parse_type("Enumerable(#{arg_type.id})").resolve : arg_type
                  elsif piece.is_a?(TypeNode)
                    Class
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

                    if info[:type] <= ::JS::Reference
                      arg = "arg#{var_counter += 1}".id
                      info[:js_args] << arg
                      info[:fun_args_decl] << [arg, Int32]
                      info[:js_body] += "__heap[#{arg}]"
                      info[:cr_args] << "#{info[:value].id}.@extern_ref.index".id
                    elsif info[:type] <= ::Enumerable
                      base_type = ([info[:type]] + info[:type].ancestors).select { |x| x <= Enumerable }.last.type_vars[0]
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
                    elsif info[:type] == ::Nil
                      arg = "arg#{var_counter += 1}".id
                      info[:js_body] += "null"
                    elsif info[:type] == ::String
                      arg_buf = "arg#{var_counter += 1}".id
                      arg_len = "arg#{var_counter += 1}".id
                      info[:js_args] << arg_buf
                      info[:js_args] << arg_len
                      info[:fun_args_decl] << [arg_buf, UInt32]
                      info[:fun_args_decl] << [arg_len, Int32]
                      unless ::JS::HELPERS[{:read, info[:type]}]
                        name = "__helper_#{::JS::HELPERS.size+1}"
                        body = "  function #{name.id}(pos, len) { // read String\n"
                        body += "    return __utf8Decoder.decode(new Uint8Array(__memory.buffer, pos, len));\n"
                        body += "  }"
                        ::JS::HELPERS[{:read, info[:type]}] = [name, body, false]
                      end
                      required_helpers << {:read, info[:type]}
                      info[:js_body] += "#{::JS::HELPERS[{:read, info[:type]}][0].id}(#{arg_buf}, #{arg_len})"
                      tmp_var = "__var#{var_counter += 1}"
                      info[:cr_prepare] += "#{tmp_var.id} = (#{info[:value].id})\n"
                      info[:cr_args] << "#{tmp_var.id}.to_unsafe.address.to_u32".id
                      info[:cr_args] << "#{tmp_var.id}.bytesize".id
                    elsif info[:type] == ::Class
                      constructor = piece.constant("JS_CONSTRUCTOR")
                      unless constructor
                        piece.raise "Type '#{piece}' must have the constant 'JS_CONSTRUCTOR' defined to be used as a metaclass on a JavaScript argument."
                      end
                      info[:js_body] += "#{constructor.id}"
                    else
                      piece.raise "Can't handle type '#{info[:type]}' as a JavaScript argument."
                    end

                    if types_to_process.size > 10
                      piece.raise "Can't handle type '#{type_information[:type]}' as a JavaScript argument, it is too deep."
                    end
                  end

                  types_to_expand.each do |info|
                    if info[:type] <= ::Enumerable
                      info[:type] = parse_type("Enumerable(#{info[:base_type][:type].id})").resolve
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
                      unless ::JS::HELPERS[{:read, info[:type]}]
                        name = "__helper_#{::JS::HELPERS.size+1}"
                        body = "  function #{name.id}(buf, size) { // read #{info[:type]}\n"
                        body += "    return Array.from({length: size}, () => {\n"
                        info[:base_type][:fun_args_decl].each_with_index do |(var, type), idx|
                          body += "      const #{info[:base_type][:js_args][idx]} = #{js_mem_read[type].gsub(/\$POS\$/, "buf").id};\n"
                          body += "      buf += #{type_size[type]};\n"
                        end
                        body += "      return #{info[:base_type][:js_body].id};\n"
                        body += "    });\n"
                        body += "  }"
                        ::JS::HELPERS[{:read, info[:type]}] = [name, body, false]
                      end
                      required_helpers << {:read, info[:type]}
                      info[:js_body] += "#{::JS::HELPERS[{:read, info[:type]}][0].id}(#{arg_buf}, #{arg_len})"
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

              return_type = method.return_type ? method.return_type.is_a?(Self) ? @type : method.return_type.resolve : Nil
              if return_type == Nil
                fun_ret = "Void".id
              elsif return_type < ::JS::Reference
                fun_ret = "Int32".id
                js_body = "return __make_ref((() => { #{js_body.id} })());"
              elsif [Int8, Int16, Int32, UInt8, UInt16, UInt32].includes? return_type
                fun_ret = return_type
              elsif return_type == Bool
                fun_ret = "UInt8".id
                js_body = "return (() => { #{js_body.id} })() ? 1 : 0;"
              elsif return_type == ::String
                fun_ret = "Void*".id
                unless ::JS::HELPERS[{:write, return_type}]
                  name = "__helper_#{::JS::HELPERS.size+1}"
                  body = "  function #{name.id}(str) { // write String\n"
                  body += "    const data = __utf8Encoder.encode(str);\n"
                  body += "    const ptr = __exports.__crystal_malloc_atomic(13 + data.byteLength);\n"
                  body += "    __memory.setUint32(ptr, __string_type_id, true);\n"
                  body += "    __memory.setUint32(ptr + 4, data.byteLength, true);\n"
                  body += "    __memory.setUint32(ptr + 8, str.length, true);\n"
                  body += "    for (let i = 0; i < data.byteLength; i++) {\n"
                  body += "      __memory.setUint8(ptr + 12 + i, data[i]);\n"
                  body += "    }\n"
                  body += "    __memory.setUint8(ptr + 12 + data.byteLength, 0);\n"
                  body += "    return ptr;\n"
                  body += "  }"
                  ::JS::HELPERS[{:write, return_type}] = [name, body, false]
                end
                required_helpers << {:write, return_type}
                js_body =  "return #{::JS::HELPERS[{:write, return_type}][0].id}((() => { #{js_body.id} })());"
              else
                method.return_type.raise "Can't handle type '#{return_type}' as a JavaScript return type."
              end

              pretty_name = "#{@type.id}#{method.receiver ? ".".id : "#".id}#{method.name.id}"
              js_code = "#{fun_name}(#{js_args.join(", ").id}) { // #{pretty_name.id} \n#{js_prepare.id} #{js_body.id} }"
              ::JS::FUNCTIONS << [fun_name, fun_args_decl, fun_ret, js_code, false, required_helpers]
            %}
            def \{{ method.receiver ? "#{method.receiver.id}.".id : "".id }}\{{ method.name }}(\{{
              *method.args.map_with_index do |arg, index|
                (
                  (index == method.splat_index ? "*" : "") +
                  "#{arg.name}" +
                  (arg.name != arg.internal_name ? " #{arg.internal_name}" : "") +
                  (arg.restriction.is_a?(Nop) ? "" : " : #{arg.restriction}") +
                  (arg.default_value.is_a?(Nop) ? "" : " = #{arg.default_value}")
                ).id
              end
            }}) : \{{method.return_type || Nil}}
              \\{%
                fun_name = \{{fun_name.stringify}}
                func = ::JS::FUNCTIONS.find {|x| x[0] == fun_name }
                func[4] = true
                func[5].each do |helper_id|
                  ::JS::HELPERS[helper_id][2] = true
                end
              %}

              \{{ cr_prepare.id }}

              \{% if [Int8, Int16, Int32, UInt8, UInt16, UInt32, Nil].includes? return_type %}
                ::LibJS.\{{ fun_name }}(\{{*cr_args}})
              \{% elsif return_type < ::JS::Reference %}
                ref = ::LibJS.\{{ fun_name }}(\{{*cr_args}})
                \{{return_type}}.new(::JS::Reference::ReferenceIndex.new(ref))
              \{% elsif return_type == ::String %}
                ::LibJS.\{{ fun_name }}(\{{*cr_args}}).as(::String)
              \{% elsif return_type == Bool %}
                ::LibJS.\{{ fun_name }}(\{{*cr_args}}) == 1
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
      include ::JS::ExpandMethods
    end
  end

  include ::JS::ExpandMethods

  macro export(method_def)
    \{% raise "JS.export can only be used at the top level" unless @type.name == "main" %}

    {%
      export_index = EXPORTS.size
      EXPORTS << [method_def.name, export_index]
    %}

    module JSExportHelpers
      {% arg_index = 0 %}
      {% for arg in method_def.args %}
        @[JS::Method]
        def self.__export_{{export_index}}_get_arg_{{arg_index}}(slot : Int32) : {{arg.restriction}}
          <<-js
            return __heap[#{slot}][{{arg_index}}];
          js
        end
        {% arg_index += 1 %}
      {% end %}

      @[JS::Method]
      def self.__export_{{export_index}}_set_result(slot : Int32, result : {{method_def.return_type || Nil}})
        <<-js
          __heap[#{slot}] = #{result};
        js
      end
    end

    {{ method_def }}

    fun __export_{{export_index}}(slot : Int32)
      {% arg_index = 0 %}
      {% for arg in method_def.args %}
        arg{{arg_index}} = JSExportHelpers.__export_{{export_index}}_get_arg_{{arg_index}}(slot)
        {% arg_index += 1 %}
      {% end %}

      result = {{ method_def.name }}({{*method_def.args.map_with_index { |arg, index| "arg#{index}".id }}})

      JSExportHelpers.__export_{{export_index}}_set_result(slot, result)
    end
  end
end

module JSExportHelpers
  include ::JS::ExpandMethods
end

private def generate_output_js_file
  {%
    output_file = env("CRYSTAL_JS_OUTPUT") || "index.js"
    target = env("CRYSTAL_JS_TARGET")
    target = "esm" if output_file.ends_with?(".mjs") && target.nil?
    target = "commonjs" if output_file.ends_with?(".cjs") && target.nil?
    target = "commonjs" if target.nil?

    js = <<-END
    const wasmSource = #{env("CRYSTAL_JS_WASM")};
    const isDenoRuntime = !!globalThis.Deno;
    const isNodeRuntime = !!globalThis.process;

    const __utf8Encoder = new TextEncoder();
    const __utf8Decoder = new TextDecoder("utf-8", { fatal: true });
    const __heap = [];
    const __free = [];
    let __memory;
    let __string_type_id;
    let __exports;

    function __make_ref(element) {
      const index = __free.length ? __free.pop() : __heap.length;
      __heap[index] = element;
      return index;
    }

    function __drop_ref(index) {
      __heap[index] = undefined;
      __free.push(index);
    }

    END

    ::JS::HELPERS.values.each do |helper|
      js += "\n#{helper[1].id}\n" if helper[2]
    end

    js += <<-END

    async function init() {
      if (__exports) return;

      const nodeCrypto = isNodeRuntime && #{target == "esm" ? "await import(\"node:crypto\")".id : "require(\"crypto\")".id};
      const nodeFsPromises = isNodeRuntime && #{target == "esm" ? "await import(\"node:fs/promises\")".id : "require(\"fs/promises\")".id};

      const imports = {
        env: {

    END

    ::JS::FUNCTIONS.each do |func|
      js += "      #{func[3].id},\n" if func[4]
    end

    js += <<-END
        },
        wasi_snapshot_preview1: {
          fd_close() {
            throw new Error("fd_close");
          },
          fd_fdstat_get(fd, buf) {
            if (fd > 2) return 8; // WASI_EBADF
            __memory.setUint8(buf, 4, true); // WASI_FILETYPE_REGULAR_FILE
            __memory.setUint16(buf + 2, 0, true);
            __memory.setUint16(buf + 4, 0, true);
            __memory.setBigUint64(buf + 8, BigInt(0), true);
            __memory.setBigUint64(buf + 16, BigInt(0), true);
            return 0;
          },
          fd_fdstat_set_flags(fd) {
            if (fd > 2) return 8; // WASI_EBADF
            throw new Error("fd_fdstat_set_flags");
          },
          fd_filestat_get(fd, buf) {
            if (fd > 2) return 8; // WASI_EBADF
            __memory.setBigUint64(buf, BigInt(0), true);
            __memory.setBigUint64(buf + 8, BigInt(0), true);
            __memory.setUint8(buf + 16, 4, true); // WASI_FILETYPE_REGULAR_FILE
            __memory.setBigUint64(buf + 24, BigInt(1), true);
            __memory.setBigUint64(buf + 32, BigInt(0), true);
            __memory.setBigUint64(buf + 40, BigInt(0), true);
            __memory.setBigUint64(buf + 48, BigInt(0), true);
            __memory.setBigUint64(buf + 56, BigInt(0), true);
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
            if (fd < 1 || fd > 2) return 8; // WASI_EBADF
            let bytes_written = 0;
            for (let i = 0; i < length; i++) {
              const buf = __memory.getUint32(iovs + i * 8, true);
              const len = __memory.getUint32(iovs + i * 8 + 4, true);
              bytes_written += len;
              if (isDenoRuntime) {
                Deno.writeAllSync(fd === 1 ? Deno.stdout : Deno.stderr, new Uint8Array(__memory.buffer, buf, len));
              } else if (isNodeRuntime) {
                const stream = fd === 1 ? process.stdout : process.stderr;
                stream.write(new Uint8Array(__memory.buffer, buf, len));
              } else {
                (fd === 1 ? console.log : console.error)(__utf8Decoder.decode(new Uint8Array(__memory.buffer, buf, len)));
              }
            }
            __memory.setUint32(bytes_written_ptr, bytes_written, true);
            return 0;
          },
          proc_exit(exitcode) {
            throw new Error("proc_exit " + exitcode);
          },
          random_get(buf, len) {
            if (isNodeRuntime) {
              nodeCrypto.randomBytes(len).copy(new Uint8Array(__memory.buffer, buf, len));
            } else {
              crypto.getRandomValues(new Uint8Array(__memory.buffer, buf, len));
            }
            return 0;
          },
          environ_get() {
            return 0;
          },
          environ_sizes_get(count_ptr, buf_size_ptr) {
            __memory.setUint32(count_ptr, 0, true);
            __memory.setUint32(buf_size_ptr, 0, true);
            return 0;
          },
          clock_time_get(clock_id, precision, time_ptr) {
            const time = BigInt((clock_id === 0 ? Date.now() : performance.now()) * 1000000);
            __memory.setBigUint64(time_ptr, time, true);
            return 0;
          },
        }
      };

      const { instance } =
        isDenoRuntime ?
          await WebAssembly.instantiate(await Deno.readFile(wasmSource), imports) :
        isNodeRuntime ?
          await WebAssembly.instantiate(await nodeFsPromises.readFile(wasmSource), imports) :
          await WebAssembly.instantiateStreaming(fetch(wasmSource), imports);

      __exports = instance.exports;
      __exports.memory.grow(1);
      __memory = new DataView(__exports.memory.buffer);
      __string_type_id = __exports.__js_bridge_get_type_id(0);
      __exports._start();
    }

    END

    if target == "esm"
      js += <<-END

      export default init;

      END

      ::JS::EXPORTS.each do |export|
        js += <<-END

        export function #{export[0].stringify.id}(...args) {
          const slot = __make_ref(args);
          __exports.__export_#{export[1]}(slot);
          const result = __heap[slot];
          __drop_ref(slot);
          return result;
        }

        END
      end

      js += <<-END

      if (import.meta.main || (isNodeRuntime && import.meta.url === (await import("node:url")).pathToFileURL(process.argv[1]).href)) {
        await init();
      }

      END
    else
      js += <<-END

      if (typeof exports === "object") {
        module.exports = init;
      } else {
        globalThis.init = init;
      }

      END

      ::JS::EXPORTS.each do |export|
        js += <<-END

        init.#{export[0].stringify.id} = (...args) => {
          const slot = __make_ref(args);
          __exports.__export_#{export[1]}(slot);
          const result = __heap[slot];
          __drop_ref(slot);
          return result;
        };

        END
      end

      js += <<-END

      if (isNodeRuntime && require.main === module) {
        init().catch(err => {
          console.error(err);
          process.exit(1);
        });
      }

      END
    end

    system("printf #{js} > #{env("CRYSTAL_JS_OUTPUT") || "index.js"}")
  %}
end

macro finished
  macro finished
    generate_output_js_file

    lib LibJS
      \{% for func in ::JS::FUNCTIONS %}
        \{{ "fun #{func[0]}(#{func[1].map { |(arg, type)| "#{arg} : #{type}".id }.join(", ").id}) : #{func[2]}".id }}
      \{% end %}
    end
  end
end

lib LibC
  fun __wasm_call_ctors
  fun __wasm_call_dtors
  fun __main_void : Int32
end

fun _start
  LibC.__wasm_call_ctors
  argv = {% begin %} {{ env("CRYSTAL_JS_WASM") || "" }}.to_unsafe {% end %}
  status = Crystal.main(1, pointerof(argv))
  LibC.exit(status) if status != 0
end

fun __js_bridge_get_type_id(type : Int32) : Int32
  case type
  when 0
    String::TYPE_ID
  else
    0
  end
end
