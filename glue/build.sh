#!/bin/sh
# Builds the wasm lane of a Bend module with the JS lane's shape
# (glue/README.md):
#
#   glue/build.sh [--node] MODULE.bend DEFS OUTDIR NAME   emit C with --lib DEFS
#   glue/build.sh [--node] FILE.c OUTDIR NAME             from library-mode C
#
# Writes into OUTDIR: NAME.wasm.mjs (the module a host imports, from
# glue/gen.mjs), bend-glue.mjs (glue/glue.mjs with the environment's
# reader appended), NAME.lib.mjs and NAME.lib.wasm (the Emscripten build,
# flags of scripts/wasm-flags; the glue compiles the wasm itself), and
# NAME.c when built from a .bend module. Logs go to OUTDIR/NAME.*.log.
#
# Without --node it is the shipped build, for a page: -sENVIRONMENT=web
# and glue/read-web.mjs, no Node code (glue/test/shipped.sh checks).
# --node is the Node-capable build of the tests and the Node benchmark:
# -sENVIRONMENT=web,node and glue/read-node.mjs. The .wasm is the same
# bytes in both (glue/test/shipped.sh compares them).
# Exit status: 0 when every step succeeded.
set -u
env=web environment=web
if [ "${1:-}" = --node ]; then
  env=node environment=web,node
  shift
fi
root=$(cd "$(dirname "$0")/.." && pwd)
sdk=${BEND_WASM_EMSDK:-$HOME/.cache/bend-wasm/emsdk-6.0.10}
node=$(find "$sdk/node" -path '*/bin/node' -type f 2>/dev/null | head -n 1)
if [ -z "$node" ]; then
  echo "glue/build.sh: no node in $sdk/node" >&2
  exit 1
fi
case ${1:-} in
  *.bend)
    [ $# = 4 ] || { echo "usage: glue/build.sh [--node] MODULE.bend DEFS OUTDIR NAME" >&2; exit 2; }
    src=$1 defs=$2 out=$3 name=$4 ;;
  *.c)
    [ $# = 3 ] || { echo "usage: glue/build.sh [--node] FILE.c OUTDIR NAME" >&2; exit 2; }
    src=$1 defs='' out=$2 name=$3 ;;
  *)
    echo "usage: glue/build.sh [--node] MODULE.bend DEFS OUTDIR NAME | FILE.c OUTDIR NAME" >&2
    exit 2 ;;
esac
mkdir -p "$out/tmp-$name"
out=$(cd "$out" && pwd)
# clang's and Bend's temporary files stay in the output directory.
export TMPDIR="$out/tmp-$name"

step() {
  log=$out/$name.$1.log
  shift
  if ! "$@" > "$log" 2>&1; then
    echo "glue/build.sh: $* failed:" >&2
    tail -n 20 "$log" >&2
    exit 1
  fi
}

c=$src
if [ -n "$defs" ]; then
  c=$out/$name.c
  step emit "$root/scripts/bend" "$src" -o "$c" --lib "$defs"
fi
exports=$("$node" "$root/glue/gen.mjs" exports "$c") || exit 1
# FILESYSTEM=0: the library uses no file system. The runtime's file
# access (the cgroup CPU quota under __linux__, the CUDA cache under
# BEND_CUDA, the IO thread's wake pipe) does not reach a wasm library:
# Robokill's step.wasm imports only fd_write, fd_seek and fd_close
# (stdio on stdout and stderr), proc_exit, emscripten_get_now and
# emscripten_resize_heap, which FILESYSTEM=0 keeps.
# shellcheck disable=SC2046 # the flags are words on purpose
step wasm "$root/scripts/emcc" $("$root/scripts/wasm-flags") -sMODULARIZE \
  -sEXPORT_ES6 -sENVIRONMENT=$environment -sFILESYSTEM=0 \
  -sEXPORTED_FUNCTIONS="$exports" "$c" -o "$out/$name.lib.mjs"
"$node" "$root/glue/gen.mjs" module "$c" "$name" > "$out/$name.wasm.mjs.tmp" \
  || exit 1
mv "$out/$name.wasm.mjs.tmp" "$out/$name.wasm.mjs"
cat "$root/glue/glue.mjs" "$root/glue/read-$env.mjs" > "$out/bend-glue.mjs"
rm -rf "$TMPDIR"
