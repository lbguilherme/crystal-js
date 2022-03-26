require "../reference"

module JavaScript
  class String < Reference
    @[JavaScript::Method]
    def self.new(str : ::String) : self
      <<-js
        return #{str}
      js
    end

    js_method self.fromCharCode(*nums : UInt16), self
    js_method self.fromCodePoint(*nums : UInt32), self

    @[JavaScript::Method]
    def to_crystal : ::String
      <<-js
        return #{self}
      js
    end

    {% for op in %w[== != < > <= >= +] %}
      @[JavaScript::Method]
      def {{op.id}}(other : self) : Bool
        <<-js
          return #{self} {{op.id}} #{other}
        js
      end
    {% end %}

    js_getter length : Int32

    js_method at(index : Int32), String
    js_method charAt(index : Int32), String
    js_method codeCodeAt(index : Int32), UInt16
    js_method codePointAt(index : Int32), UInt32
    js_method concat(*str : String), String
    js_method concat(*str : ::String), String
    js_method endsWith(str : String), Bool
    js_method endsWith(str : ::String), Bool
    js_method endsWith(str : String, length : Int32), Bool
    js_method endsWith(str : ::String, length : Int32), Bool
    js_method includes(str : String), Bool
    js_method includes(str : ::String), Bool
    js_method includes(str : String, position : Int32), Bool
    js_method includes(str : ::String, position : Int32), Bool
    js_method indexOf(str : String), Int32
    js_method indexOf(str : ::String), Int32
    js_method indexOf(str : String, position : Int32), Int32
    js_method indexOf(str : ::String, position : Int32), Int32
    js_method lastIndexOf(str : String), Int32
    js_method lastIndexOf(str : ::String), Int32
    js_method lastIndexOf(str : String, position : Int32), Int32
    js_method lastIndexOf(str : ::String, position : Int32), Int32
    js_method localeCompare(str : String), Int32
    js_method localeCompare(str : ::String), Int32
    js_method localeCompare(str : String, locale : String), Int32
    js_method localeCompare(str : ::String, locale : String), Int32
    js_method localeCompare(str : String, locale : ::String), Int32
    js_method localeCompare(str : ::String, locale : ::String), Int32
    # js_method localeCompare(str : String, locale : String, options : ???), Int32
    # js_method match(regexp : Regex) : ???
    # js_method matchAll(regexp : Regex) : ???
    js_method normalize(), String
    js_method normalize(form : String), String
    js_method normalize(form : ::String), String
    js_method padEnd(length : Int32), String
    js_method padEnd(length : Int32, pad_string : String), String
    js_method padEnd(length : Int32, pad_string : ::String), String
    js_method padStart(length : Int32), String
    js_method padStart(length : Int32, pad_string : String), String
    js_method padStart(length : Int32, pad_string : ::String), String
  end
end
