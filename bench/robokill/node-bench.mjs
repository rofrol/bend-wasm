// Paired step benchmark of Robokill's simulation in Node, no GPU
// (bench/robokill/README.md): the JS lane (`scripts/bend step.bend -o
// step.mjs`) against the wasm glue (glue/build.sh, step.wasm.mjs), both
// loaded in one process and driven by the same host code as Robokill's
// spike/main.js: per frame `step`, then `render` into a Float32Array(16384)
// (for wasm this includes the glue's copy of the F32 region into it),
// timed with performance.now(); the state hash at every 1,000th frame and
// at the end outside the timed region, checked against RESULTS.md.
//
// For each n, BLOCKS blocks; each block runs FRAMES frames from init on
// each lane, the lane order alternating between blocks. Prints a Markdown
// report: module load, compilation and instantiation times; p50, p95, p99,
// max and mean per lane over all blocks; each block's p50 and p95 and their
// paired ratio wasm / JS; the median of the per-frame ratios; and the cost
// of one 64 KiB Float32Array copy out of a wasm memory.
//
// `node node-bench.mjs <step.mjs> <step.wasm.mjs> [results.json]`;
// BLOCKS (default 5), FRAMES (10000) and SIZES ("500,2000") in the
// environment.
import { writeFileSync } from "node:fs";

const [jsPath, wasmPath, jsonPath] = process.argv.slice(2);
const blocks = Number(process.env.BLOCKS ?? 5);
const frames = Number(process.env.FRAMES ?? 10000);
const sizes = (process.env.SIZES ?? "500,2000").split(",").map(Number);
const FINAL = { 500: 603820250, 2000: 819172968 };
const url = (p) => new URL(p, `file://${process.cwd()}/`);

const t0 = performance.now();
const js = (await import(url(jsPath))).default;
const t1 = performance.now();
const wasmLane = await import(url(wasmPath));
const t2 = performance.now();
const lanes = { js, wasm: wasmLane.default };
// Drops a replay's last state. The wasm lane keeps a value until it is
// consumed or disposed (glue/README.md), and its fixed corpus fills after
// a few replays' states otherwise; the JS lane's collector frees it.
const drop = { js: () => {}, wasm: wasmLane.dispose };
const load = {
  js: { importMs: t1 - t0 },
  wasm: { importMs: t2 - t1, ...wasmLane.timings() },
};

// One replay of `frames` frames for n bodies; the per-frame times in ms.
function run(G, n, dispose) {
  const out = new Float32Array(16384);
  const ms = new Float64Array(frames);
  let state = G.init(n, 12345);
  let last = null;
  const checkpoint = () => {
    const r = G.hash(state);
    state = r.fst;
    last = r.snd;
  };
  for (let frame = 0; frame < frames; frame += 1) {
    if (frame % 1000 === 0) {
      checkpoint();
    }
    const a = performance.now();
    state = G.step(state, G.input_at(frame));
    const r = G.render(state, out);
    state = r.fst;
    ms[frame] = performance.now() - a;
  }
  checkpoint();
  dispose(state);
  if (frames === 10000 && FINAL[n] !== undefined && last !== FINAL[n]) {
    throw new Error(`n=${n}: final hash ${last}, RESULTS.md has ${FINAL[n]}`);
  }
  return ms;
}

const sorted = (xs) => Float64Array.from(xs).sort();
const q = (s, p) => s[Math.min(s.length - 1, Math.floor(p * s.length))];
const mean = (xs) => xs.reduce((a, b) => a + b, 0) / xs.length;
const median = (xs) => q(sorted(xs), 0.5);
const f3 = (x) => x.toFixed(3);

