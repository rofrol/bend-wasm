# Probe: Bend's generated C under Emscripten

Step 1 of `docs/plan.md` ("Approach"), TODO item t-jk5jg2zk, run on
2026-10-16. Build flags only: the generated C is not edited and no shim
header is used. `probe/run.sh` reproduces every build and run below from
scratch and writes its logs and `summary.txt` to `probe/out/` (ignored).

**Result:** both programs compile and link to wasm32 and wasm64 with flags
alone (no errors, no undefined symbols), but neither runs: the runtime's
memory reservation fails before any Bend code executes. Every blocker that
stops a run is in the runtime template of `vendor/bend/bend2/comp.ts`.

## Toolchain

```
$ scripts/bend --toolchain
bend 79df8d9 79df8d9c40722ee9507a1e253f283b51025f9d6c
bun 1.4.2
emcc (Emscripten gcc/clang-like replacement + linker emulating GNU ld) 6.0.10 (d6c521a7f05449857c76bd99e396895583cf2083)
```

Node for running: the SDK's `node/24.19.0_64bit/bin/node` (v24.19.0) in
`~/.cache/bend-wasm/emsdk-6.0.10`.

## Programs

| File | Shape taken from | Native output (`scripts/bend <file>`) |
| --- | --- | --- |
| `probe/hello.bend` | `vendor/bend/demos/io_hello_world/main.bend` | `Hello, world!`, exit 0 |
| `probe/arith.bend` | `vendor/bend/demos/pure_par_sum/main.bend` (its `Nat` match and `Nat.show`, without `!`, so no GPU lane) | `328350`, exit 0 |

`arith` sums the squares of 0..99; its only effect is printing the result.

## Commands

C emission (CLI form from `vendor/bend/bend2/main.ts:38` and `cli_emit`,
`main.ts:357`: an output ending in `.c` writes `Comp.compile_book`):

```
scripts/bend probe/hello.bend -o probe/out/hello.c   # 76219 bytes
scripts/bend probe/arith.bend -o probe/out/arith.c   # 80648 bytes
```

Builds, each `scripts/emcc <flags> probe/out/<p>.c -o probe/out/<p>.<variant>.js`,
then `node probe/out/<p>.<variant>.js` and a byte comparison of stdout with
the native output:

| Variant | Flags | hello | arith |
| --- | --- | --- | --- |
| `w32` | `-std=c11 -O2` | builds; run traps: `RuntimeError: memory access out of bounds` | builds; run: `bend: reservation failed`, exit 1 |
| `w32-tc-grow` | `-std=c11 -O2 -mtail-call -sALLOW_MEMORY_GROWTH -sMAXIMUM_MEMORY=4GB` | builds; run traps: `RuntimeError: memory access out of bounds` | builds; run: `bend: reservation failed`, exit 1 |
| `w64` | `-std=c11 -O2 -m64 -mtail-call -sALLOW_MEMORY_GROWTH -sMAXIMUM_MEMORY=16GB` | builds; run: `bend: reservation failed`, exit 1 | same |
| `w64-pthread` | `w64` plus `-pthread` | builds; run: `bend: reservation failed`, exit 1 | same |
| `w64-web` | `w64` plus `-sENVIRONMENT=web` | builds; not run (needs a page) | same |

