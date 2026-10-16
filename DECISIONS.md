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
