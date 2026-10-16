// Wasm driver of the Robokill replay (replay/robokill/README.md): loads
// the Emscripten build of step.bend's library-mode C (patch 0003,
// replay/robokill/run.sh) and does what replay.c does, with the same
// output. Handles and the heap mark are u64, so they cross as BigInt.
// The F32 region is viewed once (memory growth is off, so the view stays
// valid), and the word `hash` writes its U32 into is allocated once.
// `node replay.mjs <step.mjs> [bound FRAMES]`.
const [path, mode, arg] = process.argv.slice(2);
const { default: load } = await import(new URL(path, `file://${process.cwd()}/`));
const m = await load();
m._bend_init();
const region = new Uint32Array(m.HEAPU8.buffer, m._bend_f32(), m._bend_f32_len());
const hp = m._malloc(4);
const out = [];
const say = (line) => {
  out.push(line);
  if (out.length >= 4096) flush();
};
const flush = () => {
  process.stdout.write(out.join("\n") + "\n");
  out.length = 0;
};
const hash = (s) => {
  const t = m._bend_def_hash(s, hp);
  return [t, m.HEAPU32[hp >> 2]];
};

function regionHash() {
  let h = 2166136261;
  for (let i = 0; i < region.length; i += 1) {
    h = Math.imul(h ^ region[i], 16777619) >>> 0;
  }
  return h;
}

function replay(n) {
  let s = m._bend_def_init(n, 12345);
  for (let fr = 0; ; fr += 1) {
    if (fr % 1000 === 0) {
      let h;
      [s, h] = hash(s);
      say(`n=${n} frame=${fr} hash=${h}`);
    }
    if (fr === 10000) break;
    s = m._bend_def_step(s, m._bend_def_input_at(fr));
    s = m._bend_def_render(s);
    say(`render n=${n} frame=${fr + 1} hash=${regionHash()}`);
  }
}

function bound(frames) {
  let s = m._bend_def_init(500, 12345);
  for (let fr = 0; fr < frames; fr += 1) {
    s = m._bend_def_step(s, m._bend_def_input_at(fr));
    s = m._bend_def_render(s);
    [s] = hash(s);
    if ((fr + 1) % (frames / 10) === 0) {
      say(`bound frame=${fr + 1} heap=${m._bend_heap_words()} handles=${m._bend_handles()}`);
    }
  }
}

if (mode === "bound") {
  bound(Number(arg));
} else {
  replay(500);
  replay(2000);
}
flush();
