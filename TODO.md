# TODO

Plan and context: `docs/plan.md`.

## Next, in order

- [ ] Wasm lane in the differential harness (wasm32, `-mtail-call`, fixed [t-tidzr2vk]
  memory); every non-excluded program matches native byte for byte.
  Known from run r-t3hzaln6: with patches 0001 and 0002, 48 of 51 match on
  wasm32; `reg/nat_chain` and `run/bst_insert` run out of memory and
  `run/string_algorithms` overflows the stack on wasm32 and wasm64, also
  with a 1 GiB corpus or a 256 MiB stack, while the same C built natively
  with `-D__EMSCRIPTEN__` is correct: find the cause (a wasm-only runtime
  bug, not a size), never exclude them for being slow or big.
- [ ] Browser check: the pure probe program runs in a page without [t-2zouc2um]
  cross-origin isolation (single worker, no pthreads) with output identical
  to native; record the browsers tried (tail calls are an engine feature).
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

## Needs a decision

## Proposed
