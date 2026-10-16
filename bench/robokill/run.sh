#!/bin/sh
# The Chrome benchmark of Robokill's page against both lanes
# (bench/robokill/README.md). Builds both lanes (build.sh), then for each
# of BLOCKS blocks (default 5) runs the page once per lane, the lane order
# alternating (js first in odd blocks), the way Robokill's spike/serve.mjs
# does: `node serve.mjs PORT RESULTS PROFILE "lane=L&QUERY"` serves this
# directory cross-origin isolated, starts a separate Chrome with a fresh
# profile on the page and exits once the page has posted its results.
# QUERY defaults to "n=500,2000&frames=10000" (RESULTS.md's run), PORT to
# 8642. Then summary.mjs writes out/chrome.md.
#
# Chrome cannot start inside the herdr worker sandbox: run this outside it,
# on a Mac with WebGPU, with the Chrome window in front (rAF slows down
# when it is hidden). CHROME is serve.mjs's path, /Applications/Google
# Chrome.app.
# Output: bench/robokill/out/ (ignored): <block>-<lane>.json, their
# .chrome.log (V8 GC trace), chrome.md. Exit status: 0 when every run
# posted results, the lanes' hashes agree and summary.mjs's checks hold.
set -u
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
here=bench/robokill
out=$root/$here/out
sdk=${BEND_WASM_EMSDK:-$HOME/.cache/bend-wasm/emsdk-6.0.10}
node=$(find "$sdk/node" -path '*/bin/node' -type f 2>/dev/null | head -n 1)
if [ -z "$node" ]; then
  echo "bench/robokill/run.sh: no node in $sdk/node" >&2
  exit 1
fi
blocks=${BLOCKS:-5}
query=${QUERY:-n=500,2000&frames=10000}
port=${PORT:-8642}

sh "$here/build.sh" || exit 1
rm -rf "$out"
mkdir -p "$out"
scripts/bend --toolchain > "$out/toolchain.txt"

b=1
while [ "$b" -le "$blocks" ]; do
  if [ $((b % 2)) = 1 ]; then order="js wasm"; else order="wasm js"; fi
  for lane in $order; do
    profile=$out/profile-$b-$lane
    echo "block $b/$blocks, lane $lane"
    "$node" "$here/serve.mjs" "$port" "$out/$b-$lane.json" "$profile" \
      "lane=$lane&$query"
    code=$?
    rm -rf "$profile"
    if [ "$code" != 0 ]; then
      echo "bench/robokill/run.sh: block $b lane $lane: serve.mjs exited" \
        "$code (1: the page reported an error, 2: Chrome exited first)" >&2
      exit 1
    fi
  done
  b=$((b + 1))
done

{
  cat "$out/toolchain.txt"
  echo
  "$node" "$here/summary.mjs" "$out"
} > "$out/chrome.md"
code=$?
cat "$out/chrome.md"
exit "$code"
