require "./bridge"

module JavaScript
  abstract class Reference
    record ReferenceIndex, index : Int32

    def initialize(@extern_ref : ReferenceIndex)
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
      @[::JavaScript::Method]
      def {{call.name.stringify.underscore.id}}({{*call.args}}) : {{ret}}
        <<-js
          return #{self}.{{call.name.id}}({{*call.args.map { |arg| "\#{#{arg.var}}".id }}});
        js
      end
    end
  end
end