const results = { blocks, frames, sizes, load, runs: [] };
for (const n of sizes) {
  const per = { js: [], wasm: [] };
  for (let b = 0; b < blocks; b += 1) {
    const order = b % 2 === 0 ? ["js", "wasm"] : ["wasm", "js"];
    for (const lane of order) {
      per[lane].push(run(lanes[lane], n, drop[lane]));
    }
    console.error(`n=${n} block ${b + 1}/${blocks} (${order.join(", ")})`);
  }
  const all = {};
  const stat = {};
  for (const lane of ["js", "wasm"]) {
    all[lane] = sorted(per[lane].flatMap((x) => Array.from(x)));
    const s = all[lane];
    stat[lane] = {
      p50: q(s, 0.5), p95: q(s, 0.95), p99: q(s, 0.99), max: s[s.length - 1],
      mean: mean(s),
      blocks: per[lane].map((x) => {
        const t = sorted(x);
        return { p50: q(t, 0.5), p95: q(t, 0.95), max: t[t.length - 1] };
      }),
    };
  }
  const ratios = per.js.map((x, b) => ({
    p50: stat.wasm.blocks[b].p50 / stat.js.blocks[b].p50,
    p95: stat.wasm.blocks[b].p95 / stat.js.blocks[b].p95,
  }));
  const frameRatio = median(per.js.flatMap((x, b) =>
    Array.from(x, (v, i) => per.wasm[b][i] / v)));
  results.runs.push({ n, stat, ratios, frameRatio });
}

// The copy the glue's render does: the 16,384 floats of the F32 region
// into the host's Float32Array, here out of a wasm memory of 2 pages.
const mem = new WebAssembly.Memory({ initial: 2, maximum: 2 });
const region = new Float32Array(mem.buffer, 0, 16384);
const dst = new Float32Array(16384);
const reps = 20000;
for (let i = 0; i < reps; i += 1) {
  dst.set(region);
}
const c0 = performance.now();
for (let i = 0; i < reps; i += 1) {
  dst.set(region);
}
results.copyUs = (performance.now() - c0) / reps * 1000;

const lines = [
  `Node ${process.version}, ${blocks} blocks of ${frames} frames per lane and n,`
    + " lane order alternating; ms per frame of step + render (wasm: with"
    + " the copy into out).",
  "",
  `Load: JS lane import ${f3(load.js.importMs)} ms; wasm import`
    + ` ${f3(load.wasm.importMs)} ms, of which read ${f3(load.wasm.readMs)},`
    + ` compile ${f3(load.wasm.compileMs)}, instantiate`
    + ` ${f3(load.wasm.instantiateMs)}, bend_init ${f3(load.wasm.initMs)} ms.`,
  "",
  "| n | lane | p50 | p95 | p99 | max | mean |",
  "| --- | --- | --- | --- | --- | --- | --- |",
  ...results.runs.flatMap(({ n, stat }) => ["js", "wasm"].map((l) =>
    `| ${n} | ${l} | ${f3(stat[l].p50)} | ${f3(stat[l].p95)} |`
    + ` ${f3(stat[l].p99)} | ${f3(stat[l].max)} | ${f3(stat[l].mean)} |`)),
  "",
  "Per block (lane order js first in odd blocks): p50 / p95 per lane and the"
    + " paired ratio wasm / JS.",
  "",
  "| n | block | js p50 / p95 | wasm p50 / p95 | ratio p50 / p95 |",
  "| --- | --- | --- | --- | --- |",
  ...results.runs.flatMap(({ n, stat, ratios }) => ratios.map((r, b) =>
    `| ${n} | ${b + 1} | ${f3(stat.js.blocks[b].p50)} /`
    + ` ${f3(stat.js.blocks[b].p95)} | ${f3(stat.wasm.blocks[b].p50)} /`
    + ` ${f3(stat.wasm.blocks[b].p95)} | ${f3(r.p50)} / ${f3(r.p95)} |`)),
  "",
  ...results.runs.map(({ n, ratios, frameRatio }) => `n = ${n}: paired`
    + ` ratio wasm / JS, median over blocks: p50 ${f3(median(ratios.map((r) =>
      r.p50)))}, p95 ${f3(median(ratios.map((r) => r.p95)))}; median of the`
    + ` per-frame ratios ${f3(frameRatio)}.`),
  "",
  `Copy of the F32 region (16,384 floats, 64 KiB) into out:`
    + ` ${results.copyUs.toFixed(2)} us per call.`,
];
console.log(lines.join("\n"));
if (jsonPath !== undefined) {
  writeFileSync(jsonPath, JSON.stringify(results, null, 2) + "\n");
}