`16GB` is the largest `MAXIMUM_MEMORY` wasm-ld accepts for wasm64
(`32GB` fails: "maximum memory too large, cannot be greater than
17179869184").

Diagnostic builds used to locate the failures (not in `run.sh`, since
they only add instrumentation): `-O0 -g -sASSERTIONS=2 -sSAFE_HEAP=1`
on `hello.c` (the trap's stack is `main` → `corpus_setup`), the same on
`arith.c` (no trap; it fails with `reservation failed`), and
`-Wshorten-64-to-32 -c` on `hello.c` for the truncations below. Small
standalone C tests of Emscripten's `mmap` (not part of the probe) gave the
behaviour quoted in the inventory.

## Diagnostics (deduplicated, with counts)

Compile and link: no errors in any variant, and no undefined symbols
(Emscripten's libc provides `mmap`, `sigaction`, `sigaltstack`, `poll`,
`select`, `pipe`, `fcntl` and the socket calls; link with
`-sERROR_ON_UNDEFINED_SYMBOLS`, the default, succeeded).

| Diagnostic | Where | Count |
| --- | --- | --- |
| `warning: unknown attribute 'musttail' ignored [-Wunknown-attributes]` | `w32` without `-mtail-call` | hello 6, arith 15 |
| `emcc: warning: -pthread + ALLOW_MEMORY_GROWTH may run non-wasm code slowly, consider -sGROWABLE_ARRAYBUFFERS=2 [-Wpthreads-mem-growth]` | `w64-pthread` | 1 per program |
| `emcc: warning: MEMORY64 is deprecated (prefer the standard -m64 or --target=wasm64 flags)` | only when `-sMEMORY64=1` is used; `run.sh` uses `-m64` | 1 |
| `warning: implicit conversion loses integer precision: 'u64' ... to 'size_t' [-Wshorten-64-to-32]` (wasm32) | `hello.c:1576` (`pool_try`'s `mmap` length), `2097`, `2138` (its callers), and 5 more on write/fwrite lengths | 8 to `size_t`, 1 to `u32` |

Runtime:

| Diagnostic | Variants | Count |
| --- | --- | --- |
| `RuntimeError: memory access out of bounds` (in `corpus_setup`) | hello `w32`, `w32-tc-grow` | 2 |
| `bend: reservation failed`, exit 1 | arith `w32`, `w32-tc-grow`; both programs `w64`, `w64-pthread` | 6 |

Neither program reached Bend evaluation, so no output could be compared
with native.

## Why the runs fail

1. **wasm32: the 8 GiB corpus truncates to 0 bytes.** `corpus_setup`
   reserves `1ull << 33` bytes by default (`comp.ts:5231`); `pool_try`
   passes the `u64` to `mmap`'s 32-bit `size_t` (`comp.ts:4658-4660`), which
   becomes 0, and the hint `1ull << 45` (`comp.ts:5176`) becomes a null
   pointer. Emscripten's `mmap(NULL, 0, ...)` returns a valid pointer to a
   zero-length mapping, so `corpus_map` succeeds with no usable buffer.
   `corpus_setup` then writes the static image at `H + STAT_OFF`
   (`comp.ts:5242`): hello (`STAT_LEN 26`) traps out of bounds; arith
   (`STAT_LEN 0`) writes nothing there and gets past it without a trap,
   even under `SAFE_HEAP` (its other writes through `H` are not checked
   further here), and then fails reserving the 2 GiB machine stack (`pool_stack`,
   `comp.ts:4671-4673`, `len = 1ull << 31`), which `mmap` cannot give even
   with `-sMAXIMUM_MEMORY=4GB`. Even without truncation, 8 GiB plus a
   2 GiB stack do not fit a 4 GiB wasm32 address space.
2. **wasm64: Emscripten refuses address hints.** `corpus_map`
   (`comp.ts:5175-5189`) asks for the corpus at `1ull << 45` and halves the
   hint while the result is not at it; Emscripten's `__syscall_mmap2`
   returns `EINVAL` for every non-null address
   (`upstream/emscripten/system/lib/libc/emscripten_mmap.c:106-108`: "We
   don't currently support location hints"), so every try fails and the
   loop ends in `err_fail("reservation failed")`. Plain `mmap(NULL, 8 GiB)`
   and then `mmap(NULL, 2 GiB)` do succeed in wasm64 with
   `-sMAXIMUM_MEMORY=16GB`.

## Blocker inventory

Classes: **shim-able** (a header or flag gives correct behaviour),
**emitter change** (`comp.ts` must emit something else), **architectural**
(the runtime's design conflicts with wasm or browser constraints). "Seen"
means a probe run hit it; "read" means it is from reading the generated C
and Emscripten's libc, after the first failure.

| # | Blocker | Class | `comp.ts` lines | Seen/read |
| --- | --- | --- | --- | --- |
| 1 | `musttail` dispatch (`WL_JMP`, `WL_DYN`, `WL_AGAIN`) ignored on wasm by default, so the work loop's tail calls would grow the C stack | shim-able: `-mtail-call` removes every warning (needs an engine with the wasm tail-call feature; the SDK's Node 24 has it) | 3364, 3365, 4311 | seen |
| 2 | Corpus default of 8 GiB (`1ull << 33`) and a 2 GiB stack per thread (`1ull << 31`) exceed wasm32's 4 GiB and, in wasm64, are committed and zero-filled by Emscripten's `mmap` (no lazy `MAP_NORESERVE`), against browser memory limits | emitter change (a size knob or wasm defaults); with the reserve-then-touch design it is architectural | 5231, 4672 | seen |
| 3 | `u64` sizes truncated to 32-bit `size_t` on wasm32, silently (a 0-byte map, then writes past it) | emitter change (sizes checked against `SIZE_MAX`, or wasm64 only) | 4658-4660, 5176-5183, 5216 | seen |
| 4 | Address-hinted `mmap` for the corpus (`1ull << 45`, halving) and in-place doubling at `H + size` (`corpus_grow`); Emscripten returns `EINVAL` for any hint, so the corpus can neither be placed nor grown in place | emitter change for placement (`mmap(NULL, ...)` under `__EMSCRIPTEN__`); in-place growth of one base is architectural on wasm (linear memory grows only at its end, under `malloc`'s control) | 5175-5189, 5209-5225 | seen |
| 5 | Stack guard page by `mprotect(PROT_NONE)` and overflow detection by `SIGSEGV`/`SIGBUS` on `sigaltstack` | architectural: Emscripten's `mprotect` is a stub that returns 0 without protecting (`emscripten_syscall_stubs.c:163-166`), and wasm traps instead of raising signals, so an overflow corrupts memory or traps instead of printing "machine stack overflow" | 4671-4683, 3691 | read |
| 6 | Worker pool and IO helpers by `pthread_create` (`pool_open`, `io_work`) | architectural for a page without cross-origin isolation (needs `SharedArrayBuffer`, `-pthread` builds link); a single worker (`--threads 1`, `pool_size == 1`) starts no pool thread, but blocking effects still start `io_help` threads | 4743-4755, 5628 | read |
| 7 | IO event loop on `pipe` + `fcntl(O_NONBLOCK)` + `poll`/`select` with blocking waits, `signal(SIGPIPE)` | architectural in a browser main thread (no blocking waits); links under Emscripten's emulation | 5884-5887, the `io_wait` loop after it | read |
| 8 | Sockets (`arpa/inet.h`, `netinet/in.h`, `sys/socket.h`) emitted for every program | links (Emscripten's emulated sockets); no browser semantics, so effects that use them are architectural; for programs without them only dead code | 5305-5309 | read |
| 9 | `cpu_count` by `sysconf`, `/proc` and cgroup files; GPU path by `/proc/self/exe` | shim-able by flags (`--threads 1` at run time; no GPU lane in a `BANGS 0` program); harmless | 4767-4785, 4813-4816 | read |

## Headers and platform guards

The whole C runtime is one template, `runtime_c` (`comp.ts:3240-5990`),
emitted for every program; only the tables (function ids, `BANGS`,
`STAT_*`) differ between hello and arith.

- Unconditional headers on the host (`!__METAL_VERSION__`, `!BEND_RTC`):
  `stdint.h`, `stdbool.h`, `math.h`, `stdio.h`, `stdlib.h`, `string.h`,
  `pthread.h`, `sched.h`, `stdatomic.h`, `unistd.h`, `signal.h`,
  `sys/mman.h`, `time.h`, `poll.h`, `sys/select.h` (`comp.ts:3264-3278`),
  and `arpa/inet.h`, `errno.h`, `fcntl.h`, `netinet/in.h`, `sys/socket.h`
  (`comp.ts:5305-5309`). All exist in Emscripten's sysroot.
- Behind `__APPLE__`: `mach-o/dyld.h` (`comp.ts:3279-3281`),
  `_NSGetExecutablePath` (4813-4814), the Mac window and Metal paths.
- Behind `__OBJC__`: `Metal/Metal.h`, `Foundation/Foundation.h`; behind
  `BEND_CUDA`: `cuda.h`, `nvrtc.h`, `fcntl.h`, `sys/stat.h`
  (`comp.ts:3282-3290`). Neither is defined by Emscripten.
- Behind `__linux__`: the cgroup/affinity part of `cpu_count`
  (`comp.ts:4769`); behind `__linux__ || BEND_RTC`: the window quadtree
  fill. Emscripten defines neither `__linux__` nor `__APPLE__`, so it takes
  the `#else` branches (`/proc/self/exe` for the GPU path).
- Unconditional bodies that matter for wasm: `pool_try`/`pool_mmap`,
  `pool_stack` (`mprotect`, `sigaltstack`, `sigaction`), `corpus_map`,
  `corpus_grow`, `pool_open`, the IO loop (`pipe`, `fcntl`, `poll`,
  `signal(SIGPIPE)`), the socket effects. None has an `__EMSCRIPTEN__` guard.

## What would unblock the next step

Not decided here; patching `comp.ts` is the open decision t-3oqripea.

- A way to place the corpus without an address hint and at a size that fits
  (blockers 2-4): for example `mmap(NULL, ...)` and a smaller default or a
  size knob under `__EMSCRIPTEN__`, with growth that does not need the same
  base. This needs an emitter change; a shim that redefines `mmap` to drop
  hints would compile but is a header that changes the runtime's calls, so
  it was not tried here.
- A machine stack that fits linear memory (blocker 2 for `pool_stack`), and
  an answer for overflow detection without guard pages and signals
  (blocker 5).
- With those, re-run `probe/run.sh` with `w64` (or `w32` once sizes fit) and
  `--threads 1`, the next unknowns being the IO loop's blocking `poll`
  (blocker 7) and the single-worker path (blocker 6).
- The upstream issue (t-ymygf5au) can quote the commands above, the two
  runtime errors and blockers 2-5 as its first errors.
