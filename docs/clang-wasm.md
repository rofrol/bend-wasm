# Plain-clang wasm build: the libc gap

TODO t-fwjpak4c, step (A): what does Bend's emitted C need from a libc when
it is compiled for wasm32 by plain clang, without emcc? This sizes steps
(B) (mem*, allocator, printing, abort, host imports, `wasm-ld --no-entry`)
and (C) (math from vendored musl).

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
