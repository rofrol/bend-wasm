# Decisions

Closed TODO items and the decisions made on them, newest last. Durable
architectural decisions go to `docs/decisions/` (AGENTS.md, Rule 5).

## Pinned toolchain (t-3fa5ws5p)

Done 2026-10-16 (run r-yzprvcca). Bend `v2.0.35` (`79df8d9`) is the
shallow submodule `vendor/bend`; Bun `1.4.2` is pinned in `scripts/bend`;
Emscripten is emsdk/SDK `6.0.10` (2026-09-21, the newest tag at least two
weeks old) in `~/.cache/bend-wasm/emsdk-6.0.10`, pinned in `scripts/emcc`,
with `EM_CACHE` in the repository's ignored `.cache/`. Details:
`docs/workflow.md`.

Decided by the user 2026-10-16 (d-6x44i4p5): herdr workers have no network
(empty `network.allowedDomains` with `strictAllowlist`), so the coordinator
does the network steps (the submodule, the SDK download) and a worker does
the rest offline. The SDK lives outside the repository for that reason.

## Emscripten probe (t-jk5jg2zk)

Done 2026-10-16 (run r-x6alm2ho). `probe/run.sh` rebuilds it; the report
is `docs/probe.md`. Both programs emit C and link to wasm32 and wasm64 with
build flags only, but no run matches native: the runtime reserves an 8 GiB
corpus (`comp.ts:5231`) with an address-hinted `mmap` (`corpus_map`,
`comp.ts:5175-5189`), which Emscripten refuses (`EINVAL` for any hint,
`emscripten_mmap.c:106-108`); on wasm32 the 64-bit size is also silently
truncated to 0. `-mtail-call` settles `musttail`. Nine blockers are
classified there (1 and 9 shim-able by flags, 2 to 4 emitter changes, 5 to
8 architectural for a browser page); 5 to 9 come from reading the code, not
from runs. The coordinator checked the `comp.ts` and Emscripten lines.
Whether to patch `comp.ts` goes back to the user (t-3oqripea).

## Worker folder checkout note (t-yposk2fd)

Done 2026-10-16 (run r-6ec5gs2q): `docs/workflow.md` says the coordinator
checks out `vendor/bend` in herdr's worker folder before dispatch and after a
pin move, since workers have no network.

## Upstream issue (t-ymygf5au)

Opened 2026-10-16 after the user approved the text (d-lmevgpkg):
https://github.com/bendlang/bend/issues/1598, with the probe's facts and the
questions from `docs/plan.md` (scope, guard macro or flag, single-thread
mode, heap knob with `mmap(NULL)`, JS-only effect seam).

## No comp.ts patch: the JS lane meets the budget (t-3oqripea)

The user decided 2026-10-16 (d-2dcnim2c) to patch `comp.ts` only if the JS
lane missed the game's frame budget. Robokill's value check (Robokill
`63031ab`, `spike/RESULTS.md`, checked by the coordinator): Bend 2.0.35's
JS lane in Chrome on an M1 Pro runs `step`+`render`+upload at p95 1.09 ms
for 2,000 bodies (budget 8 ms), with state hashes equal to the native build.
So no patch; per `docs/plan.md` wasm is now an experiment, not a roadmap.
The consult round `20261016-124353-d5c1` patch shape stays recorded in git
history of `TODO.md` should the question return.

## Wasm approach (d-fus365v2)

The user decided 2026-10-16: wasm is a must, the coordinator owns it, ask
the models. Consult round `20261016-125354-86b1` (sol, mimo, deepseek,
argon, wonder; all answered) agreed on the approach; the coordinator
checked its claims against `vendor/bend/bend2/comp.ts` and chose it:

- a separable patch series on the pinned Bend, applied to a cached copy:
  portable limits (unguarded, upstreamable), an Emscripten platform patch
  (wasm32, fixed corpus without in-place growth, explicit stack bound, one
  worker, unsupported IO failing loudly), and a library mode in the emitter
  as its own patch; never edits to generated C;
- prove persistent state across calls (bounded heap over 100,000 calls)
  before building the game bridge, with a kill criterion;
- JS holds opaque generation-checked handles, never raw terms; render data
  goes through a fixed exported F32 region with memory growth off;
- conformance: identical stdout and exit codes on the harness, identical
  state hashes and render bytes on Robokill's replays; the switch is
  Robokill's (its decision 0003): only if conformant and faster than the
  JS lane (p95 1.09 ms at 2,000 bodies).

Checked in the code: the runtime has no tracing GC but frees affine values
and refcounts shared ones (`comp.ts` 4060-4120), so a per-frame leak is not
a given but must be measured; F32 arrays are contiguous u32 blocks, so a
zero-copy F32 view is possible. Dismissed: raw 64-bit terms as JS handles
(argon), unsafe once a term moves or is freed; "arrays are trees" (argon),
wrong for this runtime.

