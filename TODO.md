# TODO

Plan and context: `docs/plan.md`.

## Next, in order

- [ ] Memory measurement in the benchmark: report [t-2lsz77ug]
  `WebAssembly.Memory.buffer.byteLength`, `measureUserAgentSpecificMemory`
  and the renderer process's resident footprint from the OS (macOS), each
  after init and after the replay, at events the page posts; compare the
  JS lane; rerun the Chrome benchmark after the memory patch.
  This run freezes the emcc baseline for the clang cutover criteria
  (shipped wasm and JS sizes raw and gzip, linear memory, Chrome p95).
- [ ] Browser-only shipped glue (from the Node question): build the shipped [t-3wp2nvda]
  module with `-sENVIRONMENT=web` (and `-sFILESYSTEM=0` if nothing uses a
  file system), audit `step.wasm.mjs` and the Emscripten glue for
  `require`, `process`, `Buffer`, `fs`, `path`, `__dirname`, `node:`; the
  Node tests may use a Node-capable build of the same C, but the `.wasm`
  bytes of the shipped and the tested build must be identical (a check),
  and the shipped glue must load in the Chrome page (`bench/robokill`,
  `probe/web`).
- [ ] Build reproducibility (from the compiler question): `scripts/bend` [t-3rs6ne3b]
  checks Bun's exact build (`bun --revision`, not only the version) and
  `--toolchain` prints it; a check emits the C of a few programs twice
  from clean caches (and with the patch series) and requires byte-identical
  output, so ordering or environment inputs in the emitter would show.

- [ ] Type-check the patched compiler (`tsc --noEmit` over the patched [t-dyxn2pn3]
  `bend2/*.ts`; Bun strips types without checking them, mimo): needs the
  TypeScript package, a new pinned build dependency fetched by the
  coordinator; catches type errors our `comp.ts` patches introduce.
  Decided by the user 2026-10-16 (d-qiadn2fv): yes.

- [ ] Check whether Bend's TypeScript compiler (bundled into one JS file) [t-xz35srdq]
  runs on QuickJS, a small C JavaScript engine Debian and Guix build from
  source: a bootstrappable path without Bun today (argon, consult round
  `20261016-194939-a5a8`). Needs QuickJS fetched and pinned by the
  coordinator; one worker item; result: works, or the missing features.
  Decided by the user 2026-10-16 (d-2r2p2k3m): approved.

- [ ] Plain-clang freestanding build replacing emcc (from the Zig and [t-fwjpak4c]
  clang questions; consult rounds `20261016-175818-a3e6` and
  `20261016-194631-afbb`), in steps, each its own commit:
  (A) symbol inventory: compile the 51 programs and Robokill with
  `clang --target=wasm32 -nostdlib -mtail-call -c` from the pinned emsdk
  (clang 24, wasm-ld) and list undefined symbols (`llvm-nm -u`): the real
  libc gap, which sizes the rest; (B) under one guard in the patch series:
  mem*, an allocator over `__heap_base`/`memory.grow` for the IO paths,
  printing, abort and effects as named host imports, library-mode exports,
  linked with `wasm-ld --no-entry`; (C) F32 and other math from vendored
  musl sources built with `-ffp-contract=off -fno-fast-math`, never host
  `Math.*`, bit-exact against the emcc build with edge vectors for every
  math function used; (D) our own small JS loader (no Node branches) and
  the full gate run.
  Cutover criteria, set before results (decided by the coordinator): all
  gates pass (differential, negative, replay hashes and render bytes, heap
  bound over 1,000,000 frames); `return_call` present for every `musttail`
  in the disassembly; two clean builds give identical artifacts; in Chrome
  linear memory not above and frame p95 within 5% of the frozen emcc
  baseline; the shipped wasm plus JS at least 20% smaller gzip-compressed.
  Pass: switch cleanly, keep emcc as an unshipped diagnostic build. Fail:
  keep emcc, record the numbers.
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
