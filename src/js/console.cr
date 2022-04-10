require "./reference"

module JS
  class Console < JS::Reference
    js_method log(message : String)
  end

  @@console : Console?

  @[JS::Method]
  private def self.get_console : Console
    <<-js
      return console;
    js
  end

  def self.console
    @@console ||= get_console
  end
end