## Differential harness (t-ucc65gif)

Done 2026-10-16 (run r-kihgd5qi): `tests/differential/run.sh` over 51
programs from Bend's tests (`corpus.txt`), native vs JS lane, all match;
the wasm lane is reserved. Registered as the herdr check `differential`.
Hang guard 5 s, as Bend's own gate for the same programs
(`vendor/bend/gates/test.ts:136`). Exclusions with reasons in
`tests/differential/README.md`. Finding: `tests/io/process_run.bend`
differs on the JS lane (reproduced outside the sandbox by the coordinator);
the upstream report is item t-gdvytox3.

## process_run JS-lane report (t-gdvytox3)

Posted 2026-10-16 after the user approved the text (d-vz6pvgnd): https://github.com/bendlang/bend/issues/1599.
The program stays excluded from the harness until upstream answers.

## Wasm decision record (t-fushyjis)

Done 2026-10-16 (run r-rzcz45w7): `docs/decisions/0001-wasm-through-a-patched-emitter.md`;
`docs/plan.md` "Known facts" corrected (no tracing GC, affine frees and
refcounts, F32 arrays as contiguous u32 blocks).

## Patch series infrastructure (t-u66qb3n7)

Done 2026-10-16 (run r-qjv263ne): `patches/NNNN-*.patch` (unified diffs
with a "Retired by:" header) go on a cached copy of the pin,
`.toolchain/<pin>-<series hash>`, published by rename; `BEND_PATCH=0` runs
the pin; `scripts/check-patches` is the herdr check `patches`. Convention in
`patches/README.md` and `docs/workflow.md`.

## Patch 0001, portable limits (t-sljw6rhm)

Done 2026-10-16 (run r-zyipygvj): `patches/0001-portable-limits.patch`
adds `BEND_CORPUS_BYTES` and `BEND_STACK_BYTES` (`-D` knobs, native
defaults), `size_fit` (an explicit "a size past the address space" error
instead of truncating any u64 length to size_t) and a `mmap(NULL)` fallback
in `corpus_map`. Native is byte-identical (the differential harness, with
and without the patch). Effect: wasm64 probe programs match native; wasm32
fails explicitly by default and matches native with a 512 MiB corpus and an
8 MiB stack. Open points went into TODO (t-vnargpue, t-h3ak74p5).

## Patch recipe whitespace (t-vnargpue)

Done 2026-10-16 (run r-6npk7ina): the recipe in `patches/README.md` pipes
`git diff` through `sed 's/^ $//'`, so patches pass the `whitespace` check
and still apply byte for byte (checked by regenerating 0001).

## Patch 0002, Emscripten (t-h3ak74p5)

Done 2026-10-16 (run r-t3hzaln6): `patches/0002-emscripten.patch`, all
under `__EMSCRIPTEN__`: explicit Term-stack room check (`WL_ROOM` against
`stk_end`, no guard page), corpus default 512 MiB derived from
`corpus_lay`'s check (arithmetic in the patch header), stack default 8 MiB
(decided by the coordinator), one worker forced, no in-place corpus growth
(ERR_HEAP), loud errors for blocking IO waits, helper-thread effects and
sockets. Native is byte-identical (harness 51/51 with and without the
series). Canonical wasm32 flags: `-std=c11 -O2 -mtail-call
-sALLOW_MEMORY_GROWTH=0 -sINITIAL_MEMORY=528MB` (`probe/run.sh`
`w32-patched`). 48 of 51 corpus programs match on wasm32; the 3 others
are in t-tidzr2vk. Open points: t-cqjfh5mc.

## Patch 0002 hardening (t-cqjfh5mc)

Done 2026-10-16 (run r-v4jtrhtn): every Term-stack push is covered under
Emscripten (segment frames by `WL_ROOM`; task entry always starts at the
stack base, `work_loop` callers pass `stk`/`io_stk`, at most 250 words,
within the 16 KiB slack; checked by the coordinator in `comp.ts` 4322-4415,
4450, 5255). `IO.random_u32` and `Process.run` compile on wasm and fail
loudly (they run on the helper thread); probes `random.bend` and
`process.bend`. The wasm stack default stays 8 MiB (coordinator's
decision, see the item).

## Wasm lane (t-tidzr2vk)

Done 2026-10-16 (run r-qvpqkr2n): `tests/differential/run.sh` has a wasm
lane (flags in `scripts/wasm-flags`, shared with `probe/run.sh`); all 51
programs match native on the JS and wasm lanes. The three earlier wasm
mismatches had one cause: the work-loop segments take `Env e` (two
pointers) through `musttail`, and wasm passes that struct indirectly
through the caller's frame, which the tail call frees, so `e.alc` read 0
(UBSan/SAFE_HEAP evidence in `docs/probe.md`; `comp.ts` 2854 and 3420
checked by the coordinator). Patch 0002 passes the two words instead under
Emscripten; native C is unchanged. The finding goes into the upstream
offer (t-yuiyk4uz).

