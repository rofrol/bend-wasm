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
