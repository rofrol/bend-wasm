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
  (`glue/build.sh ... init,input_at,step,hash,render`), the shipped
  browser-only build (`-sENVIRONMENT=web`, glue/README.md, "Build").
- `node.sh` and `node-bench.mjs`: the paired Node benchmark. It runs the
  Node-capable build of `dist/step.c` (`glue/build.sh --node` into
  `out/node-dist/`), after `glue/test/shipped.sh` checks that its wasm is
  the shipped one byte for byte.
- `main.js`, `index.html`, `serve.mjs`: Robokill's `spike/` page at commit
  `63031ab`, vendored, each with a header naming the source.
- `run.sh` and `summary.mjs`: the Chrome benchmark; `procs.mjs`: the
  renderer process's memory for `serve.mjs`.
- `check.sh` and `check.mjs`: what can be checked without a browser.

## Edits to the vendored page

`diff <(git -C "$ROBOKILL" show 63031ab:spike/main.js) bench/robokill/main.js`
shows them; each is marked `bend-wasm:` in the code.

- `main.js`: `import G from "./dist/step.mjs"` became `?lane=js|wasm`
  (default `js`), imported in `main()` as `./dist/step.mjs` or
  `./dist/step.wasm.mjs`, so a failed import is posted like any error; an
  unknown lane is an error. The results carry `lane` and `load` (the
  import's time and, for wasm, the glue's `timings()`: read, compile,
  instantiate, `bend_init`); the error post carries `lane`. `runOne` is
  async and each run carries `memory`, two marks (below, "Memory").
  On the wasm lane `WebAssembly.instantiate` is wrapped before the import
  to catch the instance's exported memory, as the glue does not hand it out.
- `index.html`: the header only.
- `serve.mjs`: serves its own directory, so `dist/` here; the wasm is
  fetched by the glue as bytes, so its content type
  (`application/octet-stream`) does not matter. It answers the page's
  memory marks (`POST /mark`) and starts Chrome with
  `--enable-blink-features=ForceEagerMeasureMemory`, so
  `measureUserAgentSpecificMemory()` resolves at once instead of after
  Chrome's next garbage collection.

## Memory

Each run records two marks, after `G.init` and after the replay (the
final checkpoint, state still live), outside the timed frames. At each
mark the page reads the wasm lane's `memory.buffer.byteLength` (null on
the JS lane) and `performance.measureUserAgentSpecificMemory()` (the
tab's JS and wasm memory, not the GPU's; it needs cross-origin isolation,
which `serve.mjs` gives), then posts `/mark` and waits for the reply:
`serve.mjs` reads the OS numbers while the page is idle and answers with
them. No wait is on time: the page waits for the reply, `serve.mjs` for
`ps` and `footprint` to exit.

The renderer (`procs.mjs`): Chrome on macOS starts its helper processes
from the browser process, which `serve.mjs` spawned, so it knows its PID.
`ps -A -ww -o pid=,ppid=,rss=,time=,command=` gives the process tree; the
candidates are the descendants of that PID with `--type=renderer` and
without `--extension-process`. A fresh profile on one URL has the page's
renderer and at most a spare one, which has run nothing, so the one with
the most CPU time is the page's; every candidate goes into the reply and
`summary.mjs` notes a mark with more than one. Its `rss` (KiB) is the
resident size; `footprint -p PID -j FILE -f bytes --noCategories` gives
`phys_footprint`, the number Activity Monitor shows as Memory (optional:
a missing footprint is a note, not a failure).

`summary.mjs` reports per n, lane and mark the median over blocks of the
four numbers (linear memory, tab, renderer RSS, renderer footprint), and
fails when a mark lacks one of the first three. When every check holds it
writes `out/baseline.json`, the emcc baseline the clang cutover is judged
against (DECISIONS.md, "When plain clang replaces emcc"): the toolchain,
browser and adapter, the shipped files of each lane (`step.mjs`; for wasm
`step.wasm.mjs`, `bend-glue.mjs`, `step.lib.mjs`, `step.lib.wasm`), each
raw and `gzip -9 -n`, with totals; the linear memory; the memory medians;
and the medians of step+upload p50 and p95 per lane and n. `run.sh`
deletes `out/` at its start, so a baseline to keep is copied out of it.

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
each block's paired ratio wasm / JS, the memory medians, load times and
the shipped sizes, and `out/baseline.json` ("Memory"). It fails if a
run reported an error, if the lanes' checkpoint hashes differ, if the
final ones are not RESULTS.md's or if a memory mark is incomplete. A run
that never posts (a hung page) leaves `serve.mjs` waiting; stop the job.

The coordinator's run, as a herdr job, from the repository root:

```sh
herdr-job run --name "robokill chrome benchmark" \
  --why "frame times, memory and the frozen emcc baseline (t-2lsz77ug)" \
  -- bench/robokill/run.sh
```

then `out/chrome.md` and `out/baseline.json` under `bench/robokill/`.

## Checks without a browser

`bench/robokill/check.sh` builds both lanes and runs `check.mjs`:

- `main.js` loaded as a module with stand-ins for the DOM it reads:
  `?lane=js` and `?lane=wasm` each import their lane (the wasm one,
  `dist/`'s browser-only glue, compiles and instantiates; the stand-in
  `fetch` answers its `file:` URL with the file) and, as Node has no
  WebGPU, post
  `{lane, error: "Error: WebGPU is not available ..."}`; `?lane=c` posts
  its error. These pass in the herdr worker sandbox.
- `serve.mjs` started without a Chrome profile: it serves `index.html`,
  `main.js` and every file of `dist/` byte for byte with the COOP/COEP
  headers, refuses a path outside its directory, and on a POST of results
  writes them and exits 0; a `/mark` without a Chrome is answered with
  `{error: "no Chrome started"}`. This needs a local port, which the worker
  sandbox refuses (`listen EPERM`), so it was not run there; run
  `bench/robokill/check.sh` outside it. It listens on `PORT` (default
  8643); when that port is taken, pick another, e.g.
  `PORT=8645 sh bench/robokill/check.sh`.
- `procs.mjs`: the renderer lookup on fabricated `ps` output (the busier
  renderer below the browser process, extension and other trees left
  out), and live on a child the check starts and ends, whose command line
  carries `--type=renderer`, with its footprint. The worker sandbox
  refuses `ps` (`spawn EPERM`); the check then prints `skipped:` for the
  live lookup and goes on.
- `summary.mjs` on fabricated results of three blocks: the memory table,
  `baseline.json`'s fields, and a failure without a baseline when a mark
  has no renderer. These pass in the worker sandbox.