## Browser check (t-2zouc2um)

Done 2026-10-16 (run r-4xcmyvtb): `probe/web/` builds `hello` and `arith`
for a plain page (wasm embedded, `file://`, no pthreads, no COOP/COEP).
Headless Chrome 155.0.8059.80: both match native, exit 0,
`crossOriginIsolated` false. Run by the coordinator outside the worker
sandbox (herdr job 20261016-144341-f941), since Chrome cannot start inside
it. Safari and Firefox not tried.

## fast-code-llm suggestions (d-pzyv4252)

The user 2026-10-16: bend-wasm is wasm for Bend for the Robokill space;
why guix? ask the models. The printer bench (guix-bend code) is dropped as
out of scope; mutation seeds, held-out set and ledger go to a consult round.
Consult round `20261016-145116-5f6f` (sol, mimo, deepseek, argon, wonder),
decided by the coordinator: no ledger (git and the harness summary with
toolchain and patch hash suffice; mimo, argon, wonder against), no held-out
set now (patches are diagnosis-driven; Robokill's replay is the held-out
test; revisit before claiming general compatibility upstream), narrowed
negative checks after library mode (TODO). Accepted extras: heap bound on
the real `step` path, first divergent frame kept, trap recovery, tab
memory with the 512 MiB corpus.

## Library mode spike, patch 0003 (t-esggsei6)

Done 2026-10-16 (run r-s4pab6ns): `bend P.bend -o P.c --lib a,b,c` emits C
with no `main()`, exporting `bend_init`, `bend_def_<name>`, `bend_dispose`
and a debug `bend_heap_words`. Non-scalar values cross as handles (slot in
the low 32 bits, generation in the high 32, type id checked); a `+`
parameter is borrowed by `term_keep`, any other handle is consumed.
Kill criterion not triggered: `probe/lib/counter.bend` stepped 100,000
times keeps the allocator's high-water at 16,512 words from the first
checkpoint on, natively and in wasm, with peeks equal to `main`; a
deliberate leak raises it by 12,288 words per 1,000 calls, so the meter
sees leaks. Ordinary programs emit byte-identical C (58 checked). Open
points went to t-byai25qu and t-2czhzqqy.

## Negative checks (t-oh4vht3i)

Done 2026-10-16 (run r-xg35kc6g): `tests/negative/run.sh` (herdr check
`negative`, about 2.5 min) applies mutants through `BEND_PATCH_EXTRA` (added
to the series and its hash, `patches/` untouched) and requires each to
fail for its reason: a per-step leak (high-water 94,336 to 815,232 words;
`probe/lib/run.sh` now fails when the last checkpoint exceeds the first),
a stale handle (clear error natively and in wasm; with liveness checks
removed the misuse test fails), the `Env` two-word fix reverted (exactly
the three programs fail on wasm), a missing lane (`LANES`, default
`js wasm`, a listed lane that cannot build fails the run; pin-only runs use
`BEND_PATCH=0 LANES=js`). The 5 s hang guard in `probe/lib/run.sh` was
agreed by the coordinator: test tooling, measured drivers 0.01 s native and
0.21 s wasm, same bound as the harness; no orphaned process left (checked).

## Robokill replay in wasm (t-byai25qu)

Done 2026-10-16 (run r-45s7wfbq): `replay/robokill/run.sh` runs Robokill's
`spike/step.bend` (vendored from Robokill `63031ab`, `fetch.sh` checks the
copy) through `--lib`: the 22 checkpoints are identical for `replay.bend`,
the native library driver and wasm; final hashes equal Robokill's
RESULTS.md (603820250 for n = 500, 819172968 for n = 2,000); render-byte
hashes equal native and wasm on all 20,000 frames. Heap on the real path
(n = 500, step + render + hash every frame): high-water 39,040 words and
one live handle from the first to the last checkpoint over 100,000 and
1,000,000 frames, native and wasm. Patch 0003 now returns tuples (extra
components through `r<i>` pointers) and passes `Array<F32>` through a
fixed library-owned region (`bend_f32`, `BEND_LIB_F32` default 16,384);
ordinary programs' C unchanged.

## Wasm module, glue and benchmark (t-2czhzqqy)

Done 2026-10-16 (run r-nmbu5kfx). `glue/build.sh` makes
`dist/step.wasm.mjs` with exactly the JS lane's `G.*` shape (opaque
handles, tuples `{fst, snd}`, `render` filling the caller's
`Float32Array` with one 64 KiB copy, about 1.2 us); a misuse or trap throws
a JS `Error` and poisons the instance until `await reset()`. Through the
glue, Robokill's replay prints the same 22 checkpoints (final hashes as
its RESULTS.md).

