require "../src/dom"

window = Web.window
console = window.console
document = window.document

console.log("Width: #{window.inner_width}")
console.log("Height: #{window.inner_height}")

canvas = document.create_element("canvas")
document.body.append_child(canvas)
ctx = canvas.get_context("2d")
ctx.font = "30px Arial"
ctx.fill_text("Hello World!", 10, 30)
