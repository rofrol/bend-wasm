#!/bin/sh
# Builds both lanes of Robokill's simulation into bench/robokill/dist/
# (ignored), where the page and the Node benchmark import them
# (bench/robokill/README.md), from replay/robokill/step.bend (Robokill's
# spike/step.bend at 63031ab):
#
# - dist/step.mjs, the JS lane: `scripts/bend step.bend -o step.mjs`, as
#   Robokill builds spike/dist/step.mjs;
# - dist/step.wasm.mjs and its files, the wasm lane: glue/build.sh with
#   --lib init,input_at,step,hash,render.
#
# Exit status: 0 when both built.
set -u
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
dist=bench/robokill/dist
rm -rf "$dist"
mkdir -p "$dist/tmp"
if ! TMPDIR="$root/$dist/tmp" scripts/bend replay/robokill/step.bend \
  -o "$dist/step.mjs" > "$dist/step.js.log" 2>&1; then
  echo "bench/robokill/build.sh: the JS lane failed:" >&2
  tail -n 20 "$dist/step.js.log" >&2
  exit 1
fi
rm -rf "$dist/tmp"
sh glue/build.sh replay/robokill/step.bend init,input_at,step,hash,render \
  "$dist" step