Chrome benchmark (decided by the user, d-zvnjtccs; run by the coordinator,
herdr job 20261016-165751-e290, `bench/robokill/run.sh` at 152e557, which
differs from the landed commit only in a check and its README): Chrome 155,
Apple M1 Pro, WebGPU `apple`/`metal-3`, cross-origin isolated, 5 blocks
with alternating lane order, 10,000 frames per run, lanes' hashes equal.
Median over blocks, step+upload ms:

| n | lane | p50 | p95 | p99 | max |
| --- | --- | --- | --- | --- | --- |
| 500 | js | 0.225 | 0.250 | 0.350 | 4.515 |
| 500 | wasm | 0.125 | 0.140 | 0.150 | 0.530 |
| 2000 | js | 0.985 | 1.075 | 1.135 | 1.535 |
| 2000 | wasm | 0.360 | 0.390 | 0.410 | 0.575 |

Paired wasm/JS ratio, median of blocks (p50 / p95): 0.556 / 0.540 at
n = 500, 0.363 / 0.362 at n = 2,000. Costs: the tab holds about 536 MiB
with wasm (the fixed corpus) against 4.5 to 15 MiB with JS; wasm load
157 to 362 ms, almost all `bend_init` (134 to 344 ms), against 6 to 40 ms
for the JS import. Node agreed (p95 ratio 0.23 to 0.24). The result goes
to Robokill's coordinator for its decision 0003.

## Disk guard (d-fi6mbciu)

2026-10-16: herdr refused to start t-jc2zvbct below 15 GiB free (9.8 GiB).
The user freed space (14 GiB free); the coordinator deleted the worker
folder's regenerable `.toolchain/` cache (2.0 GiB) under the standing
approval; 16 GiB free.

## CPU-time hang guard (t-jc2zvbct)

Done 2026-10-16 (run r-tbldnqua): `scripts/guard` bounds 5 s of CPU time
(`ulimit -t 5`, same source `vendor/bend/gates/test.ts:136`); a kill is
SIGXCPU, exit 152, reported as "timeout". Used by the differential, the
negative checks and `probe/lib`; the Chrome guard stays wall-clock. Nested
differential runs of the negative checks write to their own directory
(`DIFFERENTIAL_OUT`), which may also explain run r-nmbu5kfx's failure.
Both checks passed together beside a load average of 195. Limits: a
program that ignores SIGXCPU or sleeps without using CPU is not stopped.
No leftover process (checked by the coordinator).

2026-10-16, again (d-k4topq5i): 12.8 GiB free stopped the audit; the user
freed space (25 GiB free).

## Memory layout audit (t-ap3q3hvo)

Done 2026-10-16 (run r-clpmphs4): `docs/memory.md`. On the host the ALC
rows and Term stacks of the corpus are device-only; rings serve only `!`
fork programs; layout offsets never reach output or hashes (Robokill's hash
equal under five layouts); only the header and ring counters need zero;
runs touch under 0.4 MiB of the corpus. Found a bug in patch 0001: on
wasm32 the address hints truncate to NULL, so `bend_init` maps and zeroes
512 MiB 14 times (verified by the coordinator). A `.bss` corpus prototype
cut Node RSS from 573 to 53 MiB and `bend_init` from 140 to 0 ms. The
memory patch is split into steps 1 and 2 accordingly (t-uyjzq4hq,
t-fkta2jvt).

## Wasm memory step 1 (t-uyjzq4hq)

Done 2026-10-16 (run r-epvs73bi): patch 0001's `corpus_map` tries a hint
only when it fits a pointer (`hint <= UINTPTR_MAX`); under Emscripten
patch 0002 takes the corpus and the Term stack from zeroed static storage
(`.bss`), no `mmap`, no memset. Node, Robokill through the glue: RSS after
init about 568 to 48 MiB (bare Node 43.5), after the replay 313-578 to
51-58 MiB, `bend_init` 152-250 ms to 0.1-0.5 ms; linear memory unchanged
(553,648,128 bytes, `INITIAL_MEMORY` 528MB, 520.5 MiB needed). All gates
pass. `probe/run.sh`'s growth variants no longer link; fixed in step 2
(t-fkta2jvt).

## Wasm tab memory (536 MiB)

