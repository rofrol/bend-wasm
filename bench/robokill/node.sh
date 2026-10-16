#!/bin/sh
# The paired Node benchmark (bench/robokill/README.md): builds both lanes
# (build.sh) and runs node-bench.mjs in the SDK's Node. BLOCKS, FRAMES and
# SIZES pass through. The report goes to stdout and out/node.md, the raw
# numbers to out/node.json (out/ is ignored), with `scripts/bend
# --toolchain` above the report.
# Exit status: 0 when the build and the run succeeded (the run checks the
# final hashes of RESULTS.md on both lanes).
set -u
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
here=bench/robokill
sdk=${BEND_WASM_EMSDK:-$HOME/.cache/bend-wasm/emsdk-6.0.10}
node=$(find "$sdk/node" -path '*/bin/node' -type f 2>/dev/null | head -n 1)
if [ -z "$node" ]; then
  echo "bench/robokill/node.sh: no node in $sdk/node" >&2
  exit 1
fi
sh "$here/build.sh" || exit 1
mkdir -p "$here/out"
{
  scripts/bend --toolchain
  echo
  "$node" "$here/node-bench.mjs" "$here/dist/step.mjs" \
    "$here/dist/step.wasm.mjs" "$here/out/node.json"
} > "$here/out/node.md.tmp" || exit 1
mv "$here/out/node.md.tmp" "$here/out/node.md"
cat "$here/out/node.md"
