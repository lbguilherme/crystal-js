require "json"

File.open(ENV["JAVASCRIPT_OUTPUT_FILE"] || "web.js", "w") do |js|
  js << <<-END
async function runCrystalApp(wasmHref) {
  const heap = [null];
  const free = [];
  let instance;
  let mem;

  function make_ref(element) {
    const index = free.length ? free.pop() : heap.length;
    heap[index] = element;
    return index;
  }

  function drop_ref(index) {
    if (index === 0) return;
    heap[index] = undefined;
    free.push(index);
  }

  function read_string(pos, len) {
    return String.fromCharCode.apply(null, new Uint8Array(mem.buffer, pos, len))
  }

  const imports = {
    env: {

END
  JSON.parse(ARGV[0]).as_a.each do |func|
    js << "      #{func},\n"
  end
  js << <<-END
    },
    wasi_snapshot_preview1: {
      fd_close() {
        throw new Error("fd_close");
      },
      fd_fdstat_get(fd, buf) {
        if (fd > 2) return 8;
        mem.setUint8(buf, 4, true); // WASI_FILETYPE_REGULAR_FILE
        mem.setUint16(buf + 2, 0, true);
        mem.setUint16(buf + 4, 0, true);
        mem.setBigUint64(buf + 8, BigInt(0), true);
        mem.setBigUint64(buf + 16, BigInt(0), true);
        return 0;
      },
      fd_fdstat_set_flags(fd) {
        if (fd > 2) return 8;
        throw new Error("fd_fdstat_set_flags");
      },
      fd_filestat_get(fd, buf) {
        if (fd > 2) return 8;
        mem.setBigUint64(buf, BigInt(0), true);
        mem.setBigUint64(buf + 8, BigInt(0), true);
        mem.setUint8(buf + 16, 4, true); // WASI_FILETYPE_REGULAR_FILE
        mem.setBigUint64(buf + 24, BigInt(1), true);
        mem.setBigUint64(buf + 32, BigInt(0), true);
        mem.setBigUint64(buf + 40, BigInt(0), true);
        mem.setBigUint64(buf + 48, BigInt(0), true);
        mem.setBigUint64(buf + 56, BigInt(0), true);
        return 0;
      },
      fd_seek() {
        throw new Error("fd_seek");
      },
      fd_write(fd, iovs, length, bytes_written_ptr) {
        if (fd < 1 || fd > 2) return 8;
        let bytes_written = 0;
        for (let i = 0; i < length; i++) {
          const buf = mem.getUint32(iovs + i * 8, true);
          const len = mem.getUint32(iovs + i * 8 + 4, true);
          bytes_written += len;
          (fd === 1 ? console.log : console.error)(read_string(buf, len));
        }
        mem.setUint32(bytes_written_ptr, bytes_written, true);
        return 0;
      },
      proc_exit() {
        throw new Error("proc_exit");
      },
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
