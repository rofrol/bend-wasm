# TODO

Plan and context: `docs/plan.md`.

## Next, in order

- [ ] Follow-up of t-oh4vht3i (found by run r-nmbu5kfx): the 5 s hang [t-jc2zvbct]
  guard is wall-clock, so under CPU contention (checks run in parallel)
  legitimate programs are killed and `tests/negative/run.sh`'s `env-abi`
  case reports three extra programs. A hang guard must not depend on load:
  bound CPU time instead (e.g. `ulimit -t` in the guard), keeping the same
  5 s source (`vendor/bend/gates/test.ts:136`), and report a guard kill as
  "timeout", never as a mismatch; show the negative check passing while
  another CPU-heavy check runs beside it.
- [ ] Requested by the user 2026-10-16: "the tab with wasm takes about 536 [t-5j4vdpgg]
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
- [ ] Audit for a CPU-sized wasm layout (read-only, a report in [t-ap3q3hvo]
  `docs/memory.md`): every use of `CUBE`, `CUBE_T`, `CUBE_LOG`, `LANES`,
  `RING_*`, `STAK_*`, `ALC_OFF`, `STAT_*`, `HEAP_OFF` on the CPU path of the
  pinned `comp.ts` with patches 0001-0003: masks and shifts, lane indexing
  by worker vs by task, whether one worker touches more than one lane's
  areas, the ring sentinel words, the meaning of `+ 10` and `> CUBE` in
  `corpus_lay`, whether any layout offset can reach observable output or
  hashes, the zeroing assumptions (`mmap` fresh-zero) on init and reset,
  and how much of the corpus a run actually touches (measure). End with
  the smallest patch shape for (a) a CPU-sized layout or (e) a split heap,
  and (b) a corpus without Emscripten's memset, with risks; no code change.
- [ ] Patch 0004 (or an extension of 0002), wasm memory, from the audit: [t-xes4fk35]
  CPU-sized layout under `__EMSCRIPTEN__`, the corpus from fresh linear
  memory without a memset, a fixed corpus sized from a stress run (the
  worst Robokill states, not the steady 39,040 words) with stated headroom
  and an explicit exhaustion error, `INITIAL_MEMORY` lowered to match.
  Gates: differential, negative, replay (hashes and render bytes), heap
  bound, deliberate exhaustion and lane-boundary tests the audit names.
- [ ] Memory measurement in the benchmark: report [t-2lsz77ug]
  `WebAssembly.Memory.buffer.byteLength`, `measureUserAgentSpecificMemory`
  and the renderer process's resident footprint from the OS (macOS), each
  after init and after the replay, at events the page posts; compare the
  JS lane; rerun the Chrome benchmark after the memory patch.
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
