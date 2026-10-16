# TODO

Plan and context: `docs/plan.md`.

## Next, in order

- [ ] Decision record `docs/decisions/0001-wasm-through-a-patched-emitter.md` [t-fushyjis]
  from DECISIONS.md "Wasm approach"; correct `docs/plan.md` "Known facts":
  the runtime has no tracing GC but frees affine values and refcounts shared
  ones (`heap_alloc`/`heap_free`, `term_keep`/`term_drop`, `comp.ts`
  4060-4120), and F32 arrays are contiguous u32 blocks (BUF, 2^c).
- [ ] Patch series infrastructure: `patches/NNNN-*.patch` applied by [t-u66qb3n7]
  `scripts/bend` to a cached copy of the pin, published by rename (as
  herdr-bend's `scripts/bend` and `toolchain-patch.py` do), `BEND_PATCH=0`
  runs the pin; a check that the series applies cleanly to exactly the
  pinned commit; each patch's header names the upstream change that retires
  it; documented in `docs/workflow.md`.
- [ ] Patch 0001, portable limits (unguarded, upstreamable): `SIZE_MAX` [t-sljw6rhm]
  checks on every u64-to-size_t length, `mmap(NULL)` when the hinted
  mapping fails, compile-time knobs for corpus and stack size with today's
  native defaults. Check: the differential harness, native vs JS lane,
  unchanged with and without the patch.
- [ ] Patch 0002, Emscripten (`#if defined(__EMSCRIPTEN__)`): wasm32, fixed [t-h3ak74p5]
  corpus mapped once with no in-place growth and an explicit exhaustion
  error, a small stack with an explicit bound check (Emscripten's
  `mprotect` is a stub), one worker forced, IO loop and sockets fail loudly
  when reached. Check: `probe/run.sh` programs run under Node with stdout
  and exit code identical to native; a deep-recursion and an exhaustion
  program fail with the explicit errors.
- [ ] Wasm lane in the differential harness (wasm32, `-mtail-call`, fixed [t-tidzr2vk]
  memory); every non-excluded program matches native byte for byte.
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
