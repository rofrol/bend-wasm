#!/bin/sh
# Builds the part of the plain-clang wasm build's libc that comes from
# vendored sources (TODO t-fwjpak4c, step C; docs/clang-wasm.md) into one
# archive, so a module links only what it calls:
#
#   tools/clang-wasm/libc.sh OUT.a
#
# - musl (tools/clang-wasm/musl, README.md there): the math functions the
#   emitter can call, strtof and strtod, and fmt_fp, printf's %e and %f;
# - compiler-rt (tools/clang-wasm/compiler-rt): the binary128 soft-float
#   routines musl's strtod calls for its long double (binary128 on wasm32);
# - tools/clang-wasm/libc: bend_fmt_fp, the entry into musl's fmt_fp, and
#   the shims those sources need.
#
# These are the sources emcc links for the same calls, built with emcc's
# flags for its libc (-D_XOPEN_SOURCE=700, -O2, -fno-builtin: clang must
# not replace musl's own calls by builtins), except:
# - -std=c11 for its -std=c99: before C11 the sysroot's stdio.h defines a
#   placeholder struct _IO_FILE, which musl's stdio_impl.h then redefines
#   (emcc's libc build puts musl's src/include/stdio.h first instead);
# - -ffp-contract=off -fno-fast-math: no contraction into fused
#   multiply-add and no reassociation or other value-changing rewrite, each
#   of which would change the rounding of a result. They are clang's
#   defaults for wasm (which has no fma instruction); the flags hold the
#   guarantee should a default change;
# - -w: the warnings are musl's and compiler-rt's own.
#
# OUT.a is rebuilt only when it is missing or older than one of those
# sources or this script, and is published by rename. Fails when a step
# fails. BEND_WASM_EMSDK points to another install of the same pin.
set -u
if [ $# != 1 ]; then
  echo "usage: tools/clang-wasm/libc.sh OUT.a" >&2
  exit 2
fi
lib=$1
v=$(cd "$(dirname "$0")" && pwd)
sdk=${BEND_WASM_EMSDK:-$HOME/.cache/bend-wasm/emsdk-6.0.10}
bin=$sdk/upstream/bin
sysroot=$sdk/upstream/emscripten/cache/sysroot
if [ -f "$lib" ] && [ -z "$(find "$v/musl" "$v/compiler-rt" "$v/libc" \
  "$v/libc.sh" -newer "$lib" -type f 2>/dev/null | head -n 1)" ]; then
  exit 0
fi
for tool in clang llvm-ar; do
  if [ ! -x "$bin/$tool" ]; then
    echo "tools/clang-wasm/libc.sh: no $tool in $bin" >&2
    exit 1
  fi
done
lo=$lib.o.$$
log=$lib.log
rm -rf "$lo"
mkdir -p "$lo"
: > "$log"

fail() {
  echo "tools/clang-wasm/libc.sh: $* (log $log)" >&2
  rm -rf "$lo" "$lib.$$"
  exit 1
}

base="--target=wasm32 -nostdlib -mbulk-memory -mtail-call -O2 -fno-builtin
  -ffp-contract=off -fno-fast-math -w --sysroot=$sysroot"
for s in "$v"/musl/src/*/*.c "$v"/libc/*.c; do
  case $s in
    # Included by libc/fmt_fp.c, for its static fmt_fp.
    */musl/src/stdio/vfprintf.c) continue ;;
  esac
  # shellcheck disable=SC2086 # the flags are words on purpose
  "$bin/clang" $base -std=c11 -D__EMSCRIPTEN__ -D_XOPEN_SOURCE=700 \
    -I"$v/libc" -I"$v/musl/src/internal" -I"$v/musl/arch/generic" \
    -I"$v/musl/src/stdio" -c "$s" -o "$lo/$(basename "$s" .c).o" \
    >> "$log" 2>&1 || fail "compiling $s failed"
done
for s in "$v"/compiler-rt/lib/builtins/*.c; do
  # shellcheck disable=SC2086
  "$bin/clang" $base -DNDEBUG -c "$s" -o "$lo/crt_$(basename "$s" .c).o" \
    >> "$log" 2>&1 || fail "compiling $s failed"
done
rm -f "$lib.$$"
"$bin/llvm-ar" rcsD "$lib.$$" "$lo"/*.o >> "$log" 2>&1 || fail "llvm-ar failed"
mv "$lib.$$" "$lib"
rm -rf "$lo"
exit 0
