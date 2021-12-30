module Web
  module JavaScript
    LIB_FUNCTIONS = [] of Nil
    JS_FUNCTIONS  = [] of Nil

    class Value
      def initialize(@extern_ref : Int32)
      end

      macro getter(js_name, type_decl)
        {% unless type_decl.is_a? TypeDeclaration %}
          {% raise "expected a TypeDeclaration" %}
        {% end %}
        {% JS_GETTERS << {js_name.id, type_decl.var.id, type_decl.type} %}
      end

      macro getter(type_decl)
        getter({{type_decl.var}}, {{type_decl}})
      end

      macro setter(js_name, type_decl)
        {% unless type_decl.is_a? TypeDeclaration %}
          {% raise "expected a TypeDeclaration" %}
        {% end %}
        {% JS_SETTERS << {js_name.id, type_decl.var.id, type_decl.type} %}
      end

      macro setter(type_decl)
        setter({{type_decl.var}}, {{type_decl}})
      end

      macro method(call)
        {% JS_METHODS << {call.name, call.name, call.args, Nil} %}
      end

      macro method(arg1, arg2 = nil, arg3 = nil)
        {%
          a = 0
          if arg1.class_name == "Call"
            call = arg1
            js_name = call.name
            return_type = arg2 || Nil
          elsif arg2.class_name == "Call"
            js_name = arg1
            call = arg2
            return_type = arg3 || Nil
          else
            raise "expected a Call"
          end

          JS_METHODS << {js_name.id, call.name, call.args, return_type}
        %}
      end

      macro inherited
        JS_GETTERS = [] of Nil
        JS_SETTERS = [] of Nil
        JS_METHODS = [] of Nil

        macro finished
          \{% for getter in JS_GETTERS %}
            \{%
              js_name, cr_name, return_type = getter
              fun_name = "__js_#{@type.name.gsub(/^Web::/, "").id}_getter_#{js_name}".id
              return_type = return_type.resolve
              raw_return_type = if [Int8, Int16, Int32, UInt8, UInt16, UInt32].includes? return_type
                return_type
              elsif return_type.ancestors.includes? Web::JavaScript::Value
                Int32
              else
                Nil
              end
              JavaScript::LIB_FUNCTIONS << {fun_name, ["extern_ref : Int32".id] of Nil, raw_return_type.id}
            %}
            def \{{cr_name}} : \{{return_type}}
              \{% if [Int8, Int16, Int32, UInt8, UInt16, UInt32].includes? return_type %}
                \\{% JavaScript::JS_FUNCTIONS << \{{[fun_name.stringify, "obj => heap[obj].#{js_name}"]}} %}
                LibJavaScript.\{{fun_name}}(@extern_ref)
              \{% elsif return_type.ancestors.includes? Web::JavaScript::Value %}
                \\{% JavaScript::JS_FUNCTIONS << \{{[fun_name.stringify, "obj => wrap(heap[obj].#{js_name})"]}} %}
                ref = LibJavaScript.\{{fun_name}}(@extern_ref)
                \{{return_type}}.new(ref)
              \{% else %}
                \{% raise "don't know how to return type #{return_type}" %}
              \{% end %}
            end
          \{% end %}

          \{% for setter in JS_SETTERS %}
            \{%
              js_name, cr_name, type = setter
              fun_name = "__js_#{@type.name.gsub(/^Web::/, "").id}_setter_#{js_name}".id
              type = type.resolve

              raw_args = ["extern_ref : Int32".id]
              raw_values = ["@extern_ref".id]
              js_raw_args = [] of Nil
              js_raw_value = nil

              if type == String
                raw_args << "arg0 : UInt32".id << "arg1 : UInt32".id
                raw_values << "value.to_unsafe.address".id << "value.bytesize".id
                js_raw_args << "arg0".id << "arg1".id
                js_raw_value = "read_string(arg0, arg1)".id
              elsif [Int8, Int16, Int32, UInt8, UInt16, UInt32].includes? type
                raw_args << "arg0 : #{type.id}".id
                raw_values << "value".id
                js_raw_args << "arg0".id
                js_raw_value = "arg0".id
              elsif type.ancestors.includes? Web::JavaScript::Value
                raw_args << "arg0 : UInt32".id
                raw_values << "value.@extern_ref".id
                js_raw_args << "arg0".id
                js_raw_value = "heap[arg0]".id
              else
                raise "don't know how to handle argument #{arg}"
              end

              JavaScript::LIB_FUNCTIONS << {fun_name, raw_args, Nil}
            %}
            def \{{"#{cr_name.id}=".id}}(value : \{{type}}) : Nil
              \\{% JavaScript::JS_FUNCTIONS << \{{[fun_name.stringify, "(obj, #{js_raw_args.join(", ").id}) => heap[obj].#{js_name} = #{js_raw_value.id}"]}} %}
              LibJavaScript.\{{fun_name}}(\{{*raw_values}})
            end
          \{% end %}

          \{% for method in JS_METHODS %}
            \{%
              js_name, cr_name, args, return_type = method
              fun_name = "__js_#{@type.name.gsub(/^Web::/, "").id}_call_#{js_name}".id
              return_type = return_type.resolve
              raw_return_type = if [Int8, Int16, Int32, UInt8, UInt16, UInt32].includes? return_type
                return_type
              elsif return_type.ancestors.includes? Web::JavaScript::Value
                Int32
              else
                Nil
              end
              raw_args = ["extern_ref : Int32".id]
              raw_values = ["@extern_ref".id]
              js_raw_args = [] of Nil
              js_raw_values = [] of Nil
              i = 0
              args.each do |arg|
                type = arg.type.resolve
                if type == String
                  raw_args << "arg#{i} : UInt32".id << "arg#{i+1} : UInt32".id
                  raw_values << "#{arg.var}.to_unsafe.address".id << "#{arg.var}.bytesize".id
                  js_raw_args << "arg#{i}".id << "arg#{i+1}".id
                  js_raw_values << "read_string(arg#{i}, arg#{i+1})".id
                  i += 2
                elsif [Int8, Int16, Int32, UInt8, UInt16, UInt32].includes? type
                  raw_args << "arg#{i} : #{type.id}".id
                  raw_values << "#{arg.var}".id
                  js_raw_args << "arg#{i}".id
                  js_raw_values << "arg#{i}".id
                  i += 1
                elsif type.ancestors.includes? Web::JavaScript::Value
                  raw_args << "arg#{i} : UInt32".id
                  raw_values << "#{arg.var}.@extern_ref".id
                  js_raw_args << "arg#{i}".id
                  js_raw_values << "heap[arg#{i}]".id
                  i += 1
                else
                  raise "don't know how to handle argument #{arg}"
                end
              end
              JavaScript::LIB_FUNCTIONS << {fun_name, raw_args, raw_return_type.id}
            %}
            def \{{cr_name}}(\{{*args}}) : \{{return_type}}
              \{% if [Int8, Int16, Int32, UInt8, UInt16, UInt32, Nil].includes? return_type %}
                \\{% JavaScript::JS_FUNCTIONS << \{{[fun_name.stringify, "(obj, #{js_raw_args.join(", ").id}) => heap[obj].#{js_name}(#{js_raw_values.join(", ").id})"]}} %}
                LibJavaScript.\{{fun_name}}(\{{*raw_values}})
              \{% elsif return_type.ancestors.includes? Web::JavaScript::Value %}
                \\{% JavaScript::JS_FUNCTIONS << \{{[fun_name.stringify, "(obj, #{js_raw_args.join(", ").id}) => wrap(heap[obj].#{js_name}(#{js_raw_values.join(", ").id}))"]}} %}
                ref = LibJavaScript.\{{fun_name}}(\{{*raw_values}})
                \{{return_type}}.new(ref)
              \{% else %}
                \{% raise "don't know how to return type #{return_type}" %}
              \{% end %}
            end
          \{% end %}
        end
      end
    end
  end
end

def final
  {% run("#{__DIR__}/generate_js", Web::JavaScript::JS_FUNCTIONS.stringify.gsub(/ of Nil/, "")) %}
end

macro finished
  macro finished
    final

    lib LibJavaScript
      \{% for func in Web::JavaScript::LIB_FUNCTIONS %}
        \{{ "fun #{func[0]}(#{func[1].map(&.id).join(", ").id}) : #{func[2]}".id }}
      \{% end %}
    end
  end
end
