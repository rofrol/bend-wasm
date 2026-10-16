# Vendored musl

The musl sources of the plain-clang wasm build's math, `strtof`, `strtod`
and printf's `%e`/`%f` (TODO t-fwjpak4c, step C; `docs/clang-wasm.md`),
built by `tools/clang-wasm/libc.sh`. They are the files emcc links for the
same calls: copied from the pinned Emscripten SDK 6.0.10
(`~/.cache/bend-wasm/emsdk-6.0.10/upstream/emscripten/system/lib/libc/musl/`,
Emscripten's tree of musl 1.2.6, its `VERSION`), each at the same path
below that directory, and **unmodified** (`cmp` against the SDK, 2026-10-16).
License: musl's MIT license, `COPYRIGHT` here (copied from the same
directory).

Which files: those of emcc's link of a probe calling every function below
(`emcc -Wl,--why-extract=...`), as far as they are musl's.

| For | Files (under `src/math/` unless given) |
|---|---|
| `exp` | `exp.c exp_data.c exp_data.h` |
| `log log2 log10` | `log.c log_data.c log_data.h log2.c log2_data.c log2_data.h log10.c` |
| `sin cos tan` | `sin.c cos.c tan.c __sin.c __cos.c __tan.c __rem_pio2.c __rem_pio2_large.c` |
| `asin acos atan atan2` | `asin.c acos.c atan.c atan2.c` |
| `sinh cosh tanh` | `sinh.c cosh.c tanh.c __expo2.c expm1.c` |
| `pow` | `pow.c pow_data.c pow_data.h` |
| `fmodf` | `fmodf.c` |
| their helpers | `__math_divzero.c __math_invalid.c __math_oflow.c __math_uflow.c __math_xflow.c fabs.c floor.c sqrt.c sqrt_data.h scalbn.c` |
| `strtof strtod` | `src/stdlib/strtod.c`, `src/internal/floatscan.c floatscan.h shgetc.c shgetc.h stdio_impl.h`, and for its `long double` (binary128): `scalbnl.c copysignl.c fmodl.c fabsl.c __fpclassifyl.c` |
| `%e %f` | `src/stdio/vfprintf.c` (its static `fmt_fp`; Emscripten's variant formats `long double` at double precision, as emcc's printf), `frexp.c` |
| headers | `src/internal/libm.h`, `arch/generic/fp_arch.h` |

`floatscan.c` computes in `long double`, binary128 on wasm32, so it calls
compiler-rt's soft-float routines, which `tools/clang-wasm/compiler-rt`
vendors the same way.

## What the build adds

Nothing in these files is edited. What emcc's libc build supplies around
them comes from `tools/clang-wasm/libc/`:

- `features.h`: musl's internal `src/include/features.h` (the public
  header plus `hidden`, `weak`, `weak_alias`), which reaches the public one
  by a relative path into musl's tree; the public headers come from the
  SDK's sysroot here, so this one takes it by `#include_next`.
- `syscall.h`: empty; `stdio_impl.h` includes it, and nothing here makes a
  system call.
- `fmt_fp.c`: includes `vfprintf.c` and adds `bend_fmt_fp`, the entry patch
  0004's printf calls for `%e` and `%f`, over a `FILE` that only collects
  bytes (`__fwritex`). The rest of `vfprintf.c` is never called and the
  linker drops it.
- `uflow.c`: `__uflow`, which `shgetc.c` calls to refill a real `FILE`; the
  only scan here is of a string, which never needs it, so it traps.

`memcpy`, `memset` and `__errno_location` come from patch 0004.

## Updating

When the emsdk pin moves, copy the same paths from the new SDK, check the
list against a new `--why-extract` probe, and run
`tools/clang-wasm/math-check.sh` (bit-exactness against emcc) and
`tools/clang-wasm/check.sh`.
