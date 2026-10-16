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
- [ ] Robokill headless replay in wasm: `spike/step.bend` of Robokill [t-byai25qu]
  (read-only, `63031ab`) through library mode; state hashes and `render`
  bytes equal native at every checkpoint of its 10,000-frame replays for
  n = 500 and 2,000.
- [ ] Wasm module plus JS glue with the JS lane's `G.*` shape (`init`, [t-2czhzqqy]
  `step`, `input_at`, `render` into a fixed exported F32 region viewed once,
  `hash`), and a Chrome benchmark against Robokill's JS lane (p95 1.09 ms at
  2,000 bodies); hand the result to Robokill's coordinator, whose decision
  0003 decides the switch.
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
- [ ] Mutation seeds for the differential harness (from the fast-code-llm [t-cec2xt5r]
  session's consult round `20261016-144453-a08f`): deliberately broken
  patches it must reject (truncated output, wrong exit code, integer width
  or signedness change, the `Env` calling-convention bug reintroduced,
  memory growth on, a leak breaking the 100,000-call bound, stale handle
  reuse); a mutant that passes means the harness is too weak.
- [ ] A per-patch ledger: Bend and Emscripten versions, patch series hash, [t-axd6nj7p]
  lane, program, stdout and exit hashes, verdict, append-only (same
  source).
- [ ] A held-out program set the patches are never tuned on (recursion [t-pbcfrie3]
  depth, allocation, strings, closures, numeric edges, long-lived state),
  run by the harness beside the 51 (same source).
