require "./reference"
require "./string"

module JS
  class Console < JS::Reference
    js_method log(message : String)
    js_method log(message : ::String)
  end

  class_getter(console : Console) { get_console }

  @[JS::Method]
  private def self.get_console : Console
    <<-js
      return console;
    js
  end
end
