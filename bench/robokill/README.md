# Robokill benchmark: JS lane against the wasm glue

The question (TODO t-2czhzqqy): is the wasm build of Robokill's simulation,
through the glue (`glue/README.md`), faster than Bend's JS lane, which
Robokill's decision 0003 compares it against (p95 1.09 ms of step +
render + upload at 2,000 bodies in Chrome)? In Node, yes: wasm takes about
a third of the JS lane's time per frame at p50 and about a quarter at p95.
The Chrome numbers are still to be measured; `run.sh` measures them
(below).

## Files

- `build.sh`: both lanes into `dist/` (ignored), from
  `replay/robokill/step.bend` (Robokill's `spike/step.bend` at `63031ab`):
  `dist/step.mjs`, the JS lane (`scripts/bend step.bend -o step.mjs`, as
  Robokill builds it), and `dist/step.wasm.mjs`, the wasm lane
  (`glue/build.sh ... init,input_at,step,hash,render`).
- `node.sh` and `node-bench.mjs`: the paired Node benchmark.
- `main.js`, `index.html`, `serve.mjs`: Robokill's `spike/` page at commit
  `63031ab`, vendored, each with a header naming the source.
- `run.sh` and `summary.mjs`: the Chrome benchmark.
- `check.sh` and `check.mjs`: what can be checked without a browser.

## Edits to the vendored page

`diff <(git -C "$ROBOKILL" show 63031ab:spike/main.js) bench/robokill/main.js`
shows them; each is marked `bend-wasm:` in the code.

- `main.js`: `import G from "./dist/step.mjs"` became `?lane=js|wasm`
  (default `js`), imported in `main()` as `./dist/step.mjs` or
  `./dist/step.wasm.mjs`, so a failed import is posted like any error; an
  unknown lane is an error. The results carry `lane` and `load` (the
  import's time and, for wasm, the glue's `timings()`: read, compile,
  instantiate, `bend_init`); the error post carries `lane`. After the runs,
  `performance.measureUserAgentSpecificMemory()` (the page is cross-origin
  isolated) adds the tab's memory, JS and wasm (the 512 MiB corpus
  included), but not the GPU's, as `memory`. Chrome may resolve it only
  after its next garbage collection.
- `index.html`, `serve.mjs`: the header only. `serve.mjs` serves its own
  directory, so `dist/` here; the wasm is fetched by the glue as bytes,
  so its content type (`application/octet-stream`) does not matter.

## Node benchmark

`bench/robokill/node.sh` (about 90 s): both lanes in one process of the
SDK's Node, driven as `spike/main.js` drives them, without the GPU:
per frame `step` then `render` into a `Float32Array(16384)`, timed with
`performance.now()` (for wasm this includes the glue's copy into `out`);
the state hash every 1,000 frames outside the timed region, the final one
checked against RESULTS.md on both lanes. n = 500 and 2,000; 5 blocks,
each 10,000 frames from `init` on each lane, the lane order alternating
between blocks. `BLOCKS`, `FRAMES`, `SIZES` change that. Report in
`out/node.md`, raw numbers in `out/node.json`.

2026-10-16, bend 79df8d9 (v2.0.35), patches 0001-0003 (series
`29bf2961ef35fa51`), bun 1.4.2, emcc 6.0.10; Node 24.19.0 of the SDK;
Apple arm64 Mac, inside a herdr worker's sandbox (a shared machine).
ms per frame of step + render over all 50,000 frames per lane and n,
including JIT warm-up:

| n | lane | p50 | p95 | p99 | max | mean |
| --- | --- | --- | --- | --- | --- | --- |
| 500 | js | 0.181 | 0.312 | 0.510 | 12.673 | 0.199 |
| 500 | wasm | 0.060 | 0.066 | 0.098 | 0.718 | 0.062 |
| 2000 | js | 0.976 | 1.530 | 2.551 | 43.106 | 1.093 |
| 2000 | wasm | 0.306 | 0.359 | 0.501 | 7.104 | 0.315 |

Paired ratio wasm / JS, per block p50 / p95 (block 1, 3, 5 ran JS first):

| n | block 1 | block 2 | block 3 | block 4 | block 5 | median |
| --- | --- | --- | --- | --- | --- | --- |
| 500 | 0.309 / 0.178 | 0.346 / 0.291 | 0.344 / 0.285 | 0.330 / 0.244 | 0.345 / 0.180 | 0.344 / 0.244 |
| 2000 | 0.316 / 0.235 | 0.310 / 0.231 | 0.309 / 0.226 | 0.323 / 0.255 | 0.308 / 0.227 | 0.310 / 0.231 |

The median of the per-frame ratios is 0.337 (n = 500) and 0.313
(n = 2,000). Wasm's spread is small (p95 within 20% of p50); the JS
lane's p95 and max move with its garbage collector.

Loading, timed apart from the frames: the JS lane's import 1.2 ms; the
wasm lane's 122 ms, of which reading the 38 KB wasm 0.7 ms, compilation
0.4 ms, instantiation 1.2 ms and `bend_init` 117 ms (the runtime's setup:
corpus, allocator and stack; not broken down further). The glue's copy of
the F32 region into `out` (64 KiB) costs 1.1 µs.

## Chrome benchmark

Run outside the herdr worker sandbox (Chrome cannot start in it), on a Mac
with WebGPU, with the Chrome window in front (a hidden window slows its
animation frames):

```sh
bench/robokill/run.sh
```

It builds both lanes, then for each of 5 blocks (`BLOCKS`) runs the page
once per lane, alternating the order (JS first in odd blocks), the way
Robokill's RESULTS.md was measured: `node serve.mjs 8642
out/<block>-<lane>.json out/profile-<block>-<lane>
"lane=<lane>&n=500,2000&frames=10000"` serves this directory cross-origin
isolated, starts a separate Chrome with a fresh profile and V8's GC trace,
and exits once the page posts its results. (`QUERY` and `PORT` change the
query and port.) `summary.mjs` then writes `out/chrome.md`: step + upload
p50, p95, p99, max and frames over 4 ms per run, the medians over blocks,
each block's paired ratio wasm / JS, load times and memory. It fails if a
run reported an error, if the lanes' checkpoint hashes differ or if the
final ones are not RESULTS.md's. A run that never posts (a hung page)
leaves `serve.mjs` waiting; stop the job.

## Checks without a browser

`bench/robokill/check.sh` builds both lanes and runs `check.mjs`:

- `main.js` loaded as a module with stand-ins for the DOM it reads:
  `?lane=js` and `?lane=wasm` each import their lane (the wasm one
  compiles and instantiates) and, as Node has no WebGPU, post
  `{lane, error: "Error: WebGPU is not available ..."}`; `?lane=c` posts
  its error. These pass in the herdr worker sandbox.
- `serve.mjs` started without a Chrome profile: it serves `index.html`,
  `main.js` and every file of `dist/` byte for byte with the COOP/COEP
  headers, refuses a path outside its directory, and on a POST of results
  writes them and exits 0. This needs a local port, which the worker
  sandbox refuses (`listen EPERM`), so it was not run there; run
  `bench/robokill/check.sh` outside it. It listens on `PORT` (default
  8643); when that port is taken, pick another, e.g.
  `PORT=8645 sh bench/robokill/check.sh`.
