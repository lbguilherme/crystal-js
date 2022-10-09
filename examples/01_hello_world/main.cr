require "js"

JS.console.log "Hello World!"

JS.export def add(a : Int32, b : Int32) : Int32
  a + b
end

JS.export def concat(a : String, b : String) : String
  a + b
end
