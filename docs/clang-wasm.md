# Plain-clang wasm build

TODO t-fwjpak4c, step (A): what does Bend's emitted C need from a libc when
it is compiled for wasm32 by plain clang, without emcc? This sizes steps
(B) (mem*, allocator, printing, abort, host imports, `wasm-ld --no-entry`)
and (C) (math from vendored musl). Step (B), the build itself, step (C),
musl's math, float parsing and formatting, and step (D), the JS loader and
the gates, are at the end ("Step (B): the freestanding build", "Step (C):
math, float parsing and formatting from musl", "Step (D): the loader and
the gates").

`tools/clang-wasm/inventory.sh` answers it; results in
`tools/clang-wasm/out/` (ignored). It emits the C of the 51 programs of
`tests/differential/corpus.txt` (as the wasm lane does) and of Robokill's
step library (`replay/robokill/step.bend --lib
init,input_at,step,hash,render`, as `glue/build.sh` does), lists the
headers each reaches without a sysroot (`clang -M -MG`), compiles each
with the emsdk's sysroot for declarations only and lists the object's
undefined symbols (`llvm-nm -u`).

## Setup

2026-10-16: bend 79df8d9 (v2.0.35) with patches 0001-0003; the pinned
emsdk 6.0.10's clang (`clang version 24.0.0git`, llvm-project a06d916),
`llvm-nm`, `wasm-ld` under `upstream/bin/`.

```
clang --target=wasm32 -nostdlib -D__EMSCRIPTEN__ -std=c11 -O2 -mtail-call \
  --sysroot=$sdk/upstream/emscripten/cache/sysroot -c NAME.c
```

- `-std=c11 -O2 -mtail-call` are `scripts/wasm-flags`' C flags; its `-s`
  settings are emcc link settings and do not apply.
- `-D__EMSCRIPTEN__`: the patch series keys its whole wasm path on it
  (`WL_ENV_SIG`'s two words, `WL_ROOM`, `pool_stack_bss`,
  `corpus_bss`, one worker, the refused effects; `docs/memory.md`, "If
  the toolchain became a freestanding wasm32 build"). emcc's target
  (`wasm32-unknown-emscripten`) predefines it and `__unix`/`__unix__`;
  `--target=wasm32` predefines neither (`-dM -E` of both). Nothing in the
  emitted C tests `__unix__`. Step (B) replaces the define with its own
  guard.
- The sysroot is the emsdk's own `upstream/emscripten/cache/sysroot`
  (musl headers), read only; no libc, compiler-rt or crt is linked.
- emcc also passes `-fvisibility=hidden`, `-mllvm -disable-lsr` and
  `-mllvm -combiner-global-alias-analysis=false` (`emcc -v`); the plain
  build does not, so its code differs from emcc's for step (D)'s timing
  comparison.

## Results

All 52 compile with no error and no warning. Undefined symbols: 39 in the
union; 31 for most programs, 30 to 35 across the corpus, 14 for Robokill.

### Headers

Without a sysroot, every file stops at the first one,
`fatal error: 'math.h' file not found` (line 25). All 52 files reach the
same set (`clang -M -MG`), from the runtime template's includes:

- missing (17): `arpa/inet.h errno.h fcntl.h math.h netinet/in.h poll.h
  pthread.h sched.h signal.h stdio.h stdlib.h string.h sys/mman.h
  sys/select.h sys/socket.h time.h unistd.h`;
- from clang's resource directory: `stdatomic.h stdbool.h stddef.h
  stdint.h` (and `stddef.h`'s `__stddef_*.h` parts).

The headers carry types as well as functions: `FILE`, `pthread_mutex_t`
and `pthread_cond_t` (statics such as `pool_lock`), `struct sockaddr_in`,
`fd_set`, `struct timespec`. Every program needs them to compile, even
where the symbol is never called.

### Symbols, by group

Count = programs of 52 whose object needs it; "where" = the functions of
the emitted C that reference it (from `llvm-objdump -d -r`).

| Symbol | Count | Where |
|---|---|---|
| **Linker** | | |
| `__stack_pointer` | 52 | every function with a stack frame; wasm-ld defines it |
| `__indirect_function_table` | 52 | `wl_tab`, `WL_DYN`, IO callbacks; wasm-ld defines it |
| **Memory** | | |
| `malloc`, `realloc` | 50 | `io_cbuf` (IO.print's buffer), `chan_new_run` |
| `calloc` | 50 | `io_spawn`, `io_wait` |
| `free` | 50 | `io_errs`, `io_print_run`, `io_step`, `io_wait`, `chan_*_run` |
| `memchr` | 1 | `show_val` |
| **Printing, stdio** | | |
| `stdout`, `stderr` | 52 | `err_fail`, `io_sync`, `io_errs`, `io_print_run`, `show_*` |
| `fprintf` | 52 | `err_fail` |
| `fflush` | 52 | `err_fail`, `io_sync` |
| `snprintf` | 52 | `err_post`, `lib_fail` (inlined into `bend_def_*`), `f32_show`, `show_val` |
| `printf` | 51 | `main` (`--bend-help`), `show_val`, `show_chr` |
| `fwrite` | 51 | `io_out`, `show_val`, `show_chr` |
| `sprintf`, `strtof`, `atoi`, `strchr` | 3 | `f32_text` via `f32_show`, `show_val` |
| `fputs`, `putchar`, `strpbrk` | 1 | `show_val` (`putchar` also `io_loop`) |
| **Strings, arguments** | | |
| `strcmp`, `strtod`, `strtol` | 51 | `main`'s option parsing |
| **Process** | | |
| `_exit` | 52 | `err_fail` |
| `exit` | 50 | `io_step` (IO.exit) |
| `signal` | 51 | `io_loop` |
| **IO loop** | | |
| `pipe`, `fcntl` | 51 | `io_loop` (the IO thread's wake pipe) |
| `read` | 50 | `io_loop`, `io_wait` |
| `select`, `__errno_location` | 50 | `io_wait` |
| `clock_gettime` | 50 | `io_loop`, `io_step`, `io_wait` |
| **Threads** | | |
| `pthread_mutex_lock/unlock`, `pthread_cond_wait/signal/broadcast`, `sched_yield` | 52 | `pool_turn` only (`POOL_WAIT`) |
| **Math** | | |
| (none) | 0 | |

The programs with fewer symbols: Robokill's library (14: no `main`, no IO
loop) and `reg/wnf_deep_chain` (30: none of the IO effects'
symbols, but the F32-text ones and the four `show_val`-only ones); `run/float_printing` and
`run/u32_mod_operator` have 35 (the IO loop and the F32-text symbols).

Robokill's library needs exactly: `__stack_pointer`,
`__indirect_function_table`, `snprintf`, `_exit`, `fprintf`, `fflush`,
`stderr`, `stdout`, the five pthread calls and `sched_yield`.

### Hot path versus IO and error paths

- The work-loop segments (`WL_FID_*`) reference no libc symbol, only the
  two linker globals. The one exception in the corpus is
  `WL_FID_MAIN_OUT_K8` of an F32-printing program, where clang inlined
  `f32_show` (printing, not evaluation).
- `memcpy`, `memset` and `memmove` never appear: clang 24's generic wasm32
  CPU enables bulk memory (`__wasm_bulk_memory__`), so they become
  `memory.copy`/`memory.fill` inline. Robokill's per-frame copy of the F32
  region (`bend_def_render`, 3 `memory.copy`) is one of them. Step (B)
  still has to supply `memcpy`/`memset` if a build turns bulk memory off
  or a call is too large to inline; none here is.
- `bend_def_step`, `bend_def_hash` and `bend_def_render` reference
  `snprintf` only through `lib_fail` (a stale or wrong handle), an error
  path.
- `pool_turn` (`comp.ts` 4787, `POOL_WAIT` 4688) is called only from
  `cube_run` (5133), the multi-worker and `!`-fork path. Patch 0002 runs
  one worker on wasm (`thr = 1`), and every program here has `BANGS 0`,
  so `work_loop` runs solo (`!BANGS && pool_size == 1`); clang cannot
  prove that, so the symbols stay. emcc links its no-op pthread stubs.
- `err_fail` (`comp.ts` 3681: `fprintf(stderr, ...)`, `fflush`, `_exit`)
  and `err_post` (`snprintf` of the corpus message) are the error path.
- The IO loop (`io_loop` 5881, `io_wait` 5656, `io_step`, `io_cbuf`) is
  program mode's host side: printing, the wake pipe, timers, `exit`. The
  library has none of it.
- F32 text (`f32_text`/`f32_show`, `comp.ts` 374-413) formats with
  `snprintf("%.*e")`/`"%.*f"` of a double and checks with `strtof`: the
  printf floating-point formatter and a correct `strtof` are needed only
  by the three F32-printing programs.

### Math (step C)

No object of the 52 needs a math function: Robokill's F32 uses `+ - * /`
and comparisons only (`step.bend`'s header), and no corpus program uses
an F32 math builtin. What the emitter can produce (`comp.ts` 184-198)
calls the double functions on a widened F32 and rounds back
(`(f32)sin((double)x)`). A probe of all of them with the same flags
(`clang -c` of `(f32)op(x)` for each) gives:

- inline wasm instructions, no libm: `sqrt floor ceil trunc fabs`;
- undefined, double: `exp log log2 log10 sin cos tan asin acos atan sinh
  cosh tanh atan2 pow`;
- undefined, float: `fmodf` (clang narrows `(f32)fmod(f32, f32)`).

So step (C) supplies those 15 double functions and `fmodf` from musl,
bit-exact with emcc's (which links the same musl sources); none of them
is on a path any current program or Robokill reaches.

### Without `-D__EMSCRIPTEN__`

`run/nat_native` compiles without the define too (native path: mmap
corpus, `sysconf`, pool threads), and its object has 15 undefined symbols
(`sysconf` new; no `mmap`, `pthread_create` or IO-loop symbols): clang
pruned most of that path as unreachable on wasm32. Why was not
investigated; it is not the path a wasm build takes.

## Constructs clang accepts without emcc

- `__attribute__((musttail))` on wasm32 with `-mtail-call`: accepted, no
  diagnostic; Robokill's object has 8 `return_call` and `run/nat_native`'s
  13 from the template's three `musttail` macros (`WL_JMP`, `WL_DYN`,
  `WL_AGAIN`, expanded per segment). Step (D) checks one per site in the
  linked module.
- `preserve_none`/`preserve_most`: `PRESERVE()` applies them only when
  both exist; clang 24 on wasm32 has `preserve_most` but not
  `preserve_none`, so neither is applied, as under emcc.
- `__attribute__((constructor))` (`io_print_use`), `aligned(65536)`
  (`corpus_bss`), `aligned(16384)` (`pool_stack_bss`), `may_alias`: no
  diagnostic. Constructors need `__wasm_call_ctors`, which wasm-ld
  synthesizes; with `--no-entry` the host must call it (or the build
  exports `_initialize`) before the first `bend_*` call.
- `main(int, char**)` becomes `__main_argc_argv` on wasm32; program mode
  needs a `_start` or a host that calls it with an argv in memory.
- Default visibility: emcc passes `-fvisibility=hidden` and exports by
  list; a plain build exports what `wasm-ld --export=` names.

## What (B) and (C) must supply

- (B), under one guard: `stdout`/`stderr` as opaque handles; `fwrite`,
  `fflush`, `fputs`, `putchar` onto one host import that writes bytes to
  fd 1 or 2; a small `snprintf`/`printf`/`fprintf` covering the formats
  in the template (`%s %.*s %c %d %u %llu %llx %ld`, and `%.*e %.*f` of a
  double for F32 text); `malloc`/`calloc`/`realloc`/`free` over
  `__heap_base` and `memory.grow` (IO paths only: 5,264 bytes plus the
  print buffer, `scripts/wasm-flags`); `strcmp strtol strtod strtof atoi
  strchr strpbrk memchr`; `_exit`/`exit` as a host import; no-op
  `pthread_*`/`sched_yield` (one worker, as emcc's stubs), or the guard
  keeps `pool_turn` out; `signal`, `pipe`, `fcntl`, `read`, `select`,
  `clock_gettime`, `errno`: the IO loop's, either imports or the guard
  keeps the wake pipe and parking out (patch 0002 already refuses the
  effects that park or block). Headers: 17 to replace with one
  freestanding header or keep from the sysroot for declarations.
- (C): the 15 double functions and `fmodf` above, plus a correct `strtof`
  and the double formatter for `%.*e`/`%.*f` (musl's `floatscan` and
  `fmt_fp`), the latter two needed by F32 printing (done: "Step (C)",
  below).
- Robokill's library alone needs only the error path (`snprintf`,
  `fprintf`, `fflush`, `_exit`, `stdout`, `stderr`) and the pool stubs.

## Step (B): the freestanding build

2026-10-16, the toolchain of step (A) and patch
`patches/0004-freestanding-wasm.patch`.

```
tools/clang-wasm/build.sh FILE.c OUTDIR NAME   # one module: OUTDIR/NAME.wasm
tools/clang-wasm/check.sh [OUTDIR]             # the 51 programs and Robokill
```

`build.sh` compiles with the pinned emsdk's clang, `--target=wasm32
-nostdlib -mbulk-memory -DBEND_WASM_FREESTANDING`, `scripts/wasm-flags`'
C flags (`-std=c11 -O2 -mtail-call`) and the sysroot's musl headers for
declarations, as step (A); links with `wasm-ld --no-entry --export=...`;
then runs binaryen's `wasm-opt --memory-packing` from the same SDK (below).
No libc, compiler-rt or crt of the SDK is linked: the link fails on any
undefined symbol. Since step (C) the module also links `libc.a`, built from
vendored musl and compiler-rt sources ("Step (C)", below).

### The guard

One macro, `BEND_WASM_FREESTANDING`. It defines `__EMSCRIPTEN__` before
the template's includes, so the build takes the series' wasm path exactly
as emcc's does (two-word `Env` through `musttail`, `WL_ROOM`, the static
corpus and Term stack, one worker, the refused effects), and it is an
`#error` under emcc. The series keeps keying on `__EMSCRIPTEN__` rather
than a new name because renaming patch 0002's conditions would rewrite
them, and `tests/negative/env-abi.patch` applies to one of those lines.
Without the guard the C preprocesses to what it was: the emcc builds of
`check.sh` are byte-identical to the ones built before the patch
(`glue/out/step.lib.wasm`, `tests/differential/out/run_nat_native.wasm.wasm`,
`cmp`).

Under the guard a "Freestanding" section after the includes defines what
step (A) found missing:

- `memcpy`, `memmove`, `memset` as `memory.copy`/`memory.fill` (bulk
  memory is required, an `#error` otherwise; clang inlines most calls
  anyway), `memcmp memchr strlen strcmp strchr strpbrk strtol atoi`;
- `malloc calloc realloc free` (below);
- `stdout`, `stderr`, `fwrite fputs putchar fflush` and a printf
  (`printf fprintf snprintf sprintf`) of the formats the template uses:
  `%% %c %s %d %i %u %x %X`, the lengths `l ll z`, a precision on `%s`
  (`.N`, `.*`) and on `%e %f`; anything else traps. The streams are
  unbuffered (each write goes to the host at once), so `fflush` has
  nothing to do;
- `_exit`, `exit`, `clock_gettime(CLOCK_MONOTONIC)`, `errno`;
- the one worker's pool: `pthread_mutex_lock/unlock`,
  `pthread_cond_signal/broadcast`, `sched_yield` do nothing;
  `pthread_cond_wait` traps (nothing could signal it);
- the IO loop: `signal` and `fcntl` do nothing, `pipe` opens nothing (fds
  -1), and `read` and `select` trap: they serve helper threads and parked
  requests, which the wasm path refuses (`io_work`, `io_wait_on`), so no
  program reaches them.

### Host imports

All of module `bend`; a module imports only those its code reaches.

| Import | Signature | For |
|---|---|---|
| `write` | `(fd i32, data i32, len i32) -> i32` | stdout (1) and stderr (2): the bytes taken (the runtime loops on fewer), 0 or less for an error ("a short write on a standard stream") |
| `exit` | `(code i32)`, never returns | `_exit` (every fail-stop), `exit` (`IO.exit`) |
| `now` | `() -> i64` | monotonic nanoseconds (`io_tick`: `IO.now`, the IO loop) |

Step (B) also had trapping stand-ins for `fmt_fp`, `strtof`, `strtod`
and the math functions; step (C) replaced them with musl's code in the
module, so these three are all the host gives.

What the 52 modules import (`check.sh` instantiates each with stubs):
`write exit now` for 49 programs; `write exit` for `reg/wnf_deep_chain`,
`io/halt_utf8_law` and Robokill's library.

### Exports

- A library (the C defines `bend_init`): what `glue/build.sh`'s emcc build
  exports (`glue/gen.mjs exports`): `bend_init bend_dispose
  bend_heap_words bend_handles bend_f32 bend_f32_len malloc` and every
  `bend_def_*`.
- A program: `__main_argc_argv` (clang's name for `main(int, char**)` on
  wasm32) and `malloc`, for the host to place `argv`.
- Both: `memory` and `__wasm_call_ctors`, which the host calls once,
  first: a program's effects register in constructors (`io_print_use`).

### Memory

Sized as `scripts/wasm-flags` sizes emcc's: the static image, a 64 KiB
stack placed first (`-z stack-size=65536 --stack-first`: an overflow
leaves memory and traps) and a 1 MiB heap (`--initial-heap=1048576`), and
no growth (`--no-growable-memory`: the maximum is the initial size). All
52 modules have the same number of pages as their emcc build (176 for
Robokill, 11,534,336 bytes; 171 to 179 for the programs; `wasm-dis`).

The allocator serves only the host side (IO buffers, the glue's scratch
words): blocks with a 16-byte header from `__heap_base` up, a request
rounded to a power of two, freed blocks reused through per-size lists,
and the block at the top grown in place by `realloc` and returned to the
top by `free`. More memory comes from `memory.grow`, which fails here, so
`malloc` returns NULL and the run stops with "bend: host allocation
failed" (`io_mem`), as under emcc. `IO.print`'s buffer doubles from 64
bytes: as the top block it grows in place, so the longest String's 512
KiB buffer, and 768 KiB, fit in the 1 MiB heap, and 2 MiB is refused (a
throwaway test of the allocator).

### Data: wasm-opt --memory-packing

clang -O2 evaluates the effects' constructors at compile time, so a
program's `io_eff_rows` (65,536 rows of 8 bytes) becomes initialized data,
nearly all zeros, and wasm-ld writes all 512 KiB of it (533 KiB modules).
emcc's wasm-opt drops such zero runs; `build.sh` runs that one pass,
`--memory-packing`, and nothing else of wasm-opt's pipeline (memory is not
imported, so it is zero at instantiation). It also drops the name
section, so the tail-call check reads wasm-ld's output (`NAME.ld.wasm`)
and then checks that the final module has as many `return_call`s.

### Tail calls

`build.sh` disassembles the module with the SDK's `llvm-objdump -d` and
fails when a segment (`WL_*`) enters a segment by a plain `call` or by any
`call_indirect`, or when a module whose C has `musttail` has no
`return_call`. clang refuses a `musttail` it cannot honour, so the check
is that the target lowered each to `return_call`/`return_call_indirect`.
`NAME.tail` has the counts. None of the 52 has a plain entry. The counts
differ from the C's sites, both ways: Robokill's C has 9 `musttail`, the
module 8 `return_call_indirect`; the ninth, `FID_EXIT`'s jump to a
continuation that has a frame, is dead code there (`FID_T[*][1]` is 0 for
every def) and is removed. Across the 52: 1,186 sites, 1,187
`return_call`s; 37 modules have fewer than their sites (dead sites), some
more (the optimizer duplicates a tail).

### Results

`check.sh` (about 4 minutes): all 52 emit, build and validate (they
instantiate with stub imports, every expected export is there), with no
compiler warning. Running them is step (D)'s loader. A throwaway run in
the SDK's Node (not committed: real `write`, `exit` and `now`, trapping
step-(C) imports, `__wasm_call_ctors` then `__main_argc_argv`) gave the
emcc lane's stdout, stderr and exit status for 49 of the 51 programs; the
other two, `run/float_printing` and `run/u32_mod_operator`, trap in
`fmt_fp` (step (C) fixed both, below). Robokill's library run the same way
(n = 500, seed 12345, 10,000 frames) hashes 603820250, as its RESULTS.md,
and a stale handle gives the library's message and exit 1.

