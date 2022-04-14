# crystal-js

This library provides bindings to run a Crystal application in a JavaScript environment, such as Node.js or the Web. Using this it is possible to consume existing JavaScript API's inside Crystal when compiling for the WebAssembly target. It is similar to [`wasm-bindgen`](https://github.com/rustwasm/wasm-bindgen) from Rust.

This library and WebAssembly with Crystal is highly experimental and still in the early days. Please report bugs.

For a Web APIs bindings see [`crystal-web`](https://github.com/lbguilherme/crystal-web).

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     js:
       github: lbguilherme/crystal-js
   ```

2. Run `shards install`

3. Build your project with `lib/js/scripts/build.sh src/main.cr` Use the `--release` flag for an optimized build. This will produce two files: a `main.wasm` and a `main.js`.

You can run your project:

- with Deno: `deno run --allow-read main.js`
- with Node.js: `node main.js`
- on the Web: `<script defer src="main.js"></script>`

See [crystal-web-demo](https://github.com/lbguilherme/crystal-web-demo) for an example project.

## Usage

For basic usage you can `require "js"` and then use common JavaScript methods and classes from the `JS` module.

```crystal
require "js"

JS.console.log "Hello from the JavaScript!"
```

### Defining raw JavaScript methods

You can define special methods that run JavaScript code from Crystal. They can take parameters but their body must be a single string literal using interpolation to receive arguments:

```crystal
require "js"

module Test
  # You need to include this module. It won't add any new methods, all it will do
  # is expanding JavaScript methods you define.
  include JS::ExpandMethods

  # Mark JavaScript methods with this annotation. They must be fully typed and
  # be aware that not all types are supported yet.
  @[JS::Method]
  def self.add(first : Int32, second : Int32) : Int32
    # This is NOT a raw string interpolation. The notation here is used to pass
    # valid values to JavaScript land.
    <<-js
      return #{first} + #{second}; // This is JavaScript!
    js
  end
end

five = Test.add(2, 3) # Returns 5.
```

JavaScript methods are always defined in a class or module that includes `JS::ExpandMethods`. Their body must be a single string literal that interpolates values. The string is raw JavaScript code that will be used as is, and the interpolations are placeholders to receive values from Crystal land. The bridging managed by this library handles converting the values to the appropriate type based on the annotations. Splat arguments are supported. The following types are supported:

- `Int`, they become `number` on JavaScript land.
- `String`, they are converted to `string`. Only proper UTF-8 is supported.
- `Bool`, they become `boolean`.
- `Enumerable(T)`, such as `Array`, `Tuple`, `Hash`, etc. They are converted to an array of `T`'s conversion.

The return type restriction is used to convert the JavaScript return value to the corresponding Crystal type. Only `Int`, `String`, and `Bool` are supported for now.

Unions are not supported yet.

In some cases it may be better to keep the value on JavaScript land instead of converting it, and instead hold a reference to the value that can be used later. The `JS::Reference` class provides this interface. When used as an argument type or a return type, it does no conversion and returns a reference to the value. This class is abstract, you must define a subclass to handle your custom types. Here is a more complex example:

```crystal
require "js"

class MyObj < JS::Reference
  @[JS::Method]
  def self.new(data : String) : MyObj
    <<-js
      const pieces = #{data}.split(', ')

      return {                    // The value returned here will be held by MyObj
        pieces,                   // and can later be accessed using `#{self}`.
        length: pieces.length
      };
    js
  end

  @[JS::Method]
  def size : Int32
    <<-js
      return #{self}.length;
    js
  end

  @[JS::Method]
  def add_piece(piece : String)
    <<-js
      #{self}.pieces.push(#{piece.strip.as(String)}); // You can use complex Crystal expressions,
      #{self}.length += 1;                            // as long as you add `.as(type)` to it.
    js
  end
end

obj = MyObj.new("a, b, c")
p obj.size # => 3
obj.add_piece("d")
p obj.size # => 4
```

Only the methods that are actually called will be generated in the output `.js` file, thus it is fine to define lots of unused methods.

Additionally, there are some helper functions to facilitate creating bindings to existing JavaScript APIs. Use `js_getter`, `js_setter`, `js_property`, and `js_method` to define matching methods. For example:


```crystal
require "js"

class XMLHttpRequest < JS::Reference
  @[JS::Method]
  def self.new : self
    <<-js
      return new XMLHttpRequest();
    js
  end

  js_getter readyState : Int32    # defines a `ready_state` method.
  js_getter responseText : String
  js_getter status : Int32

  # defines `response_type` and `response_type=` methods.
  js_property responseType : String

  # methods can be overloaded
  js_method send
  js_method send(body : String)
  js_method open(method : String, url : String)

  # for the return type use a comma, not a colon.
  js_method getResponseHeader(header : String), String
end

req = XMLHttpRequest.new
req.open("GET", "https://example.com")
req.send
p req.response_text
```
