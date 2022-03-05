require "./reference"

module Web
  include JavaScript::ExpandMethods

  @@window : Window?

  @[JavaScript::Method]
  private def self.get_window : Window
    <<-js
      return window;
    js
  end

  def self.window
    @@window ||= get_window
  end

  abstract class EventTarget < JavaScript::Reference
  end

  abstract class Node < EventTarget
    js_method appendChild(child : Node)
  end

  abstract class Document < Node
  end

  abstract class Element < Node
  end

  abstract class HTMLElement < Node
  end

  class HTMLBodyElement < HTMLElement
  end

  class CanvasContext < JavaScript::Reference
    js_setter font : String
    js_method fillText(text : String, x : Int32, y : Int32)
  end

  class HTMLCanvasElement < HTMLElement
    js_method getContext(name : String), CanvasContext
  end

  class HTMLDocument < Document
    js_method createElement(tagName : String), HTMLCanvasElement
    js_getter body : HTMLBodyElement
  end

  class Console < JavaScript::Reference
    js_method log(message : String)
  end

  class Window < EventTarget
    js_getter console : Console
    js_getter document : HTMLDocument
    js_getter innerWidth : Int32
    js_getter innerHeight : Int32
  end
end
