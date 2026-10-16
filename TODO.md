# TODO

Plan and context: `docs/plan.md`.

## Next, in order

- [ ] Persistent-state spike, patch 0003 (library mode, separate from the [t-esggsei6]
  portability patches): the emitter emits, for named definitions, exported
  C entry points with no `main()`; JS holds opaque handles (root table slot
  plus generation); a call consumes or borrows (borrow by `term_keep`), an
  explicit dispose frees; reuse of a consumed handle fails. Check: a counter
  state stepped 100,000 times across calls keeps the heap high-water mark
  bounded, natively and in wasm. Kill criterion (decided by the coordinator
  under d-fus365v2): if it does not stay bounded, stop and report to the
  user before any further wasm work.
- [ ] Negative checks (decided by the coordinator 2026-10-16 after consult [t-oh4vht3i]
  round `20261016-145116-5f6f`, under the user's d-pzyv4252 "ask the
  models"; narrowed from the fast-code-llm session's mutation seeds): the
  harness and library-mode checks must fail on (1) a mutant library build
  that leaks one term per step (the 100,000-call bound must trip), (2) reuse
  of a consumed or disposed handle (a clear error, never corruption), (3)
  patch 0002's `Env` fix reverted (the wasm lane must report the three
  programs), (4) an expected lane missing: today `BEND_PATCH=0` makes the
  wasm lane "not available" and the run still exits 0; a lane that should
  exist must fail the run. Mutants live as small patch files under
  `tests/negative/`, applied only by that check; no mutation framework.
- [ ] Robokill headless replay in wasm: `spike/step.bend` of Robokill [t-byai25qu]
  (read-only, `63031ab`) through library mode; state hashes and `render`
  bytes equal native at every checkpoint of its 10,000-frame replays for
  n = 500 and 2,000.
  Also (round `20261016-145116-5f6f`): the heap bound measured on this real
  `step` path over 100,000 calls and again at 1,000,000 (live handles and
  allocator high-water, stated ceilings); keep the first divergent frame's
  index and data when hashes differ.
- [ ] Wasm module plus JS glue with the JS lane's `G.*` shape (`init`, [t-2czhzqqy]
  `step`, `input_at`, `render` into a fixed exported F32 region viewed once,
  `hash`), and a Chrome benchmark against Robokill's JS lane (p95 1.09 ms at
  2,000 bodies); hand the result to Robokill's coordinator, whose decision
  0003 decides the switch.
  Also (same round): define what happens after a wasm trap (the instance is
  poisoned: invalidate handles and re-instantiate, tested), and measure the
  tab's memory with the fixed 512 MiB corpus beside the game's WebGPU use.
- [ ] Offer the patch series upstream on [t-yuiyk4uz]
  https://github.com/bendlang/bend/issues/1598 (the user approves the text
  first).
  Include the finding of run r-qvpqkr2n: the work-loop segments pass
  `Env e` (a two-pointer struct, `comp.ts` 2854, 3420) through `musttail`;
  wasm32/wasm64 pass it indirectly through the caller's frame, which the
  tail call frees, so `e.alc` read 0 (fixed in patch 0002 by passing two
  words); Windows x64 also passes 16-byte structs indirectly and may hit
  the same, unchecked.

## Needs a decision

## Proposed
