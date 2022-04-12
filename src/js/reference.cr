require "./bridge"

module JS
  abstract class Reference
    record ReferenceIndex, index : Int32

    def initialize(@extern_ref : ReferenceIndex)
    end

    def inspect(io)
      to_s(io)
    end

    @[JS::Method]
    def finalize
      <<-js
        drop_ref(#{@extern_ref.index.as(Int32)});
      js
    end

    macro js_getter(decl)
      @[::JS::Method]
      def {{decl.var.stringify.underscore.id}} : {{decl.type}}
        <<-js
          return #{self}.{{decl.var.id}};
        js
      end
    end

    macro js_setter(decl)
      @[::JS::Method]
      private def internal_setter_{{decl.var.stringify.underscore.id}}(value : {{decl.type}})
        <<-js
          #{self}.{{decl.var.id}} = #{value};
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
      @[::JS::Method]
      def {{ call.receiver ? "#{call.receiver.id}.".id : "".id }}{{call.name.stringify.underscore.id}}({{*call.args}}) : {{ret}}
        <<-js
          return {{
            call.receiver.id == "self" ? "\#{#{@type}}".id :
            call.receiver ? raise("The receiver must be 'self'") :
            "\#{self}".id
          }}.{{call.name.id}}({{*call.args.map { |arg| "#{arg.class_name == "Splat" ? "...".id : "".id}\#{#{arg.class_name == "Splat" ? arg.exp.var : arg.var}}".id }}});
        js
      end
    end

    macro inherited
      private JS_CONSTRUCTOR = {{@type.stringify.split("::").last}};

      @[JS::Method]
      def dup : self
        <<-js
          return #{self};
        js
      end
    end
  end
end
