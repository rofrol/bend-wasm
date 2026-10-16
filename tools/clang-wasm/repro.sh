#!/bin/sh
# Two clean builds of the plain-clang wasm give identical artifacts (TODO
# t-fwjpak4c, step D; docs/clang-wasm.md):
#
#   tools/clang-wasm/repro.sh [OUTDIR]
#
# Emits the C of every program of tests/differential/corpus.txt and of
# Robokill's step library once (the emitted C's own reproducibility is
# tests/repro/run.sh's), then builds everything twice, into OUTDIR/a and
# OUTDIR/b (default tools/clang-wasm/out-repro, ignored), each from
# nothing: its own libc.a (tools/clang-wasm/libc.sh), every module
# (tools/clang-wasm/build.sh), and Robokill's shipped glue (glue/build.sh
# --clang: step.wasm.mjs, bend-glue.mjs, step.lib.wasm). The two output
# directories have different paths, so a path that leaks into an artifact
# shows. Compares libc.a, every NAME.wasm and the shipped files with cmp.
# Exit status: 0 when every pair is identical.
set -u
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1
out=${1:-tools/clang-wasm/out-repro}
rm -rf "$out"
mkdir -p "$out/c" "$out/tmp"
out=$(cd "$out" && pwd)
export TMPDIR="$out/tmp"

names=
while read -r src rest; do
  case $src in '' | '#'*) continue ;; esac
  name=$(echo "$src" | sed 's|^vendor/bend/tests/||; s|\.bend$||; s|/|_|g')
  scripts/bend "$src" -o "$out/c/$name.c" > "$out/c/$name.log" 2>&1 \
    || { echo "FAILED: emit $name (log $out/c/$name.log)"; exit 1; }
  names="$names $name"
done < tests/differential/corpus.txt
scripts/bend replay/robokill/step.bend -o "$out/c/robokill_step.c" \
  --lib init,input_at,step,hash,render > "$out/c/robokill_step.log" 2>&1 \
  || { echo "FAILED: emit robokill_step"; exit 1; }
names="$names robokill_step"

for run in a b; do
  for name in $names; do
    sh tools/clang-wasm/build.sh "$out/c/$name.c" "$out/$run" "$name" \
      2> "$out/$run.err" || { cat "$out/$run.err"; exit 1; }
    # Up to 10 MB each (the static corpus); the modules are compared.
    rm -f "$out/$run/$name.o"
  done
  sh glue/build.sh --clang "$out/c/robokill_step.c" "$out/$run/glue" step \
    || exit 1
done

status=0
n=0
for f in libc.a $(for name in $names; do echo "$name.wasm"; done) \
  glue/step.wasm.mjs glue/bend-glue.mjs glue/step.lib.wasm; do
  n=$((n + 1))
  if ! cmp "$out/a/$f" "$out/b/$f"; then
    echo "FAILED: $f differs between two clean builds"
    status=1
  fi
done
rm -rf "$out/tmp"
[ "$status" = 0 ] && echo "ok: two clean builds give identical artifacts" \
  "($n files: libc.a, $(echo "$names" | wc -w | tr -d ' ') modules," \
  "Robokill's shipped glue)"
exit $status
