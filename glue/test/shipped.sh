#!/bin/sh
# Checks a shipped build of glue/build.sh against the Node-capable build
# of the same C (glue/README.md, "Build"):
#
#   glue/test/shipped.sh WEBDIR NODEDIR NAME
#
# - the shipped NAME.wasm.mjs, bend-glue.mjs and NAME.lib.mjs (the
#   Emscripten build's factory; the plain-clang build has none, and its
#   NAME.wasm.mjs imports none) in WEBDIR name none of Node's require, process, Buffer, fs, path, __dirname or a
#   node: module. `path` counts as Node's module only as `path.` or a
#   "path" specifier: Emscripten's locateFile(path) in NAME.lib.mjs has a
#   parameter of that name, and a use of the module would read `path.`
#   (`require("path")` and `node:path` are caught as require and node:);
# - WEBDIR/NAME.lib.wasm and NODEDIR/NAME.lib.wasm are the same bytes, so
#   the tests and the Node benchmark run the wasm that ships.
#
# Exit status: 0 when both hold.
set -u
[ $# = 3 ] || { echo "usage: glue/test/shipped.sh WEBDIR NODEDIR NAME" >&2; exit 2; }
web=$1 node=$2 name=$3
status=0
js="$web/$name.wasm.mjs $web/bend-glue.mjs"
if grep -q "^import load from \"./$name.lib.mjs\";$" "$web/$name.wasm.mjs"; then
  js="$js $web/$name.lib.mjs"
fi
for f in $js; do
  [ -f "$f" ] || { echo "FAILED: no $f"; exit 1; }
  hits=$(grep -noE '\b(require|process|Buffer|fs|__dirname)\b|node:|\bpath\.|"path"' "$f")
  if [ -n "$hits" ]; then
    echo "FAILED: $f names Node: $(echo "$hits" | sort -u | tr '\n' ' ')"
    status=1
  fi
done
if ! cmp "$web/$name.lib.wasm" "$node/$name.lib.wasm"; then
  echo "FAILED: the shipped and the Node-capable $name.lib.wasm differ"
  status=1
fi
[ "$status" = 0 ] && echo "ok: the shipped $name names no Node API and" \
  "its wasm is the Node-capable build's, byte for byte"
exit "$status"
