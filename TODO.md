# TODO

Plan and context: `docs/plan.md`.

## Next, in order

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
  Step (A) done 2026-10-16 (run r-iptfuhjv, 5abd632): `tools/clang-wasm/inventory.sh`
  and `docs/clang-wasm.md`. All 52 C files (51 corpus programs and
  Robokill's step library) compile with plain clang 24 `--target=wasm32
  -nostdlib -mtail-call` against the emsdk's musl headers (17 headers
  missing without a sysroot); 39 undefined libc symbols in all (a typical
  program 30-35, Robokill 14), all on IO, error, F32-printing or the
  multi-worker pool paths, none on the `WL_FID_*` hot path; memcpy/memset
  become `memory.copy`/`memory.fill`; no libm needed by any of the 52;
  step (C) needs 15 double math functions plus fmodf, strtof and %e/%f
  formatting; `musttail` gives `return_call`. `-D__EMSCRIPTEN__` is still
  needed (the series' wasm path keys on it); step (B) replaces it with its
  own guard. Next: step (B).
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

- [ ] Requested by the user 2026-10-16: "on this machine this test does not [t-xqgdbzz2]
  pass now: fix it; ask the models". `probe/web/run.sh` fails on this Mac:
  headless Chrome 155 (`--headless=new --dump-dom`) renders the page
  correctly (hello: exit 0, stdout "Hello, world!" in the dumped DOM) but
  exits 2 at teardown; its log ends with "Trying to load the allocator
  multiple times. This is *not* supported." and "Teardown watchdog expired;
  recording dump and terminating." Seen on run r-mqzurb3s's tree, which
  does not touch `probe/`; find the cause (Rule 10: no longer timeout, no
  retry) and fix it so the check passes.
  Decided by the coordinator after consult round `20261016-211147-4d29`
  (sol, mimo, argon, wonder; deepseek failed): the "allocator multiple
  times" line is noise (it is on passing runs too); the Playwright Chrome
  started at 21:09 cannot be the trigger (failures began about 21:04); a
  watchdog-disabling flag, a longer timeout, a retry and accepting exit 2
  are rejected. Reproduced by the coordinator on `about:blank` (3 of 3,
  21:07-21:09), then not at all: a diagnostic loop of 20 full-Chrome and 20
  headless-shell runs at load about 54 all exited 0 (herdr job
  20261016-211539-7744); the cause stays unproven (a Playwright Chrome of
  the same app bundle crashed at 21:06 and 20:52, Crashpad dumps). Fix:
  `probe/web/run.sh` uses Chrome for Testing's chrome-headless-shell,
  pinned, a separate binary built for `--dump-dom` with a lighter teardown
  and no state shared with the user's Chrome. The coordinator fetched
  155.0.8059.84 mac-arm64 (zip sha256
  7f111980bcb41e908d0fa3e969a625e7777ff683c1fc43fd7759d05ec3ffe52b) into
  `~/.cache/bend-wasm/chrome-headless-shell-155.0.8059.84/`; with it
  `probe/web/run.sh` passes (hello, arith). The worker makes it the
  default (CHROME still overrides), documents the fetch and the pin in
  `docs/workflow.md` and `docs/probe.md`, and adds negative pages (a
  program that fails, a page that never runs it) that the coordinator runs
  outside the sandbox to show the check still fails.

- [ ] Node benchmark out of memory at n = 2,000 (from t-3wp2nvda, run [t-m72ghzpf]
  r-mqzurb3s): `bench/robokill/node.sh` stops with `bend: out of memory:
  the corpus of 1425408 bytes is full`; the worker reports the same on
  ddc00ce with the old flags (same `.wasm` bytes), so it predates the
  shipped-glue change. Not yet reproduced by the coordinator. Find why the
  Node run fills the corpus while the Chrome run at n = 2,000 does not, and
  fix it or size it (docs/memory.md).
  Decided by the user 2026-10-16 (d-c2aqguer): approved.

- [ ] Differential check's temp dir deleted mid-run (from t-dyxn2pn3, run [t-vdfibz6b]
  r-tqd3miak, verify event 178884, 2026-10-16 ~21:47): in herdr's verify,
  `tests/differential/run.sh` got `ENOENT ... mkdtemp
  tests/differential/out/tmp/bend-*` from program ~33 on (ok 64, DIFFERS 1,
  FAILED 34); the diff did not touch `tests/`. Checked: herdr runs checks
  sequentially and keeps ignored files (`src/workers/verify.rs:166-196`,
  `git clean -fdq` without `-x`); worker w381 had exited at 21:44:45 with
  no background run; no corpus program deletes files. Suspect: a second
  `tests/differential/run.sh` with the default output in the same folder
  (its `rm -rf "$out"` at line 43), source unknown. Proposed: give each
  run its own output under `out/` (or refuse a concurrent run with a lock
  naming the holder), and keep the first failing program's full message in
  the summary, since verify keeps only the tail.
  Decided by the user 2026-10-16 (d-c2aqguer): approved.

- [ ] Bun-free compile path on QuickJS (the user, 2026-10-16: running [t-gp6pld3m]
  programs on QuickJS failing for lack of `bun:ffi` "is weak, maybe throw
  QuickJS out; ask the models", then "why is Node better than QuickJS?
  ask the models"). Rounds `20261016-221426-c9c3` and
  `20261016-222217-7c9e` (sol, mimo, deepseek, argon, wonder): `bun:ffi`
  only serves the JS lane's in-process IO, off the bootstrap path
  (compiler -> C -> cc -> native or wasm); what decides is type stripping,
  not the runtime: QuickJS's experiment used a bundle made by Bun. Node's
  only edge was no shims; its own type stripping is amaro (SWC as a
  prebuilt wasm), and its chain (V8, C++, Python, OpenSSL, ICU) is far
  longer than QuickJS's cc + make. Checked by the coordinator: Guix
  packages esbuild 0.24.0 (Go, from source; `gnu/packages/web.scm`) and
  node-lts 24.18.0 keeps `deps/amaro` (`gnu/packages/node.scm`), so the
  models' "Guix strips amaro" was wrong.
  Work: produce plain JS from the patched `bend2/*.ts` with esbuild
  (pinned; it handles the two constructor parameter properties,
  `main.ts:827`, `safe.ts:159`), no Bun in the chain; run it on the pinned
  QuickJS with the shims of `tools/quickjs/` (plus the spawnSync shim for
  building a native binary); a patch in the series dropping the Bun guard
  on the emit and native-build paths instead of the fake `Bun` object; a
  check that emits the whole differential corpus this way and requires C
  byte identical to Bun's, with `--stack-size` set from the largest
  program; one program built to a native binary from that C and run
  against its expected output.
  Decided by the user 2026-10-16 (d-6npw3qxi, superseding d-76senvng and
  d-y55x4t3z): only QuickJS, no Node path. Needs esbuild fetched and pinned
  by the coordinator.

## Needs a decision

## Proposed
