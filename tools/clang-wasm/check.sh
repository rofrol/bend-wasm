#!/bin/sh
# Builds every program of tests/differential/corpus.txt and Robokill's step
# library (replay/robokill/step.bend --lib init,input_at,step,hash,render,
# as glue/build.sh builds it) with tools/clang-wasm/build.sh, the plain
# clang build of TODO t-fwjpak4c steps B and C (docs/clang-wasm.md), and
# validates each module with tools/clang-wasm/check.mjs in the SDK's node:
# it instantiates with stub imports, lists them and fails on a missing
# export or an import the host does not serve. Nothing runs here: the
# programs run in tests/differential/run.sh's clang-wasm lane
# (tools/clang-wasm/node.mjs), the library through glue/build.sh --clang
# (step D), and tools/clang-wasm/math-check.sh runs the musl part.
#
# For the sizes, each C is also built with emcc as today (scripts/emcc and
# scripts/wasm-flags for a program, as tests/differential/run.sh; the
# library through glue/build.sh).
#
#   tools/clang-wasm/check.sh [OUTDIR]
#
# OUTDIR (default tools/clang-wasm/out-check, ignored) gets per program
# NAME.c, NAME.wasm and build.sh's files, NAME.check (check.mjs's line),
# the emcc build under emcc/, and sizes.txt: per program the bytes of the
# plain and the emcc .wasm, raw and gzip -9, and the totals. Exit status:
# 0 when every program emitted, built and validated, and emcc built.
set -u
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1
out=${1:-tools/clang-wasm/out-check}
sdk=${BEND_WASM_EMSDK:-$HOME/.cache/bend-wasm/emsdk-6.0.10}
node=$(find "$sdk/node" -path '*/bin/node' -type f 2>/dev/null | head -n 1)
if [ -z "$node" ]; then
  echo "tools/clang-wasm/check.sh: no node in $sdk/node" >&2
  exit 1
fi
rm -rf "$out"
mkdir -p "$out/tmp" "$out/emcc"
out=$(cd "$out" && pwd)
# clang's, emcc's and Bend's temporary files stay in the output directory.
export TMPDIR="$out/tmp"
status=0
programs=0
printf '%-40s %10s %10s %8s %8s\n' program plain emcc plain.gz emcc.gz \
  > "$out/sizes.txt"

gz() {
  gzip -9 -c "$1" | wc -c | tr -d ' '
}

# check NAME SRC [--lib DEFS]: one program, into $out/NAME.*.
check() {
  name=$1 src=$2
  shift 2
  programs=$((programs + 1))
  b=$out/$name
  if ! scripts/bend "$src" -o "$b.c" "$@" > "$b.emit.log" 2>&1; then
    echo "$name: FAILED, emit: $(head -n 1 "$b.emit.log")"
    status=1
    return
  fi
  if ! sh tools/clang-wasm/build.sh "$b.c" "$out" "$name" 2> "$b.err"; then
    echo "$name: FAILED, $(head -n 1 "$b.err")"
    status=1
    return
  fi
  if ! "$node" tools/clang-wasm/check.mjs validate "$b.wasm" "$b.exports" \
    > "$b.check" 2>&1; then
    echo "$name: FAILED, $(head -n 1 "$b.check")"
    status=1
    return
  fi
  e=$out/emcc/$name
  if [ $# = 0 ]; then
    # shellcheck disable=SC2046 # the flags are words on purpose
    scripts/emcc $("$root/scripts/wasm-flags") "$b.c" -o "$e.js" \
      > "$e.log" 2>&1 && ew=$e.wasm
  else
    sh glue/build.sh "$b.c" "$out/emcc" "$name" > "$e.log" 2>&1 \
      && ew=$e.lib.wasm
  fi
  if [ ! -f "${ew:-}" ]; then
    echo "$name: FAILED, the emcc build (log $e.log)"
    status=1
    return
  fi
  printf '%-40s %10s %10s %8s %8s\n' "$name" "$(wc -c < "$b.wasm" | tr -d ' ')" \
    "$(wc -c < "$ew" | tr -d ' ')" "$(gz "$b.wasm")" "$(gz "$ew")" \
    >> "$out/sizes.txt"
  echo "$name: ok, $(head -n 2 "$b.tail" | sed 's/.*: //' | tr '\n' ' ' \
    | sed 's/ $//; s/ / musttail, /')" "return_call; $(cat "$b.check")"
  unset ew
}

while read -r src rest; do
  case $src in '' | '#'*) continue ;; esac
  check "$(echo "$src" | sed 's|^vendor/bend/tests/||; s|\.bend$||; s|/|_|g')" \
    "$src"
done < tests/differential/corpus.txt
check robokill_step replay/robokill/step.bend --lib init,input_at,step,hash,render

awk 'NR > 1 { p += $2; e += $3; pg += $4; eg += $5; n += 1 }
  END { printf "%-40s %10d %10d %8d %8d\n", "total (" n ")", p, e, pg, eg }' \
  "$out/sizes.txt" >> "$out/sizes.txt"
tail -n 1 "$out/sizes.txt"
echo "programs: $programs"
rm -rf "$out/tmp"
exit $status
