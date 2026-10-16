#!/bin/sh
# The paired Node benchmark (bench/robokill/README.md): builds both lanes
# (build.sh), the Node-capable build of the wasm lane's dist/step.c into
# out/node-dist/ (glue/build.sh --node; glue/test/shipped.sh checks that
# its wasm is the shipped one) and runs node-bench.mjs on dist/step.mjs and
# out/node-dist/step.wasm.mjs in the SDK's Node. BLOCKS, FRAMES and
# SIZES pass through, and WASM_BUILD (build.sh) picks the wasm lane's
# build for both. The report goes to stdout and out/node.md, the raw
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
rm -rf "$here/out/node-dist"
build=
[ "${WASM_BUILD:-emcc}" = clang ] && build=--clang
# shellcheck disable=SC2086 # $build is empty or one word
sh glue/build.sh --node $build "$here/dist/step.c" "$here/out/node-dist" step \
  || exit 1
sh glue/test/shipped.sh "$here/dist" "$here/out/node-dist" step || exit 1
{
  scripts/bend --toolchain
  echo
  "$node" "$here/node-bench.mjs" "$here/dist/step.mjs" \
    "$here/out/node-dist/step.wasm.mjs" "$here/out/node.json"
} > "$here/out/node.md.tmp" || exit 1
mv "$here/out/node.md.tmp" "$here/out/node.md"
cat "$here/out/node.md"
