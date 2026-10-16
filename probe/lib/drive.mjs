// Wasm driver of the persistent-state spike (probe/lib/README.md): loads
// the Emscripten build of counter.bend's library-mode C (patch 0003,
// probe/lib/run.sh) and does what drive.c does, with the same output.
// Handles and the heap mark are u64, so they cross as BigInt.
// `node drive.mjs <counter.mjs> [--misuse]`.
const [path, mode] = process.argv.slice(2);
const { default: load } = await import(new URL(path, `file://${process.cwd()}/`));
const m = await load();
const heap = () => m._bend_heap_words();
m._bend_init();
let s = m._bend_def_init(5);
console.log(`init heap ${heap()}`);
for (let i = 0; i < 100000; i += 1) {
  s = m._bend_def_step(s, i);
  if ((i + 1) % 10000 === 0) {
    const p = m._bend_def_peek(s) >>> 0;
    console.log(`step ${i + 1} peek ${p} heap ${heap()}`);
  }
}
m._bend_dispose(s);
console.log(`disposed heap ${heap()}`);
if (mode === "--misuse") {
  m._bend_def_peek(s);
  console.log("misuse not caught");
}
