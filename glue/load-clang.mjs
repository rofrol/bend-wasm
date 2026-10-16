// The backend of the plain-clang build (tools/clang-wasm/build.sh;
// glue/build.sh --clang appends it to bend-glue.mjs): an instance of
// lane.mod with the three host imports of patch 0004, all of module
// "bend" (docs/clang-wasm.md, "Host imports"), then its constructors.
//
// - write(fd, data, len): the bytes of fd 1 (stdout) and 2 (stderr), UTF-8,
//   cut into lines: stdout's to console.log, stderr's into lane.errs, as
//   Emscripten's print and printErr; all len bytes are taken;
// - exit(code): throws Exit, after the unfinished stderr line, if any;
// - now(): monotonic nanoseconds, from performance.now().
async function instantiate(lane) {
  let mem;
  const streams = [1, 2].map(() => ({ dec: new TextDecoder(), rest: "" }));
  const lines = [(line) => console.log(line), (line) => lane.errs.push(line)];
  const bend = {
    write: (fd, data, len) => {
      const i = fd - 1;
      if (i !== 0 && i !== 1) {
        return -1;
      }
      const s = streams[i];
      const text = s.rest + s.dec.decode(
        new Uint8Array(mem.buffer, data >>> 0, len >>> 0), { stream: true });
      const parts = text.split("\n");
      s.rest = parts.pop();
      parts.forEach(lines[i]);
      return len;
    },
    exit: (code) => {
      if (streams[1].rest !== "") {
        lane.errs.push(streams[1].rest);
        streams[1].rest = "";
      }
      throw new Exit(code);
    },
    now: () => BigInt(Math.round(now() * 1e6)),
  };
  const inst = await WebAssembly.instantiate(lane.mod, { bend });
  mem = inst.exports.memory;
  inst.exports.__wasm_call_ctors();
  return inst.exports;
}
