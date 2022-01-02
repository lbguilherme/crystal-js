require "json"

File.open("web.js", "w") do |js|
  js << <<-END
async function runCrystalApp(wasmHref) {
  const heap = [null, window];
  let instance;
  let mem;

  function wrap(element) {
    heap.push(element);
    return heap.length - 1;
  }

  function read_string(pos, len) {
    return String.fromCharCode(...new Uint8Array(mem.buffer, pos, len))
  }

  const imports = {
    env: {

END
  JSON.parse(ARGV[0]).as_a.each do |func|
    js << "      #{func[0]}: #{func[1]},\n"
  end
  js << <<-END
    },
    wasi_snapshot_preview1: {
      fd_close() { throw new Error("fd_close"); },
      fd_fdstat_get(fd, buf) {
        if (fd > 2) return 8;
        mem.setUint8(buf, 4); // WASI_FILETYPE_REGULAR_FILE
        mem.setUint16(buf + 2, 0);
        mem.setUint16(buf + 4, 0);
        mem.setBigUint64(buf + 8, BigInt(0));
        mem.setBigUint64(buf + 16, BigInt(0));
        return 0;
      },
      fd_fdstat_set_flags(fd) { if (fd > 2) return 8; throw new Error("fd_fdstat_set_flags"); },
      fd_filestat_get(fd, buf) {
        if (fd > 2) return 8;
        mem.setBigUint64(buf, BigInt(0));
        mem.setBigUint64(buf + 8, BigInt(0));
        mem.setUint8(buf + 16, 4); // WASI_FILETYPE_REGULAR_FILE
        mem.setBigUint64(buf + 24, BigInt(1));
        mem.setBigUint64(buf + 32, BigInt(0));
        mem.setBigUint64(buf + 40, BigInt(0));
        mem.setBigUint64(buf + 48, BigInt(0));
        mem.setBigUint64(buf + 56, BigInt(0));
        return 0;
      },
      fd_seek() { throw new Error("fd_seek"); },
      fd_write() { throw new Error("fd_write"); },
      proc_exit() { throw new Error("proc_exit"); },
      random_get(buf, len) {
        crypto.getRandomValues(new Uint8Array(mem.buffer, buf, len));
        return 0;
      },
    }
  };

  const wasm = await WebAssembly.instantiate(await (await fetch(wasmHref)).arrayBuffer(), imports);
  instance = wasm.instance;
  mem = new DataView(instance.exports.memory.buffer)
  instance.exports.__crystal_main(0, 0);
}

END
end
