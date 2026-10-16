# TODO

Plan and context: `docs/plan.md`.

## Next, in order

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
- [ ] Requested by the user 2026-10-16: "see how Zig produces wasm output, [t-ci7r5qnc]
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
- [ ] Wasm memory, step 2 (from the same audit): under `__EMSCRIPTEN__` a [t-fkta2jvt]
  host layout without the device-only areas (ALC rows 8 MiB, Term stacks
  256 MiB; the host keeps `ALC[w]` static and stacks in `pool_stack`),
  rings only when `BANGS != 0` (fork programs use many rings, assigned per
  task; 28 measured with one worker), `corpus_lay`'s `> CUBE` (a GPU
  requirement) not applied on the host; then a corpus sized from a stress
  run of Robokill's worst states with stated headroom and an explicit
  exhaustion error, and `INITIAL_MEMORY` lowered to match (the audit puts
  Robokill's minimum near 331 KiB before headroom). Not a smaller
  `CUBE_T` (changes `!` fork order; `RING_WORDS` and `RING_LOG`'s 17 are
  tied to 128). Gates as step 1 plus the audit's lane-boundary,
  ring-near-full, stack-near-limit and exhaustion tests.
  Also (from run r-epvs73bi, decided by the coordinator): `probe/run.sh`'s
  pre-patch variants (`w32`, `w32-tc-grow`, `w64`, `w64-pthread`,
  `w64-web`) document the original probe, so they run on the pin
  (`BEND_PATCH=0`), and `w32-patched` on the series; `probe/run.sh` exits 0
  again with each variant's expected result stated; `docs/probe.md` says
  so. Step 1 left `INITIAL_MEMORY` at 528MB (wasm-ld needs 520.5 MiB for the
  static corpus); this step lowers it.
- [ ] Memory measurement in the benchmark: report [t-2lsz77ug]
  `WebAssembly.Memory.buffer.byteLength`, `measureUserAgentSpecificMemory`
  and the renderer process's resident footprint from the OS (macOS), each
  after init and after the replay, at events the page posts; compare the
  JS lane; rerun the Chrome benchmark after the memory patch.
- [ ] Freestanding wasm build beside Emscripten (from the Zig request, [t-nt66wuif]
  consult round `20261016-175818-a3e6`), after the memory patch and its
  measurement: first `-sSTANDALONE_WASM --no-entry` with Emscripten's own
  clang (argon; no second toolchain), else `clang --target=wasm32` from
  the pinned emsdk or `zig cc -target wasm32-freestanding -nostdlib`
  (pinned); one guard in the patch series, a minimal libc subset (mem*,
  an allocator over `memory.grow` for the IO paths), printing and effects
  as named host imports (unsupported ones absent, failing at link time),
  F32 math from vendored musl sources, never host `Math.*`. Gates: all of
  ours plus a bit-exact F32 math comparison against native and the JS
  lane, and `return_call` kept for every `musttail`. Promote it over
  Emscripten only if it passes every gate and is materially smaller in
  memory or binary size; otherwise record the result and keep Emscripten.
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
