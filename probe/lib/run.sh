#!/bin/sh
# Persistent-state spike (probe/lib/README.md): builds counter.bend in
# library mode (patch 0003) and runs it from a native C driver (drive.c)
# and from Node on the wasm build (drive.mjs, scripts/wasm-flags). Each
# driver prints its peeks and the heap high-water mark per checkpoint.
# Checks: native and wasm print the same lines; their peeks equal what
# counter.bend's own main prints (built natively, `-o bin`: the JS lane
# takes minutes for 100,000 steps); using a disposed handle fails with
# exit 1 and the handle message on both; the heap high-water mark at the
# last checkpoint (100,000 steps) is no higher than at the first (10,000),
# on both, so a leak of even one term per step fails the run.
#
# Output: probe/lib/out/ (ignored). Exit status: 0 when every check holds.
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

# timed CMD...: runs CMD with the hang guard, scripts/guard (5 s of CPU
# time), as tests/differential/run.sh does. It only stops a run that never
# ends (a corrupted handle can loop forever, tests/negative), which exits
# 152 (SIGXCPU) and fails its check as "timeout". Measured 2026-10-16 on an
# Apple arm64 Mac: the drivers take 0.01 s native and 0.21 s in wasm, so
# 5 s leaves a 20-fold margin.
timed() {
  scripts/guard "$@"
}
# why CODE: " (timeout)" when CODE is the guard's kill, else nothing.
why() {
  [ "$1" = 152 ] && echo " (timeout, stopped by the hang guard)"
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
# The heap bound must show a leak as growth on both lanes. A leak of one
# task node per call (tests/negative's leak mutant) reaches 815,232 words
# at 100,000 steps; the default wasm corpus (1,280 heap pages, patch 0002)
# would stop it with ERR_HEAP before the last checkpoint. So the wasm
# build gets a 16 MiB corpus (15,194 pages, 1,944,832 words); the counter
# itself needs 129 pages.
# shellcheck disable=SC2046 # the flags are words on purpose
step wasm scripts/emcc $(scripts/wasm-flags) -DBEND_CORPUS_BYTES=16777216 \
  -sMODULARIZE -sEXPORT_ES6 \
  -sEXPORTED_FUNCTIONS=$exports "$out/counter.c" -o "$out/counter.mjs"

timed "$out/main.bin" > "$out/main.out" || {
  c=$?
  fail "main exited $c$(why $c)"
}
timed "$out/drive" > "$out/native.out" || {
  c=$?
  fail "native driver exited $c$(why $c)"
}
timed "$node" "$here/drive.mjs" "$out/counter.mjs" > "$out/wasm.out" || {
  c=$?
  fail "wasm driver exited $c$(why $c)"
}

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

# bound NAME: the high-water check on probe/lib/out/NAME.out.
bound() {
  first=$(sed -n 's/^step [0-9]* peek [0-9]* heap \([0-9]*\)$/\1/p' \
    "$out/$1.out" | head -n 1)
  last=$(sed -n 's/^step [0-9]* peek [0-9]* heap \([0-9]*\)$/\1/p' \
    "$out/$1.out" | tail -n 1)
  [ -n "$first" ] && [ "$last" -le "$first" ] \
    || fail "$1: the heap high-water grew from ${first:-?} words at the first" \
      "checkpoint to ${last:-?} at the last"
}
bound native
bound wasm

misuse() {
  timed "$@" --misuse > /dev/null 2> "$out/misuse.err"
  code=$?
  grep -q '^bend: peek: a handle that was consumed, disposed or never made' \
    "$out/misuse.err" && [ "$code" = 1 ] \
    || fail "$1: a disposed handle gave exit $code$(why $code):" \
      "$(head -n 1 "$out/misuse.err")"
}
misuse "$out/drive"
misuse "$node" "$here/drive.mjs" "$out/counter.mjs"

rm -rf "$out/tmp"
[ "$status" = 0 ] && echo "ok: peeks equal (native, wasm, main); heap flat; misuse fails on both"
exit $status
