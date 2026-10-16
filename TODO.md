# TODO

Plan and context: `docs/plan.md`.

## Next, in order

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
  From run r-s4pab6ns (library mode): Robokill threads its state through
  returns (`hash(s) -> State & U32`, `render(s, out) -> State &
  Array<F32>`, `step(s, +inp)`; `+` only on scalars, Robokill `63031ab`
  `spike/step.bend` 350-476), so library mode must return tuples of a
  handle and a scalar or an `Array<F32>`, and take an `Array<F32>` in;
  extend patch 0003 for that here. The borrow rule ("`+` parameter is
  borrowed by `term_keep`") is not exercised by Robokill; keep it, tested
  by `probe/lib`.
- [ ] Wasm module plus JS glue with the JS lane's `G.*` shape (`init`, [t-2czhzqqy]
  `step`, `input_at`, `render` into a fixed exported F32 region viewed once,
  `hash`), and a Chrome benchmark against Robokill's JS lane (p95 1.09 ms at
  2,000 bodies); hand the result to Robokill's coordinator, whose decision
  0003 decides the switch.
  Also (same round): define what happens after a wasm trap (the instance is
  poisoned: invalidate handles and re-instantiate, tested), and measure the
  tab's memory with the fixed 512 MiB corpus beside the game's WebGPU use.
  From run r-s4pab6ns: a misuse (stale handle, slot table full at
  `BEND_LIB_SLOTS` 4096) ends the process with `_exit(1)`, an unhandled
  `ExitStatus` in Node; decide here, with the trap rule, whether the glue
  turns it into a thrown JS error and a poisoned instance.
- [ ] Offer the patch series upstream on [t-yuiyk4uz]
  https://github.com/bendlang/bend/issues/1598 (the user approves the text
  first).
  Include the finding of run r-qvpqkr2n: the work-loop segments pass
  `Env e` (a two-pointer struct, `comp.ts` 2854, 3420) through `musttail`;
  wasm32/wasm64 pass it indirectly through the caller's frame, which the
  tail call frees, so `e.alc` read 0 (fixed in patch 0002 by passing two
  words); Windows x64 also passes 16-byte structs indirectly and may hit
  the same, unchecked.

- [ ] Requested by the user 2026-10-16: "bring in that loop as work to do, [t-ayhexs3c]
  the one from the fast-code-llm space; ask the models": an autoresearch
  loop like fast-code-llm's (`~/personal_projects/fast-code-llm/loop/`,
  its decision 0001: agents propose one patch, a gate of byte identity and
  laws on a per-run random corpus, a paired deterministic score, an
  append-only locked JSONL ledger with start and verdict records, seeds with
  known verdicts proving the gate rejects bad candidates), adapted to
  bend-wasm. Shape decided after a consult round; recorded here.
  Shape decided by the coordinator after consult round
  `20261016-145518-d5bf` (sol, mimo, deepseek, argon, wonder, all agreeing
  on these points):
  - Starts only after t-esggsei6 (heap bounded over 100,000 calls),
    t-oh4vht3i (negative checks), t-byai25qu (replay equal to native) and
    t-2czhzqqy (module, glue, Chrome baseline) are done and the score's
    paired noise is measured. Its target is the gap Robokill's decision
    0003 sets: wasm conformant and faster than the JS lane (p95 1.09 ms at
    2,000 bodies). If baseline wasm already beats it, rounds are capped and
    the incumbent stays default; the user is told before agent rounds run.
  - Candidate: one patch `patches/NNNN-*.patch` touching only the
    `__EMSCRIPTEN__` path of `comp.ts`, with flags and glue frozen (flags and
    glue are tuned by hand as separate experiments, never mixed into a
    candidate). Never touched: Robokill's repository, Bend semantics and
    the native/JS emitters, patches 0001 to 0003's contracts (the `Env`
    two-word ABI, generation-checked handles, the heap bound), the harness,
    generators, scorer, gate, ledger and seeds; memory size and growth,
    threads, SIMD, fast-math are not a candidate's to change.
  - Gate, in order: scope and frozen hashes checked, a ledger start record
    with a seed drawn after the candidate is frozen; clean build, wasm
    validates, imports/exports/memory unchanged, tail calls still
    `return_call`; invariants (negative checks, heap bound over 100,000
    calls, no traps); the 51-program differential on all lanes; a per-run
    corpus from the seed: seeded valid Robokill input traces compared per
    frame (state hash and render bytes) plus a held-out stress replay whose
    seed is revealed only for a provisional winner; then the score.
  - Score: instructions retired (`/usr/bin/time -l`) of the SDK's pinned
    Node running the wasm replay single-threaded, compilation excluded by
    an explicit phase boundary, incumbent and candidate paired and
    alternated in one run, advance only at >= 2% and above the measured
    paired noise. A provisional winner is confirmed in pinned headless
    Chrome with interleaved A/B blocks (p95 frame cost, memory); a Node win
    that Chrome does not confirm loses. Wasmtime fuel (wonder) is a
    possible deterministic meter but a new dependency: not now.
  - State: our own append-only locked JSONL ledger after fast-code-llm's
    `fcl.py` (start and verdict records, torn line dropped, interrupted run
    redone with its seed), copied, not shared; acceptance seeds with known
    verdicts: wrong-fast, slower, weakened invariant, memory inflation,
    replay recognition, escaping the allowed files, and a genuinely faster
    one.
  - Risks to guard: memoizing replay states, moving work outside the timed
    phase, speed bought with memory, ABI erosion, V8-only wins, unreadable
    patches that hurt the upstream offer (a diff-size cap).
  Split into worker items when its prerequisites are done.

## Needs a decision

## Proposed