Requested by the user 2026-10-16: "the tab with wasm takes about 536
MiB, very bad; analyze it; maybe fast-code-llm helps here? ask the
models." (Chrome benchmark, DECISIONS.md "Wasm module, glue and
benchmark": wasm tab about 536 MiB against 4.5 to 15 MiB for the JS lane;
Robokill's real heap use is 39,040 words.)
Analysis by the coordinator 2026-10-16: two causes. (1) Emscripten
6.0.10's `mmap(MAP_ANONYMOUS)` does `memalign` then `memset(ptr, 0,
alloc_len)` (`system/lib/libc/emscripten_mmap.c`), so the whole corpus is
resident (Node replay peak RSS: wasm 616 MB, JS lane 202 MB, bare Node
43 MB) and `bend_init` takes 134 to 344 ms. (2) The corpus layout is
GPU-shaped: `CUBE_T` 128, `CUBE` 16,384 lanes, each with a ring (1,026
words) and a stack (2,048 words: 256 MiB), plus ALC; `corpus_lay`
requires `(span - HEAP_OFF) / (PAGE_LEN + 10) > CUBE`, so the minimum
corpus is about 409.5 MiB (`comp.ts` 3462-3497) while Robokill needs
0.3 MB of heap.
Decided by the coordinator after consult round `20261016-174158-ae98`
(sol, mimo, deepseek, argon, wonder; under the user's d-fus365v2 and this
request): the items below, in order; no memory growth (detaches JS views,
gains nothing once the corpus is small); fast-code-llm's loop is not used
to find the fix (a design decision a search would game, e.g. by
under-provisioning); later the loop (t-ayhexs3c) may tune lane count and
corpus size with memory as a score under these gates.

## What to take from Zig's wasm output

Requested by the user 2026-10-16: "see how Zig produces wasm output,
so that Bend can do it that way too; ask the models". Facts checked by
the coordinator: Zig 0.17.0 is installed (Homebrew); Bend 2.0.35 does not
use Zig. `zig cc -target wasm32-wasi -O2` on Bend's emitted C of
`probe/hello.bend` (patches 0001-0003): 20 errors (wasi-musl has no
signals and no true mmap without emulation flags); `-target
wasm32-freestanding`: stops at the first missing libc header
(`math.h`).
Decided by the coordinator after consult round `20261016-175818-a3e6`
(sol, mimo, deepseek, argon, wonder, agreeing; under the user's
d-fus365v2 and this request): what is worth copying from Zig is the
contract, not the toolchain: a freestanding module with explicit exports
and host imports (patch 0003's library mode is halfway there) and owning
memory (pages from `memory.grow` past `__heap_base`, zero by the spec, no
bulk memset). The 536 MiB is the runtime's layout, not the toolchain:
the memory items below come first, under Emscripten, to isolate it.
Rejected: wasm32-wasi through `zig cc` with emulation flags (re-enables
what patch 0002 removed, needs a WASI shim, the emulated mmap still
zeroes) and emitting wasm directly from Bend like Zig's own backend (a
new compiler backend, orthogonal to the memory bug, no upstream chance).
Next after the memory work: the freestanding build item below.

## Do we need Node.js

Requested by the user 2026-10-16: "do we need Node.js in Bend at
all? ask the models." Facts checked by the coordinator: the browser
product does not run Node; the Bend compiler runs on Bun 1.4.2; `emcc`
needs Node at build time (emsdk's `.emscripten` sets `NODE_JS`; its JS
passes run through it); our tests run the wasm in emsdk's Node
(differential wasm lane, replay, glue tests, Node benchmark); a bare
Node process is 43.5 MiB of the 48 MiB RSS measured after memory step 1.
Decided by the coordinator after consult round `20261016-194332-e124`
(sol, mimo, deepseek, argon, wonder, agreeing): the product needs no
Node, but the glue is built with `-sENVIRONMENT=web,node`, so the shipped
module carries Node branches (`fs`, `process`, ...) that strict bundlers
reject: fixed by the next item. Node stays at build time (emcc's JS
passes; `-sSTANDALONE_WASM` still runs emcc, argon) and as the test
runtime (the only V8, Chrome's engine, the sandbox can start); Bun
(JavaScriptCore) would change the engine tested and is not a
replacement. Node at build time goes only if a freestanding build with
plain `clang --target=wasm32` + `wasm-ld` replaces emcc.

## Bend's compiler in TypeScript

Requested by the user 2026-10-16: "rather weak that Bend's compiler
is TypeScript on Node? ask the models". Facts checked by the
coordinator: Bend 2.0.35's compiler is TypeScript (`bend2/*.ts`, about
12,700 lines) run by Bun (`#!/usr/bin/env bun`; our pin 1.4.2), not
Node; `main.ts` is also a Bun plugin and a Node import hook for
`import x from "./x.bend"`; upstream ships its release `bend` binary
built with `bun build --compile` (CHANGELOG, #1025); no self-hosting plan
found in its README, CHANGELOG or WONTFIX. The compiler is upstream's;
bend-wasm only pins it; it has no `package.json` or npm dependencies
(imports only `bun` and built-ins), so its supply chain is Bun itself.
Decided by the coordinator after consult round `20261016-194422-4983`
(sol, mimo, deepseek, argon, wonder, agreeing): the language is not a
material weakness here (build time only, Emscripten dominates the build,
TypeScript makes rebasing our `comp.ts` patches easier); keep the
upstream compiler; do not rewrite or port it (months, a permanent fork)
and do not ask upstream for a language change (it chose TypeScript for
the Bun/Node import hooks). The real risks are reproducibility and the
build's trust in Bun: the next item. A single compiled binary (`bun
build --compile`) only if a separate Bun install becomes a measured
burden (it embeds the same runtime; not a security gain).

## When plain clang replaces emcc

Requested by the user 2026-10-16: "when will the freestanding build
on plain clang --target=wasm32 replace emcc? ask the models". Today the
freestanding item sits after the memory work, the browser-only glue and
the reproducibility check, and replaces Emscripten only if it passes
every gate and is materially smaller; `-sSTANDALONE_WASM` still needs
emcc (and so Node), so only plain clang + wasm-ld removes emcc.
Decided by the coordinator after consult round `20261016-194631-afbb`
(sol, mimo, deepseek, argon, wonder): it is not a date. It comes after
the Chrome memory measurement (which freezes the emcc baseline) and the
build reproducibility check, then four freestanding steps (the item
below); the emcc lane ships until they pass. `-sSTANDALONE_WASM` is
dropped (it still runs emcc's driver, libc and glue; all five). The
browser-only glue item stays (cheap; the baseline must be clean). Cut
over cleanly when every criterion holds; keep emcc only as an unshipped
diagnostic build (ASSERTIONS, SAFE_HEAP); if the size criterion fails,
emcc stays and the result is recorded.

## Wasm memory step 2 (t-fkta2jvt)

Done 2026-10-16 (run r-55d4hhjj): under `__EMSCRIPTEN__` patch 0002 lays
out the corpus without the device-only areas, with rings only when
`BANGS != 0`, and requires two heap pages instead of `> CUBE` on the host;
`CUBE_T` stays 128; native C is unchanged. The default corpus is the layout
plus 1,280 heap pages: 4.2 times the high-water of 131 Robokill stress runs
(305 pages; two live states 481), 1.36 MiB for Robokill; programs with `!`
also get the rings (128.25 MiB); a too small corpus fails at start.
`scripts/wasm-flags` uses `-sINITIAL_HEAP=1MB` (decided by the coordinator:
the linker sizes memory per program, no growth; measured malloc 5.3 KiB)
instead of a fixed `INITIAL_MEMORY`. Node, Robokill: linear memory
553,648,128 to 11,534,336 bytes; RSS 46.1 MiB after init and 54.0 after
the replay (bare Node 42.3); `bend_init` 0.10-0.40 ms. New boundary probes
(deep/deep-fit, exhaust/exhaust-fit, forks, rings driver). Open points:
t-ouy36at5.

## Bend self-hosting and a wasm bootstrap seed

Requested by the user 2026-10-16: "what about making Bend's compiler
in Bend, and restoring the previous code from a wasm file it is built
into, with a small compiler in C, as Zig does; then it could be
rebuildable like Guix and Debian; ask the models". Facts checked by the
coordinator (GitHub API, ziglang/zig): `stage1/zig1.wasm` (3.2 MB) is
committed with `stage1/wasm2c.c` (122 KB) and `stage1/wasi.c`;
`bootstrap.c` builds wasm2c with the system C compiler, translates
zig1.wasm to zig1.c, builds zig1, which compiles the compiler's source to
zig2.c (C backend), then builds zig2. Bend 2.0.35's compiler is
TypeScript on Bun (DECISIONS.md, "Bend's compiler in TypeScript"). The
compiler is upstream's. Decided by the coordinator after consult round `20261016-194939-a5a8`
(sol, mimo, deepseek, argon, wonder, agreeing): not bend-wasm's work.
Self-hosting is an upstream language project (parser, module loader,
type and proof checker, emitters, I/O, data structures; estimated months
to a year; interaction nets suit a sequential, string-heavy compiler
poorly; argon, wonder). A committed wasm seed gives a portable bootstrap,
not Guix's full-source bootstrap (Guix packages Zig through a source chain
from its older C++ implementation instead of `zig1.wasm`, per sol and
argon; not verified by the coordinator) and not Debian source; it can be
reproducible if regenerated deterministically. Reproducibility of the
current build is already an item (TODO, "Build reproducibility"). Two proposals came out of
the round (TODO, Proposed).

The user 2026-10-16 (d-2r2p2k3m): the QuickJS check is approved (TODO);
the upstream self-hosting experiment proposal is not approved and dropped.

## Memory step 2 follow-up (t-ouy36at5)

Done 2026-10-16 (run r-tegfqq6m): on wasm the negative leak case accepts
the runtime's out-of-memory error as detection; `probe/lib` uses the
default corpus again; under `__EMSCRIPTEN__` the out-of-memory message is
"bend: out of memory: the corpus of N bytes is full; build with a bigger
-DBEND_CORPUS_BYTES=..." (native and JS text unchanged); stale "528 MB"
fixed. `probe/run.sh` needs `probe/exhaust.bend`'s expectation updated
(next follow-up).

## Exhaust probe expectation (t-fjpg2odo)

Done 2026-10-16 (run r-ovs2aiyz): `probe/exhaust.bend` expects the new wasm
out-of-memory message; `docs/probe.md` updated; `probe/run.sh` exits 0.

## Bend bootstrap project (d-lkclwjmw)

The user 2026-10-16: start a new project for a Zig-style bootstrap of
Bend as a fork; Claude to work in a new herdr space. Done by the
coordinator: branch `bootstrap` of the user's fork `rofrol/bend` (worktree
`~/personal_projects/bend/bend-bootstrap` of `~/personal_projects/bend/bend`,
from upstream main 234cb9b9), with the policy the user chose,
`AGENTS-bend.md` with `LAWS.bend` and `PROOF.bend` (copied from
`~/personal_projects/agents.md`, now `~/personal_projects/agent-kit`), a pointer in upstream's `AGENTS.md`, and
`BOOTSTRAP.md` (goal and context); commit 2ac9f72c, not pushed. Herdr
workspace `bend-bootstrap` (wD8), agent `bend-bootstrap` started with a
first prompt; bend-wasm does not coordinate it.

## Memory in Chrome and the frozen emcc baseline (t-2lsz77ug)

Done 2026-10-16: code in run r-2mymemna; the Chrome run by the coordinator
(user's d-2v35sch7, herdr job 20261016-201946-7171, `sh
bench/robokill/run.sh` at ab6139d; a first try failed with exit 126 because
`run.sh` is not executable). Chrome 155, M1 Pro, 5 blocks, 10,000 frames.
Step+upload ms, median over blocks: n = 500 JS p95 0.275, wasm 0.130;
n = 2,000 JS p50 0.960 p95 1.060, wasm p50 0.350 p95 0.370 (paired p95
ratio 0.500 and 0.349). Memory at n = 2,000 after the replay, MiB: linear
11.0 (wasm); tab (`measureUserAgentSpecificMemory`) JS 12.1, wasm 22.5
(was about 536 before the memory work); renderer RSS JS 208.6, wasm 150.1;
renderer footprint JS 110.1, wasm 45.2. Wasm load 17-67 ms in all
(`bend_init` 0.1-4.8 ms). Shipped bytes raw / gzip -9: JS lane 40,357 /
6,617; wasm lane 52,992 / 22,087 (`step.lib.wasm` 34,619 / 15,487).
Frozen emcc baseline for the clang cutover criteria (from
`bench/robokill/out/baseline.json`, which `run.sh` overwrites):

```json
{
 "shipped": {
  "js": {
   "files": {
    "step.mjs": {
     "raw": 40357,
     "gzip9": 6617
    }
   },
   "total": {
    "raw": 40357,
    "gzip9": 6617
   }
  },
  "wasm": {
   "files": {
    "step.wasm.mjs": {
     "raw": 1928,
     "gzip9": 648
    },
    "bend-glue.mjs": {
     "raw": 7087,
     "gzip9": 2729
    },
    "step.lib.mjs": {
     "raw": 9358,
     "gzip9": 3223
    },
    "step.lib.wasm": {
     "raw": 34619,
     "gzip9": 15487
    }
   },
   "total": {
    "raw": 52992,
    "gzip9": 22087
   }
  }
 },
 "linearMemoryBytes": 11534336,
 "memory": {
  "js": {
   "500": {
    "init": {
     "wasmMemoryBytes": null,
     "uaMemoryBytes": 801571,
     "rendererRssBytes": 197820416,
     "rendererFootprintBytes": 64488888
    },
    "replay": {
     "wasmMemoryBytes": null,
     "uaMemoryBytes": 12479063,
     "rendererRssBytes": 205881344,
     "rendererFootprintBytes": 105645568
    }
   },
   "2000": {
    "init": {
     "wasmMemoryBytes": null,
     "uaMemoryBytes": 12370208,
     "rendererRssBytes": 207683584,
     "rendererFootprintBytes": 106268160
    },
    "replay": {
     "wasmMemoryBytes": null,
     "uaMemoryBytes": 12669996,
     "rendererRssBytes": 218775552,
     "rendererFootprintBytes": 115492376
    }
   }
  },
  "wasm": {
   "500": {
    "init": {
     "wasmMemoryBytes": 11534336,
     "uaMemoryBytes": 12212393,
     "rendererRssBytes": 195362816,
     "rendererFootprintBytes": 63489464
    },
    "replay": {
     "wasmMemoryBytes": 11534336,
     "uaMemoryBytes": 23573878,
     "rendererRssBytes": 156598272,
     "rendererFootprintBytes": 46073272
    }
   },
   "2000": {
    "init": {
     "wasmMemoryBytes": 11534336,
     "uaMemoryBytes": 23408430,
     "rendererRssBytes": 157024256,
     "rendererFootprintBytes": 46220728
    },
    "replay": {
     "wasmMemoryBytes": 11534336,
     "uaMemoryBytes": 23589418,
     "rendererRssBytes": 157401088,
     "rendererFootprintBytes": 47416832
    }
   }
  }
 },
 "chromeStepUploadMs": {
  "js": {
   "500": {
    "p50": 0.23,
    "p95": 0.275
   },
   "2000": {
    "p50": 0.96,
    "p95": 1.06
   }
  },
  "wasm": {
   "500": {
    "p50": 0.12,
    "p95": 0.13
   },
   "2000": {
    "p50": 0.35,
    "p95": 0.37
   }
  }
 },
 "blocks": 5,
 "frames": 10000,
 "userAgent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36",
 "adapter": {
  "vendor": "apple",
  "architecture": "metal-3"
 }
}
```

## Browser-only shipped glue (t-3wp2nvda)

Done 2026-10-16 (run r-mqzurb3s, ae7bde5): `glue/build.sh` builds the
shipped module with `-sENVIRONMENT=web -sFILESYSTEM=0` and a fetch-only
wasm reader (`glue/read-web.mjs`); `--node` builds the Node-capable one
(`-sENVIRONMENT=web,node`, `glue/read-node.mjs`) for `glue/test`, the
differential run and the Node benchmark. `glue/test/shipped.sh` fails when
the shipped files name a Node API or when the two `.wasm` files differ
(wired into `glue/test/run.sh` and `bench/robokill/node.sh`). Checks
passed in the driver's verify (whitespace, patches, differential,
negative); the coordinator ran `bench/robokill/check.sh` (all ok) outside
the sandbox. `probe/web/run.sh` (unchanged by this run) failed at Chrome's
teardown; queued as t-xqgdbzz2. Open point from the worker: the Node
benchmark's out-of-memory at n = 2,000 (Proposed).

## Reproducible emitted C and Bun's revision pinned (t-3rs6ne3b)

Done 2026-10-16 (run r-5uysjpvz, bc293ec): `scripts/bend` pins Bun's
`bun --revision` (`1.4.2+50a8a8387`) and refuses another build;
`--toolchain` prints it. `tests/repro/run.sh` emits the C of 7 corpus
programs and Robokill's step library twice, each pass from a fresh
compiler copy with an empty Bun transpiler cache, the second in another
TZ, locale, cwd and TMPDIR, and requires identical bytes: it passes, and
fails on an injected timestamp (worker's check, not committed). The check
is not registered in `.herdr/checks.toml`.

## Type check of the patched compiler (t-dyxn2pn3)

Done 2026-10-16 (run r-tqd3miak, a3f46dc; first verify failed on the
differential temp-dir race, Proposed; re-verify passed; user's
d-qiadn2fv): `scripts/typecheck`
runs TypeScript 6.0.3 (on the pinned Bun) with `strict` over the patched
`bend2/*.ts`; the pinned Bend v2.0.35 has 8 type errors of its own
(`bend.ts` 2x TS2339, `safe.ts` 6x TS2345), recorded in
`tools/typecheck/baseline.txt`; the check fails only on errors beyond
them (shown failing on a patch with a type error). Pins in
`tools/typecheck/package-lock.json`, install in `docs/workflow.md`;
registered as the herdr check `typecheck`. The coordinator chose 6.0.3
over 7.x (the native Go port with per-platform binaries) to keep a
JavaScript tool run by the pinned Bun.

## Bend's compiler on QuickJS (t-xz35srdq)

Done 2026-10-16 (run r-qhxshnds, 7913706; user's d-2r2p2k3m): yes for
emitting C. `bun build --target=bun` of the patched compiler, run by
`qjs --stack-size 6M --std -m` (QuickJS 2026-06-04) with about 200 lines
of shims over QuickJS's `std`/`os` (process, a fake `Bun` object for the
guard, URL, a synchronous `node:fs` subset, path, url, os), emits C byte
identical to `scripts/bend` for `nat_native.bend` and Robokill's step
library; qjs about 1.1x and 3.8x slower than Bun. Walls: building a
binary (spawnSync, ~30-line shim, untried), running a program
(`bun:ffi`), `--verdict`, publish, page bundling. Reproduced by
`tools/quickjs/run.sh`; details in `docs/quickjs.md`. Follow-up in
Proposed.

## Node benchmark out of memory at n = 2,000 (t-m72ghzpf)

Done 2026-10-17 in run r-3pyo47m5 (0377339, t-fwjpak4c step D): the
cause was `bench/robokill/node-bench.mjs` never disposing a replay's last
state; the wasm lane keeps a value until it is consumed or disposed
(`glue/README.md`), so the fixed corpus filled after a few replays. It now
disposes it. The worker's Node run after the fix: p50 emcc 0.065/0.315 ms,
clang 0.066/0.314 ms (n = 500/2,000). Not rerun by the coordinator.
