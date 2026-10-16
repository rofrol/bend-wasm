#!/bin/sh
# Persistent-state spike (probe/lib/README.md): builds counter.bend in
# library mode (patch 0003) and runs it from a native C driver (drive.c)
# and from Node on the wasm build (drive.mjs, scripts/wasm-flags). Each
# driver prints its peeks and the heap high-water mark per checkpoint.
# Checks: native and wasm print the same lines; their peeks equal what
# counter.bend's own main prints (built natively, `-o bin`: the JS lane
# takes minutes for 100,000 steps); using a disposed handle fails with
# exit 1 and the handle message on both.
#
# Output: probe/lib/out/ (ignored). Exit status: 0 when every check holds.
# The heap numbers are reported, not judged: the kill criterion
# (docs/decisions/0001) is read from them.
set -u
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
here=probe/lib
out=$here/out
sdk=${BEND_WASM_EMSDK:-$HOME/.cache/bend-wasm/emsdk-6.0.10}
node=$(find "$sdk/node" -path '*/bin/node' -type f 2>/dev/null | head -n 1)
if [ -z "$node" ]; then
  echo "probe/lib/run.sh: no node in $sdk/node" >&2
  exit 1
fi
cc=${CC:-clang}
exports=_bend_init,_bend_dispose,_bend_heap_words,_bend_def_init,_bend_def_step,_bend_def_peek

rm -rf "$out"
mkdir -p "$out/tmp"
# clang's and Bend's temporary files stay in the output directory.
export TMPDIR="$root/$out/tmp"
status=0
fail() {
  echo "FAILED: $*"
  status=1
}

step() {
  log=$out/$1.log
  shift
  if ! "$@" > "$log" 2>&1; then
    echo "probe/lib/run.sh: $* failed:" >&2
    tail -n 20 "$log" >&2
    exit 1
  fi
}

step main scripts/bend "$here/counter.bend" -o "$out/main.bin"
step lib scripts/bend "$here/counter.bend" -o "$out/counter.c" \
  --lib init,step,peek
step native "$cc" -std=c11 -O3 "$out/counter.c" "$here/drive.c" -lpthread \
  -lm -o "$out/drive"
# shellcheck disable=SC2046 # the flags are words on purpose
step wasm scripts/emcc $(scripts/wasm-flags) -sMODULARIZE -sEXPORT_ES6 \
  -sEXPORTED_FUNCTIONS=$exports "$out/counter.c" -o "$out/counter.mjs"

"$out/main.bin" > "$out/main.out" || fail "main exited $?"
"$out/drive" > "$out/native.out" || fail "native driver exited $?"
"$node" "$here/drive.mjs" "$out/counter.mjs" > "$out/wasm.out" \
  || fail "wasm driver exited $?"

echo "native:"
cat "$out/native.out"
echo "wasm:"
cat "$out/wasm.out"
echo "main: $(cat "$out/main.out")"

cmp -s "$out/native.out" "$out/wasm.out" \
  || fail "native and wasm differ (diff $out/native.out $out/wasm.out)"
peeks=$(sed -n 's/^step [0-9]* peek \([0-9]*\) .*/\1/p' "$out/native.out" \
  | paste -sd, - | sed 's/,/, /g')
[ "[$peeks]" = "$(cat "$out/main.out")" ] \
  || fail "the peeks [$peeks] differ from main's $(cat "$out/main.out")"

misuse() {
  "$@" --misuse > /dev/null 2> "$out/misuse.err"
  code=$?
  grep -q '^bend: peek: a handle that was consumed, disposed or never made' \
    "$out/misuse.err" && [ "$code" = 1 ] \
    || fail "$1: a disposed handle gave exit $code: $(head -n 1 "$out/misuse.err")"
}
misuse "$out/drive"
misuse "$node" "$here/drive.mjs" "$out/counter.mjs"

rm -rf "$out/tmp"
[ "$status" = 0 ] && echo "ok: peeks equal (native, wasm, main); misuse fails on both"
exit $status
