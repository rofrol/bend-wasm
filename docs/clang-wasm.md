# Plain-clang wasm build

TODO t-fwjpak4c, step (A): what does Bend's emitted C need from a libc when
it is compiled for wasm32 by plain clang, without emcc? This sizes steps
(B) (mem*, allocator, printing, abort, host imports, `wasm-ld --no-entry`)
and (C) (math from vendored musl). Step (B), the build itself, is at the
end ("Step (B): the freestanding build").

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
  `fmt_fp`), the latter two needed by F32 printing.
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
No libc, compiler-rt or crt is linked, and none is needed: the link
fails on any undefined symbol.

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
| `fmt_fp` | `(out i32, cap i32, v f64, prec i32, conv i32) -> i32` | `%e`/`%f` of a double (`conv` 101 or 102) into `out`, its length; F32 text. Traps until step (C) |
| `strtof`, `strtod` | `(s i32, end i32) -> f32 / f64` | F32 text read back; `main`'s `--gpu` size. Trap until step (C) |
| `exp log log2 log10 sin cos tan asin acos atan sinh cosh tanh` | `(f64) -> f64` | F32 math. Trap until step (C) |
| `atan2 pow` | `(f64, f64) -> f64` | the same |
| `fmodf` | `(f32, f32) -> f32` | the same |

What the 52 modules import (`check.sh` instantiates each with stubs):

- 47 programs: `write exit now`, unresolved `strtod fmt_fp`;
- `run/float_printing`, `run/u32_mod_operator`: `write exit now`,
  unresolved `strtof strtod fmt_fp`;
- `reg/wnf_deep_chain`: `write exit`, unresolved `strtof strtod fmt_fp`;
- `io/halt_utf8_law`: `write exit`, unresolved `strtod fmt_fp`;
- Robokill's library: `write exit`, unresolved `fmt_fp`.

Every module imports `fmt_fp`, because the one formatter also serves
`snprintf` on the error path; every program imports `strtod` through
`main`'s option parsing, and `--gpu 4GB` traps there until step (C) (emcc
parses it and then ignores it, the program having no `!`). No module
imports a math function.

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
`fmt_fp`. Robokill's library run the same way (n = 500, seed 12345,
10,000 frames) hashes 603820250, as its RESULTS.md, and a stale handle
gives the library's message and exit 1.

Sizes in bytes (`check.sh`'s `sizes.txt`; gzip -9): the plain build is 45%
of emcc's in all (41% gzip-compressed), Robokill 67% (62%). emcc's module
carries musl's stdio and dlmalloc; emcc also optimizes the code with
wasm-opt -O2, which the plain build does not, so the code itself differs
(step (A)'s note on emcc's flags holds too).

| Program | plain | emcc | plain gzip | emcc gzip |
|---|--:|--:|--:|--:|
| `run_nat_native` | 19485 | 50641 | 8951 | 23637 |
| `run_nat_add_infix` | 21299 | 52278 | 9451 | 24143 |
| `run_nat_overflow` | 19469 | 50578 | 8938 | 23621 |
| `reg_nat_chain` | 19819 | 50970 | 9152 | 23815 |
| `reg_nat_table` | 19467 | 50625 | 8939 | 23624 |
| `run_word_arithmetic` | 19465 | 50623 | 8946 | 23628 |
| `run_word_div_mod` | 19465 | 50623 | 8942 | 23624 |
| `run_word_wrap_chains` | 19465 | 50623 | 8946 | 23628 |
| `run_word_bitwise_literals` | 19465 | 50623 | 8950 | 23632 |
| `run_u32_mod_operator` | 25148 | 56622 | 10729 | 25608 |
| `eval_bit_adder` | 19465 | 50623 | 8939 | 23620 |
| `run_float_arithmetic` | 19465 | 50623 | 8947 | 23628 |
| `run_float_printing` | 25567 | 57065 | 10760 | 25666 |
| `run_float_specials` | 19465 | 50623 | 8945 | 23626 |
| `run_float_text_roundtrip` | 19467 | 50625 | 8950 | 23634 |
| `run_computed_match` | 19479 | 50635 | 8947 | 23636 |
| `run_state_machine` | 21728 | 52791 | 9602 | 24231 |
| `run_expr_interpreter` | 24901 | 55613 | 9809 | 24529 |
| `run_bst_insert` | 23577 | 54441 | 10293 | 24956 |
| `run_overuse_clone` | 25277 | 55914 | 10098 | 24753 |
| `run_spare_reuse` | 21299 | 52278 | 9448 | 24142 |
| `eval_either_suite` | 25436 | 56039 | 10176 | 24818 |
| `eval_maybe_ops` | 23237 | 53983 | 9891 | 24524 |
| `eval_tuple_suite` | 21301 | 52280 | 9452 | 24143 |
| `reg_match_value_literal_arm` | 21022 | 51934 | 9228 | 23932 |
| `run_insertion_sort` | 24776 | 55602 | 10317 | 24999 |
| `run_sieve_eratosthenes` | 20295 | 51449 | 9199 | 23893 |
| `run_binary_search` | 21179 | 52303 | 9521 | 24229 |
| `run_fuel_loops` | 19469 | 50627 | 8944 | 23625 |
| `eval_deep_thunk_chain` | 19539 | 50630 | 8966 | 23666 |
| `run_list_map_fold_ops` | 103834 | 126364 | 24008 | 37224 |
| `reg_wnf_deep_chain` | 16922 | 38796 | 8136 | 19107 |
| `run_flat_copy_share` | 19473 | 50629 | 8948 | 23634 |
| `run_fork_shared_flat` | 30399 | 60800 | 11724 | 26374 |
| `run_array_fork_unshare` | 36219 | 66112 | 12621 | 27175 |
| `run_fn_capture_owns` | 26871 | 57327 | 10385 | 25043 |
| `reg_share_tuple_global` | 25339 | 56219 | 10632 | 25202 |
| `reg_brw_shared_fields` | 21844 | 52782 | 9753 | 24393 |
| `reg_closure_capture_once` | 24924 | 55691 | 10080 | 24738 |
| `reg_array_keep_cow` | 25691 | 56519 | 10969 | 25505 |
| `run_string_algorithms` | 41951 | 71205 | 13955 | 28662 |
| `eval_string_escape` | 25955 | 56472 | 10251 | 24925 |
| `io_hello_print` | 19829 | 50971 | 9042 | 23720 |
| `io_do_let_lines` | 21273 | 52257 | 9293 | 24042 |
| `io_text_formatting` | 26045 | 56416 | 10535 | 25135 |
| `io_chan_close_send` | 27381 | 57819 | 10905 | 25406 |
| `io_fiber_single_join` | 31684 | 61505 | 11606 | 26008 |
| `io_deadlock` | 23580 | 54193 | 9995 | 24513 |
| `io_halt_utf8_law` | 16172 | 47494 | 7640 | 22377 |
| `io_nat_host_bounds` | 27525 | 58254 | 10175 | 24867 |
| `io_nat_host_neg` | 22251 | 53244 | 9589 | 24265 |
| `robokill_step` | 23238 | 34619 | 9628 | 15510 |
| `total (52)` | 1276891 | 2845972 | 522246 | 1271035 |
