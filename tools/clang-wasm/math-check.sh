#!/bin/sh
# Checks that the plain-clang wasm build's math, strtof, strtod and %e/%f
# give emcc's results bit for bit (TODO t-fwjpak4c, step C;
# docs/clang-wasm.md):
#
#   tools/clang-wasm/math-check.sh [OUTDIR]
#
# tools/clang-wasm/math-check.c is built twice: by scripts/emcc with
# scripts/wasm-flags, as the emcc lane builds a program (so it links
# emcc's musl), and by plain clang with the flags of tools/clang-wasm/build.sh
# and the archive of tools/clang-wasm/libc.sh. tools/clang-wasm/math-check.mjs
# then calls both over edge vectors and a seeded random sample, in the
# SDK's node, and fails on any difference, which it lists. OUTDIR (default
# tools/clang-wasm/out-math, ignored) gets libc.a, mc.wasm (plain),
# mc.mjs and mc.wasm under emcc/, and math-check.log.
set -u
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1
out=${1:-tools/clang-wasm/out-math}
sdk=${BEND_WASM_EMSDK:-$HOME/.cache/bend-wasm/emsdk-6.0.10}
bin=$sdk/upstream/bin
sysroot=$sdk/upstream/emscripten/cache/sysroot
node=$(find "$sdk/node" -path '*/bin/node' -type f 2>/dev/null | head -n 1)
if [ -z "$node" ]; then
  echo "tools/clang-wasm/math-check.sh: no node in $sdk/node" >&2
  exit 1
fi
mkdir -p "$out/emcc" "$out/tmp"
out=$(cd "$out" && pwd)
# emcc's and clang's temporary files stay in the output directory.
export TMPDIR="$out/tmp"
src=tools/clang-wasm/math-check.c
log=$out/math-check.log
: > "$log"

fail() {
  echo "tools/clang-wasm/math-check.sh: $* (log $log)" >&2
  exit 1
}

sh tools/clang-wasm/libc.sh "$out/libc.a" >> "$log" 2>&1 \
  || fail "the libc archive failed"
"$bin/clang" --target=wasm32 -nostdlib -mbulk-memory -std=c11 -O2 \
  -mtail-call -fno-builtin --sysroot="$sysroot" -c "$src" -o "$out/mc.o" \
  >> "$log" 2>&1 || fail "the plain compile failed"
exports="mc_buf mc_f1 mc_f2 mc_fmodf mc_strtof mc_strtod mc_fmt"
flags=
emflags=
for x in $exports; do
  flags="$flags --export=$x"
  emflags="$emflags,_$x"
done
# shellcheck disable=SC2086 # the flags are words on purpose
"$bin/wasm-ld" --no-entry $flags "$out/mc.o" "$out/libc.a" -o "$out/mc.wasm" \
  >> "$log" 2>&1 || fail "the plain link failed"
# shellcheck disable=SC2046,SC2086
scripts/emcc $(scripts/wasm-flags) -fno-builtin "$src" -o "$out/emcc/mc.mjs" \
  -sMODULARIZE=1 -sEXPORT_ES6=1 -sEXPORTED_FUNCTIONS="${emflags#,}" \
  -sEXPORTED_RUNTIME_METHODS=HEAPU8 >> "$log" 2>&1 \
  || fail "the emcc build failed"
"$node" tools/clang-wasm/math-check.mjs "$out/mc.wasm" "$out/emcc/mc.mjs" \
  > "$out/result.txt" 2>> "$log"
status=$?
cat "$out/result.txt"
rm -rf "$out/tmp"
exit $status
