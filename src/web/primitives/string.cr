module JavaScript
  class String < Reference
    @[JavaScript::Method]
    def self.new(str : ::String) : self
      <<-js
        return #{str}
      js
    end

    js_getter length : Int32

    js_method at(index : Int32), ::String
    js_method charAt(index : Int32), ::String
    js_method codeCodeAt(index : Int32), UInt16
    js_method codePointAt(index : Int32), UInt32
    #js_method concat(*str : ::String), ::String
    js_method endsWith(str : ::String), Bool
    js_method endsWith(str : ::String, length : Int32), Bool
  end
end
