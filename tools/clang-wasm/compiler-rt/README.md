# Vendored compiler-rt builtins

The soft-float routines musl's `strtof`/`strtod` call for their
`long double`, which is IEEE binary128 on wasm32 and has no wasm
instructions (TODO t-fwjpak4c, step C; `../musl/README.md`), built by
`tools/clang-wasm/libc.sh`. They are the members of emcc's
`libclang_rt.builtins.a` that its link of the same calls takes
(`emcc -Wl,--why-extract=...`): copied from the pinned Emscripten SDK 6.0.10
(`~/.cache/bend-wasm/emsdk-6.0.10/upstream/emscripten/system/lib/compiler-rt/`),
each at the same path below that directory, and **unmodified** (`cmp`
against the SDK, 2026-10-16). License: Apache 2.0 with LLVM Exceptions,
`LICENSE.TXT` and `CREDITS.TXT` here (copied from the same directory).

| For | Files (under `lib/builtins/`) |
|---|---|
| binary128 `+ - * /` | `addtf3.c subtf3.c multf3.c divtf3.c fp_add_impl.inc fp_mul_impl.inc fp_div_impl.inc` |
| comparisons | `comparetf2.c fp_compare_impl.inc` |
| conversions | `extenddftf2.c extendsftf2.c trunctfdf2.c trunctfsf2.c floatsitf.c floatunsitf.c fp_extend.h fp_extend_impl.inc fp_trunc.h fp_trunc_impl.inc int_to_fp.h int_to_fp_impl.inc` |
| 128-bit integers | `ashlti3.c lshrti3.c multi3.c` |
| rounding mode | `fp_mode.c fp_mode.h` (round to nearest; wasm has no other) |
| headers | `fp_lib.h int_endianness.h int_lib.h int_math.h int_types.h int_util.h` |
