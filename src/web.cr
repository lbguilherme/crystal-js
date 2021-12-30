require "./js"

module Web
  def self.window
    # 0 = null
    # 1 = window
    Window.new(1)
  end

  class EventTarget < JavaScript::Value
  end

  class Node < EventTarget
    method "appendChild", append_child(child : Node)
  end

  class Document < Node
  end

  class Element < Node
  end

  class HTMLElement < Node
  end

  class HTMLBodyElement < HTMLElement
  end

  class CanvasContext < JavaScript::Value
    setter font : String
    method "fillText", fill_text(text : String, x : Int32, y : Int32)
  end

  class HTMLCanvasElement < HTMLElement
    method "getContext", get_context(name : String), CanvasContext
  end

  class HTMLDocument < Document
    method "createElement", create_element(tagName : String), HTMLCanvasElement
    getter body : HTMLBodyElement
  end

  class Console < JavaScript::Value
    method log(message : String)
  end

  class Window < EventTarget
    getter console : Console
    getter document : HTMLDocument
    getter "innerWidth", inner_width : Int32
    getter "innerHeight", inner_height : Int32
  end
end
