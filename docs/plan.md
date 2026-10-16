# Plan: Bend programs as WebAssembly in the browser

Status: approved by the user 2026-10-16 ("niech nowa herdr space zacznie
robić target wasm"); first consumer: the Robokill reimplementation
(`~/personal_projects/Robokill`, decision 0003 there), which renders with
WebGPU from a JS host.

## Goal

Run programs written in Bend 2 (https://github.com/bendlang/bend,
Apache-2.0, pinned at 2.0.35, commit 79df8d9) as WebAssembly in the
browser, CPU only; rendering stays in the host page (WebGPU).

## Known facts (checked 2026-10-16)

- Bend has no wasm target. Outputs: native binary (clang), `-o x.c`, `-o x.js`,
  `-o x.mjs` (JS lane; `F32` are JS numbers, `Nat` is `BigInt`), and
  `bend page.html -o dist`.
- The emitted C for hello world (74 KB) includes pthread.h, stdatomic.h,
  sys/mman.h, sys/socket.h, poll.h, signal.h, Metal/Foundation/mach-o and
  cuda/nvrtc; platform guards in `bend2/comp.ts` exist only for
  `__APPLE__` and `__linux__`. Which bodies are unconditional is not yet
  known.
- Runtime: 64-bit words, one heap (mmap) shared by cores and GPU, no GC,
  no C stack, a work-stealing scheduler over pthreads; IO effects are defs
  importing a `.js` file and a `.c` twin.

## Approach (consult round `20261016-121009-6b8e`, five models agreed)

1. **Out-of-tree probe first.** `bend -o x.c`, then Emscripten with build
   flags and, where needed, `-isystem` shim headers; no edits to generated C.
   Shims must not fake behaviour (a fake `mmap`, sockets or signals that
   compile but compute wrongly); stop when success would need that.
   Result: either a working CPU-only build or a blocker inventory classified
   as shim-able / emitter change (`comp.ts`) / architectural.
2. **Patch set on pinned Bend only with the user's approval**, as a small
   separable patch to the emitter (`comp.ts`), never to generated C, with
   the upstream change that would retire it.
3. **Upstream:** an issue proposing a wasm32/Emscripten CPU-only build mode
   (outline below); opening it needs the user's go.
4. **No separate Bend-to-wasm backend.**

## Correctness and value checks

- Differential tests: the same deterministic programs (Bend's own tests
  where possible: arithmetic and `Nat`, ADT matching and affine frees,
  recursion, shared values and refcounts, one JS effect) run native, JS lane
  and wasm; stdout and exit code must match byte for byte. F32 results are
  compared under documented rounding and NaN rules. Excluded tests are
  listed with the reason.
- Value check before investing beyond the probe: the Robokill `step`
  benchmark on the JS lane. If the JS lane meets the game's frame budget,
  wasm is an experiment, not a roadmap; report that to the user.
- Browser constraints to respect: pthreads need `SharedArrayBuffer` and a
  cross-origin-isolated page (COOP/COEP); `Atomics.wait` must not run on
  the main thread; wasm32 address space and memory growth; JS views of
  linear memory are invalidated on growth.

## Upstream issue outline

Title: "wasm32/Emscripten CPU-only build mode for generated C?" Pinned
version; exact `bend -o x.c` and `emcc` commands; first errors from the
unmodified output; questions: is wasm in scope, preferred guard
(`__EMSCRIPTEN__` or a Bend flag), an acceptable single-thread mode, a
JS-only effect seam without `.c` twins, a heap-size knob; offer the patch and
tests; ask which change would make a downstream patch unnecessary.
