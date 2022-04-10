# crystal-web

This is an early proof of concept. It demonstrates that it is possible to develop Web front-end applications using Crystal. This library exposes the DOM and other browser JavaScript API's.

![demo](demo.png)

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     web:
       github: lbguilherme/crystal-web
   ```

2. Run `shards install`

3. Build your project with `lib/web/scripts/build.sh src/main.cr` Use the `--release` flag for an optimized build. This will produce two files: a `main.wasm` and a `main.js`.

You can run your project:

- with Deno: `deno run --allow-read main.js`;
- with Node.js: `node main.js`;
- on the Web: `<script defer src="main.js"></script>`

See [crystal-web-demo](https://github.com/lbguilherme/crystal-web-demo) for an example project.

## Usage

For basic usage you can `require "web"` and then use DOM related classes and methods. The global `window` object will be accessible at `Web.window`.

```crystal
require "web"

Web.window.console.log("Hello from the Web!")
```

You can define special methods that run JavaScript code from Crystal. They can take parameters but their body must be a single string literal using interpolation to receive arguments:

```crystal
require "web"

module Test
  # You need to include this module. It won't add any new methods, all it will do
  # is expanding JavaScript methods you define.
  include JavaScript::ExpandMethods

  # Mark JavaScript methods with this annotation. They must be fully typed and
  # be aware that not all types are supported yet.
  @[JavaScript::Method]
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

More complex examples can be created using `JavaScript::Reference`, an abstract base class capable of holding references to JavaScript values.

```crystal
require "web"

class MyObj < JavaScript::Reference
  @[JavaScript::Method]
  def self.new(data : String) : MyObj
    <<-js
      const pieces = #{data}.split(', ')
      return {
        pieces,
        length: pieces.length
      };
    js
  end

  @[JavaScript::Method]
  def size : Int32
    <<-js
      return #{self}.length;
    js
  end

  @[JavaScript::Method]
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

Only the methods that are actually called will be generated in the output `web.js` file, thus it is fine to define usused methods.

## How to contribute?

- Help defining more standard DOM interfaces at `src/web/dom.cr` (good start)
- Build cool demos and examples with this library (awesome)
- Support more types for the bridge at `src/web/bridge.cr` (complex)
- Identify, report and/or fix bugs