Sizes after step (B) (`check.sh`'s `sizes.txt`; gzip -9): the plain build
was 45% of emcc's in all (41% gzip-compressed), Robokill 67% (62%). emcc's
module carries musl's stdio and dlmalloc; emcc also optimizes the code
with wasm-opt -O2, which the plain build does not, so the code itself
differs (step (A)'s note on emcc's flags holds too). The sizes with step
(C)'s musl code are in "Step (C)", below.

## Step (C): math, float parsing and formatting from musl

2026-10-16, the toolchain of step (A), patch
`patches/0004-freestanding-wasm.patch` and the vendored sources below.

```
tools/clang-wasm/libc.sh OUT.a          # the archive (build.sh calls it)
tools/clang-wasm/math-check.sh [OUTDIR] # bit-exactness against emcc
```

The math functions the emitter can call (`exp log log2 log10 sin cos tan
asin acos atan sinh cosh tanh atan2 pow fmodf`), `strtof`, `strtod` and
printf's `%e`/`%f` now come from code in the module, never from the host:
patch 0004 drops their trapping imports and declares `bend_fmt_fp`, which
its printf calls for `%e` and `%f`. `build.sh` links the module's object
with `OUTDIR/libc.a`, which `libc.sh` builds (and rebuilds only when a
source or the script is newer), so a module takes only what it calls.

### Sources

The files emcc links for the same calls, found by emcc's own link of a
probe that calls each (`emcc -Wl,--why-extract=...`), copied unmodified
from the pinned SDK (`cmp`):

- `tools/clang-wasm/musl/`: Emscripten's musl 1.2.6 (`system/lib/libc/musl`),
  56 files and `COPYRIGHT`; the list, per function, is its `README.md`.
  `strtof`/`strtod` are musl's `floatscan`; `%e`/`%f` is `fmt_fp` of
  Emscripten's `vfprintf.c`, which formats `long double` at double
  precision, as emcc's printf does.
- `tools/clang-wasm/compiler-rt/`: 32 files of compiler-rt's builtins
  (`system/lib/compiler-rt`, Apache 2.0 with LLVM Exceptions), the
  binary128 soft-float routines `floatscan` needs: its `long double` is
  binary128 on wasm32, as under emcc, which links the same routines from
  its `libclang_rt.builtins.a`. Its `README.md` lists them.
- `tools/clang-wasm/libc/`, ours: `features.h` and an empty `syscall.h`,
  the two internal headers musl's sources include that are not vendored
  (the public headers are the sysroot's); `fmt_fp.c`, which includes
  `vfprintf.c` for its static `fmt_fp` and defines `bend_fmt_fp` over a
  `FILE` that collects bytes (the rest of `vfprintf.c` is dead and the
  linker drops it); `uflow.c`, a trapping `__uflow`, which only a scan of a
  real `FILE` reaches.

`.gitattributes` exempts the vendored directories from the whitespace
check, so they stay byte-identical (`vfprintf.c` and `floatscan.c` have
trailing blanks).

### Flags

`libc.sh` compiles with `--target=wasm32 -nostdlib -mbulk-memory
-mtail-call -O2 -fno-builtin -ffp-contract=off -fno-fast-math -w` and the
sysroot's headers; musl's files also with `-std=c11 -D__EMSCRIPTEN__
-D_XOPEN_SOURCE=700`, compiler-rt's with `-DNDEBUG`.

- From emcc's build of its libc (`tools/system_libs.py`): `-fno-builtin`
  (clang must not replace musl's own calls, such as `scalbn`, by builtins
  or fold them), `-D_XOPEN_SOURCE=700`, `-O2` (emcc uses `-O2` for its math
  files and `-Os` for the rest; the optimization level does not change
  IEEE results here), and `__EMSCRIPTEN__`, which Emscripten's musl tests
  (`libm.h`, `stdio_impl.h`, `vfprintf.c`, and `fabs`, `floor`, `sqrt` as
  wasm instructions on `__wasm__`).
- `-ffp-contract=off -fno-fast-math`: no contraction into fused
  multiply-add and no reassociation or other value-changing rewrite, each
  of which would change a result's rounding. They are clang's defaults for
  wasm32, which has no fma instruction; the flags keep the guarantee if a
  default changes.
- `-std=c11` for emcc's `-std=c99`: before C11 the sysroot's `stdio.h`
  defines a placeholder `struct _IO_FILE`, which `stdio_impl.h` then
  redefines; emcc's libc build puts musl's `src/include/stdio.h` first,
  which prevents that. Nothing in these files differs between the two.
- `-w`: the warnings are musl's and compiler-rt's own.

### Bit-exactness

`math-check.sh` (about 15 seconds) builds `tools/clang-wasm/math-check.c`
twice: with `scripts/emcc` and `scripts/wasm-flags`, as the emcc lane builds
a program (so with emcc's musl), and with plain clang and `libc.sh`'s
archive. `math-check.mjs` then calls both, passing values as their bits
(a JS number need not keep a NaN's payload), and compares:

- each unary function over the edge vectors (±0, ±inf, quiet and
  signalling NaNs with payloads, the smallest and largest subnormals,
  ±`DBL_MIN`, ±`DBL_MAX`, overflow and underflow limits of `exp`, `sinh`,
  `cosh`, F32 limits, multiples of π/2 and π/4 from −12 to 12 and near
  10^3 to 10^100 and 2^20 to 2^52, each also one and two ulps either side)
  and 14,000 seeded random values (random bits, and uniform in ±10, ±1000,
  ±1 and over all magnitudes): 15,549 calls each;
- `atan2` and `pow` over the cross product of 53 edge values and 10,000
  random pairs, `pow` also over 10,000 pairs of bases and exponents near 1,
  negative bases with integer exponents and large exponents; `fmodf` over
  the cross product of 47 float edges and 17,000 random pairs;
- `strtof` and `strtod` (the bits and the bytes taken) over 38,578 strings:
  edge texts (signs, `inf`, `infinity`, `nan(...)`, hex floats, overflow,
  underflow, the subnormal and `DBL_MAX` boundaries, the known hard cases,
  leading blanks, trailing junk, empty and partial texts, 800-digit
  texts), and for 2,500 random doubles and 2,500 random floats their
  shortest, 17- and 9-digit texts, the exact decimal halfway point to the
  next value up (texts up to 1,077 characters), its negation, a text just above it and
  one just below;
- `%.*e` and `%.*f` (the bytes) of every double above and 5,000 more at
  precisions 0 to 60, and exact ties (odd multiples of 2^−k at precision
  k − 1, and values such as 125, 2.5, 0.5, 2^60 at precisions 0 to 20):
  237,332 calls.

Result: all 571,452 calls give the same bits and bytes in both builds.
The check finds what it should: a plain build with `cos` replaced by a
shifted `sin` differs in 8,368 `cos` calls, one with `strtof` as
`(float)strtod` (double rounding) in 1,339 `strtof` calls (the halfway
texts), one formatting `v * (1 + 2^-52)` in 89,206 `%e`/`%f` calls
(throwaway mutants, not committed).

### Programs

A throwaway run in the SDK's Node, the same runner as step (B) (not
committed: real `write`, `exit` and `now`, `__wasm_call_ctors` then
`__main_argc_argv`), of the 51 programs built by `check.sh`: all 51 give
the emcc lane's stdout, stderr and exit status, without arguments and with
`--gpu 4GB`, which no longer traps (`strtod`). `run/float_printing` and
`run/u32_mod_operator`, which trapped in step (B), print what emcc's build
prints. Two clean builds of `run/float_printing` (`libc.a` and the module)
are byte-identical. Robokill's library was not run again: it gained only
`fmt_fp` on its error path.

### Sizes

`check.sh` (about 4 minutes): all 52 build and validate, and import only
`write exit now`. Sizes in bytes (`sizes.txt`; gzip -9): the plain build
is 86% of emcc's in all (80% gzip-compressed), Robokill 82% (78%); after
step (B) it was 45% (41%) and 67% (62%).

The growth is the musl code: every program takes `strtod` through `main`'s
option parsing (`--gpu`), and with it `floatscan` and the binary128
routines, 18,596 bytes of code in `run/nat_native`; every module takes
`fmt_fp` through the one formatter, which also serves `snprintf` on the
error path, 5,237 bytes (`llvm-nm -S`). The archive itself is 95 KiB; no
module links a math function, as none calls one (step (A)).

| Program | plain | emcc | plain gzip | emcc gzip |
|---|--:|--:|--:|--:|
| `run_nat_native` | 42036 | 50641 | 18700 | 23637 |
| `run_nat_add_infix` | 43849 | 52278 | 19211 | 24143 |
| `run_nat_overflow` | 42020 | 50578 | 18689 | 23621 |
| `reg_nat_chain` | 42369 | 50970 | 18892 | 23815 |
| `reg_nat_table` | 42018 | 50625 | 18691 | 23624 |
| `run_word_arithmetic` | 42016 | 50623 | 18697 | 23628 |
| `run_word_div_mod` | 42016 | 50623 | 18692 | 23624 |
| `run_word_wrap_chains` | 42016 | 50623 | 18697 | 23628 |
| `run_word_bitwise_literals` | 42016 | 50623 | 18700 | 23632 |
| `run_u32_mod_operator` | 48330 | 56622 | 20694 | 25608 |
| `eval_bit_adder` | 42016 | 50623 | 18689 | 23620 |
| `run_float_arithmetic` | 42016 | 50623 | 18697 | 23628 |
| `run_float_printing` | 48741 | 57065 | 20720 | 25666 |
| `run_float_specials` | 42016 | 50623 | 18695 | 23626 |
| `run_float_text_roundtrip` | 42018 | 50625 | 18702 | 23634 |
| `run_computed_match` | 42030 | 50635 | 18698 | 23636 |
| `run_state_machine` | 44280 | 52791 | 19373 | 24231 |
| `run_expr_interpreter` | 47452 | 55613 | 19583 | 24529 |
| `run_bst_insert` | 46135 | 54441 | 20054 | 24956 |
| `run_overuse_clone` | 47836 | 55914 | 19884 | 24753 |
| `run_spare_reuse` | 43849 | 52278 | 19208 | 24142 |
| `eval_either_suite` | 47994 | 56039 | 19951 | 24818 |
| `eval_maybe_ops` | 45795 | 53983 | 19658 | 24524 |
| `eval_tuple_suite` | 43851 | 52280 | 19212 | 24143 |
| `reg_match_value_literal_arm` | 43580 | 51934 | 18984 | 23932 |
| `run_insertion_sort` | 47335 | 55602 | 20083 | 24999 |
| `run_sieve_eratosthenes` | 42846 | 51449 | 18953 | 23893 |
| `run_binary_search` | 43730 | 52303 | 19258 | 24229 |
| `run_fuel_loops` | 42020 | 50627 | 18693 | 23625 |
| `eval_deep_thunk_chain` | 42090 | 50630 | 18712 | 23666 |
| `run_list_map_fold_ops` | 126606 | 126364 | 33752 | 37224 |
| `reg_wnf_deep_chain` | 40111 | 38796 | 18086 | 19107 |
| `run_flat_copy_share` | 42024 | 50629 | 18696 | 23634 |
| `run_fork_shared_flat` | 52965 | 60800 | 21511 | 26374 |
| `run_array_fork_unshare` | 58769 | 66112 | 22351 | 27175 |
| `run_fn_capture_owns` | 49429 | 57327 | 20173 | 25043 |
| `reg_share_tuple_global` | 47890 | 56219 | 20395 | 25202 |
| `reg_brw_shared_fields` | 44394 | 52782 | 19502 | 24393 |
| `reg_closure_capture_once` | 47475 | 55691 | 19847 | 24738 |
| `reg_array_keep_cow` | 48249 | 56519 | 20716 | 25505 |
| `run_string_algorithms` | 64509 | 71205 | 23712 | 28662 |
| `eval_string_escape` | 48514 | 56472 | 20036 | 24925 |
| `io_hello_print` | 42380 | 50971 | 18799 | 23720 |
| `io_do_let_lines` | 43826 | 52257 | 19039 | 24042 |
| `io_text_formatting` | 48603 | 56416 | 20312 | 25135 |
| `io_chan_close_send` | 49931 | 57819 | 20684 | 25406 |
| `io_fiber_single_join` | 54233 | 61505 | 21377 | 26008 |
| `io_deadlock` | 46131 | 54193 | 19771 | 24513 |
| `io_halt_utf8_law` | 38720 | 47494 | 17380 | 22377 |
| `io_nat_host_bounds` | 50074 | 58254 | 19965 | 24867 |
| `io_nat_host_neg` | 44800 | 53244 | 19347 | 24265 |
| `robokill_step` | 28410 | 34619 | 12083 | 15510 |
| `total (52)` | 2434359 | 2845972 | 1023004 | 1271035 |

## Step (D): the loader and the gates

2026-10-17, the toolchain of step (A), patches 0001-0004 and step (C)'s
sources. Emcc still ships: nothing here switches the default build.

### The loader

The plain build reuses the glue (`glue/README.md`) with a second backend
rather than a parallel copy. `glue/glue.mjs` keeps everything both builds
share (the handles, the failure rule, poisoning, `reset()`, the F32
region, the defs' wrappers that `glue/gen.mjs` writes) and calls
`instantiate(lane)`, which `glue/build.sh` appends with the reader, as it
appends `read-web.mjs`/`read-node.mjs`:

- `glue/load-emcc.mjs`: Emscripten's factory (`NAME.lib.mjs`), as before;
- `glue/load-clang.mjs`: `WebAssembly.instantiate` with the three imports
  of module `bend` (`write`: fd 1 and 2 cut into lines, stdout to
  `console.log` and stderr into the error lines, as Emscripten's `print`
  and `printErr`; `exit`: throws, as the Emscripten backend's `proc_exit`;
  `now`: `performance.now()` in nanoseconds), then `__wasm_call_ctors`.

So the shipped page gets only its own build's code, and no Node code
(`glue/test/shipped.sh`). `glue/gen.mjs module FILE.c NAME clang` writes
the same `NAME.wasm.mjs` without the factory's import; `glue/build.sh
--clang` builds with `tools/clang-wasm/build.sh` (its other files in
`OUTDIR/NAME.clang/`) and writes `NAME.wasm.mjs`, `bend-glue.mjs` and
`NAME.lib.wasm`, the names the hosts already import, so
`glue/test/*`, `replay/robokill` and `bench/robokill` load either build
unchanged.

For the tests in Node only, `tools/clang-wasm/node.mjs` hosts the same
three imports on the process (`writeSync`, `process.exit`,
`process.hrtime`): `node.mjs run FILE.wasm ARGS` runs a program
(`__main_argc_argv` with argv placed by the module's `malloc`, argv[0]
`./this.program` as Emscripten's), and `node.mjs factory FILE.wasm` writes
a module with the Emscripten factory's shape as far as the library tests'
drivers use it (`_`-prefixed exports, `HEAPU8`, `HEAPU32`), so
`replay/robokill/replay.mjs`, `probe/lib/drive.mjs` and
`tests/negative/consumed.mjs` run on it unchanged.

### Gates

Each runs from a script; all passed on 2026-10-17 in herdr's worker
sandbox (Apple arm64, the SDK's Node 24.19.0).

| Gate | Script | Result |
|---|---|---|
| Differential, 51 programs | `tests/differential/run.sh`, lane `clang-wasm` (default lanes now `js wasm clang-wasm`) | 153 of 153 ok: stdout, stderr and exit status equal to native on every lane (stderr is now compared on every lane; 5 min 17 s) |
| Negative | `tests/negative/run.sh` | every case caught; the clang lane in the cases below |
| Glue conformance, failure, poisoning, reset, shipped | `glue/test/run.sh --clang` | all ok, as the emcc build (`glue/test/run.sh`) |
| Robokill replay | `replay/robokill/run.sh` (lane `clang`) | 22 checkpoints equal to `replay.bend`, native and emcc's; final hashes 603820250 and 819172968; render hashes equal on all 20,000 frames |
| Heap bound | the same, `BOUND_CLANG` (default `100000 1000000`) | 39,040 words of high-water and 1 live handle at every checkpoint over 1,000,000 frames, as native and emcc's |
| `return_call` for every live `musttail` | `tools/clang-wasm/build.sh`'s check (step B), in every build above | all 52 modules: no segment enters a segment without a tail call; 1,186 sites, 1,187 `return_call`s, all kept by `wasm-opt` |
| Reproducibility | `tools/clang-wasm/repro.sh` | two clean builds into different paths: `libc.a`, the 52 modules and Robokill's shipped glue identical (56 files) |
| Step B and C checks | `tools/clang-wasm/check.sh`, `math-check.sh` | 52 build and validate; 571,452 math, parse and format calls bit-identical to emcc |

Negative cases on the clang lane:

- stale (the real series): `consumed.mjs` on the plain build of
  `probe/lib`'s counter (through `node.mjs factory`) exits 1 with the
  handle message;
- env-abi (patch 0002's two-word `Env` reverted): the clang lane reports
  `reg_nat_chain`, `run_bst_insert`, `run_insertion_sort` and
  `run_string_algorithms`, the emcc lane the first, second and fourth. A
  segment then reads `Env` from a frame the tail call freed; what
  overwrote it, and so which programs go wrong, depends on the code, which
  differs between the builds (both are reproducible, so each set is
  fixed);
- missing-lane: under `BEND_PATCH=0` the run names both wasm lanes as not
  available;
- leak and stale-handle (mutants under `probe/lib/run.sh`): not on the
  clang lane. Their check is `probe/lib/run.sh`, whose wasm driver builds
  with emcc only; giving it a clang lane is a change to `probe/lib`,
  outside this step. The replay's heap bound above covers the clang
  lane's heap, and the stale case its handle check.

### Sizes

Robokill's shipped files (`glue/build.sh`, without `--node`), bytes raw /
`gzip -9 -n`:

| File | emcc | plain clang |
|---|--:|--:|
| `step.wasm.mjs` | 1,928 / 648 | 1,893 / 642 |
| `bend-glue.mjs` | 7,981 / 3,020 | 8,667 / 3,330 |
| `step.lib.mjs` | 8,379 / 2,902 | (none) |
| `step.lib.wasm` | 34,619 / 15,487 | 28,410 / 12,064 |
| total | 52,907 / 22,057 | 38,970 / 16,036 |

gzip-compressed, the plain build ships 27.3% less than emcc's today and
27.4% less than the frozen emcc baseline (22,087, DECISIONS.md, "Memory
in Chrome and the frozen emcc baseline"; its `bend-glue.mjs` and
`step.lib.mjs` have changed since): the 20% criterion holds. Raw, 26.3%
less. `bend-glue.mjs` grew by the backend's comment lines on both builds.

### Node benchmark

`WASM_BUILD=clang bench/robokill/node.sh` against `bench/robokill/node.sh`,
one run each in the sandbox (a shared machine, so the tails are noisy):
ms per frame of step + render, p50, n = 500 and 2,000: emcc 0.065 and
0.315, plain clang 0.066 and 0.314. A Node number, not the criterion.

Both runs first failed at n = 2,000 with "the corpus ... is full":
`node-bench.mjs` dropped each replay's last state without disposing it,
and the wasm lane's fixed corpus fills with them since the memory work;
it now disposes it (emcc and clang alike).

### Not run: the Chrome criteria

Chrome cannot start in the worker sandbox, so these are the coordinator's,
with the user's go:

- linear memory not above the frozen emcc baseline (11,534,336 bytes);
  the plain build has the same pages (176 for Robokill, step B), but
  Chrome's numbers are the criterion;
- frame p95 (step + upload) within 5% of the frozen baseline in
  DECISIONS.md.

`WASM_BUILD=clang bench/robokill/run.sh` runs the page on the plain build
(`bench/robokill/README.md`); its `out/baseline.json` then holds that
build's numbers (`"build": "clang"`), to compare with the frozen one.
`WASM_BUILD=clang bench/robokill/check.sh` passes its sandbox parts (the
page loads the clang lane; the summary); its server part needs a local
port.
