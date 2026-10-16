#!/bin/sh
# The browserless checks of the Chrome benchmark (check.mjs): builds both
# lanes (build.sh) and runs check.mjs in the SDK's Node on PORT (default
# 8643, beside run.sh's 8642). WASM_BUILD=clang checks the plain-clang
# build of the wasm lane (build.sh). Exit status: 0 when every check holds.
set -u
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
here=bench/robokill
sdk=${BEND_WASM_EMSDK:-$HOME/.cache/bend-wasm/emsdk-6.0.10}
node=$(find "$sdk/node" -path '*/bin/node' -type f 2>/dev/null | head -n 1)
if [ -z "$node" ]; then
  echo "bench/robokill/check.sh: no node in $sdk/node" >&2
  exit 1
fi
sh "$here/build.sh" || exit 1
"$node" "$here/check.mjs" "${PORT:-8643}"
