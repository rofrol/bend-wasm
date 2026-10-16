// The backend of the Emscripten build (glue/build.sh appends it to
// bend-glue.mjs): an instance of lane.mod through the build's factory
// lane.load (NAME.lib.mjs), stderr lines into lane.errs, and proc_exit
// replaced so the library's _exit throws Exit.
async function instantiate(lane) {
  let fail;
  const failed = new Promise((_, reject) => {
    fail = reject;
  });
  let ex;
  await Promise.race([failed, lane.load({
    printErr: (line) => lane.errs.push(line),
    instantiateWasm: (imports, done) => {
      imports.env.proc_exit = (code) => {
        throw new Exit(code);
      };
      if (imports.wasi_snapshot_preview1 !== undefined) {
        imports.wasi_snapshot_preview1.proc_exit = imports.env.proc_exit;
      }
      WebAssembly.instantiate(lane.mod, imports).then((inst) => {
        ex = inst.exports;
        done(inst, lane.mod);
      }, fail);
      return {};
    },
  })]);
  return ex;
}
