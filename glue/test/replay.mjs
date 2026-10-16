// Robokill's replay protocol through a lane module with the JS lane's
// shape (glue/README.md): the same host code for the JS lane (`scripts/bend
// step.bend -o step.mjs`) and the wasm glue (step.wasm.mjs), so the lanes
// differ by one import. Per frame it calls step and render as Robokill's
// spike/main.js does (a Float32Array(16384) that render fills) and prints
// "render n=500 frame=1 hash=..." with an FNV-1a hash of its 32-bit words;
// at frames 0, 1,000, ..., 10,000 it prints the state hash as
// spike/replay.bend does ("n=500 frame=0 hash=..."). The lines are those of
// replay/robokill's drivers. `node replay.mjs <lane module>`.
const [path] = process.argv.slice(2);
const { default: G } = await import(new URL(path, `file://${process.cwd()}/`));
const lines = [];

for (const n of [500, 2000]) {
  const out = new Float32Array(16384);
  const words = new Uint32Array(out.buffer);
  let s = G.init(n, 12345);
  for (let fr = 0; ; fr += 1) {
    if (fr % 1000 === 0) {
      const r = G.hash(s);
      s = r.fst;
      lines.push(`n=${n} frame=${fr} hash=${r.snd}`);
    }
    if (fr === 10000) {
      break;
    }
    s = G.step(s, G.input_at(fr));
    const r = G.render(s, out);
    s = r.fst;
    if (r.snd !== out) {
      throw new Error(`render returned another array at frame ${fr}`);
    }
    let h = 2166136261;
    for (let i = 0; i < words.length; i += 1) {
      h = Math.imul(h ^ words[i], 16777619) >>> 0;
    }
    lines.push(`render n=${n} frame=${fr + 1} hash=${h}`);
  }
}
process.stdout.write(lines.join("\n") + "\n");
