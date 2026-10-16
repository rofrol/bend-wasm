#!/bin/sh
# Robokill's headless replay through library mode (replay/robokill/README.md,
# TODO t-byai25qu). Builds step.bend with `--lib init,input_at,step,hash,render`
# once, links that C natively (replay.c) and to wasm (replay.mjs under the
# SDK's Node, scripts/wasm-flags), and builds the vendored replay.bend
# natively as the reference. Checks, stopping at the first that fails:
#
# - the checkpoint lines (state hash at frames 0, 1,000, ..., 10,000 for
#   n = 500 and 2,000) are equal for replay.bend, the native driver and
#   the wasm driver;
# - the final hashes are Robokill's (spike/RESULTS.md at 63031ab):
#   603820250 for n = 500, 819172968 for n = 2,000;
# - the render hash (FNV-1a of the F32 region after every frame's render)
#   is equal natively and in wasm on every frame;
# - the heap bound, n = 500, step + render + hash for BOUND_FRAMES frames
#   (default "100000 1000000"), natively and in wasm (BOUND_WASM, default
#   the same list): at the last checkpoint the allocator's high-water mark
#   and the live handle count are no higher than at the first (frame
#   FRAMES/10, after warm-up).
# On a difference it prints the first differing frame and both values.
# Wall times of each run are printed with its summary.
#
# Output: replay/robokill/out/ (ignored). Exit status: 0 when every check
# holds.
set -u
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
here=replay/robokill
out=$here/out
sdk=${BEND_WASM_EMSDK:-$HOME/.cache/bend-wasm/emsdk-6.0.10}
node=$(find "$sdk/node" -path '*/bin/node' -type f 2>/dev/null | head -n 1)
if [ -z "$node" ]; then
  echo "replay/robokill/run.sh: no node in $sdk/node" >&2
  exit 1
fi
cc=${CC:-clang}
frames_list=${BOUND_FRAMES:-100000 1000000}
wasm_list=${BOUND_WASM-$frames_list}
exports=_bend_init,_bend_heap_words,_bend_handles,_bend_f32,_bend_f32_len
exports=$exports,_bend_def_init,_bend_def_input_at,_bend_def_step
exports=$exports,_bend_def_hash,_bend_def_render,_malloc

rm -rf "$out"
mkdir -p "$out/tmp"
# clang's and Bend's temporary files stay in the output directory.
export TMPDIR="$root/$out/tmp"

die() {
  echo "FAILED: $*"
  exit 1
}

step() {
  log=$out/$1.log
  shift
  if ! "$@" > "$log" 2>&1; then
    echo "replay/robokill/run.sh: $* failed:" >&2
    tail -n 20 "$log" >&2
    exit 1
  fi
}

now() {
  perl -MTime::HiRes=time -e 'printf "%.2f\n", time'
}

# timed NAME CMD...: runs CMD with stdout to out/NAME.out; prints its wall
# time; a failing run stops the script.
timed() {
  name=$1
  shift
  t0=$(now)
  "$@" > "$out/$name.out" 2> "$out/$name.err"
  code=$?
  if [ "$code" != 0 ]; then
    tail -n 5 "$out/$name.err"
    die "$name exited $code"
  fi
  echo "$name: $(awk -v a="$t0" -v b="$(now)" 'BEGIN { printf "%.2f", b - a }') s"
}

# same WHAT A B: the lines of files A and B are equal; otherwise prints the
# first line that differs (its n and frame, and both hashes) and stops.
same() {
  awk -v what="$1" -v a="$2" -v b="$3" '
    function key(l) { sub(/ hash=.*/, "", l); return l }
    function val(l) { return sub(/.* hash=/, "", l) ? l : "(none)" }
    { if ((getline o < b) <= 0) o = ""
      if ($0 != o) { bad = 1; exit } }
    END {
      if (!bad && (getline o < b) > 0) { $0 = ""; bad = 1 }
      if (bad) {
        printf "first difference (%s) at %s: %s %s, %s %s\n", what,
          key($0 != "" ? $0 : o), a, val($0), b, val(o)
        exit 1
      }
    }' "$2" || die "$1 differ"
}

step lib scripts/bend "$here/step.bend" -o "$out/step.c" \
  --lib init,input_at,step,hash,render
step ref scripts/bend "$here/replay.bend" -o "$out/ref.bin"
step native "$cc" -std=c11 -O3 "$out/step.c" "$here/replay.c" -lpthread \
  -lm -o "$out/replay"
# shellcheck disable=SC2046 # the flags are words on purpose
step wasm scripts/emcc $(scripts/wasm-flags) -sMODULARIZE -sEXPORT_ES6 \
  -sEXPORTED_FUNCTIONS=$exports -sEXPORTED_RUNTIME_METHODS=HEAPU8,HEAPU32 \
  "$out/step.c" -o "$out/step.mjs"

timed ref "$out/ref.bin"
timed native "$out/replay"
timed wasm "$node" "$here/replay.mjs" "$out/step.mjs"

for lane in native wasm; do
  grep '^n=' "$out/$lane.out" > "$out/$lane.points"
  grep '^render ' "$out/$lane.out" > "$out/$lane.render"
done
cp "$out/ref.out" "$out/ref.points"
same "checkpoints, replay.bend vs native" "$out/ref.points" "$out/native.points"
same "checkpoints, native vs wasm" "$out/native.points" "$out/wasm.points"
grep -qx 'n=500 frame=10000 hash=603820250' "$out/ref.points" \
  && grep -qx 'n=2000 frame=10000 hash=819172968' "$out/ref.points" \
  || die "final hashes differ from Robokill's RESULTS.md:" \
    "$(grep 'frame=10000' "$out/ref.points" | paste -sd, -)"
same "render hashes, native vs wasm" "$out/native.render" "$out/wasm.render"
echo "ok: $(wc -l < "$out/ref.points" | tr -d ' ') checkpoints equal" \
  "(replay.bend, native, wasm), final hashes as RESULTS.md, render hashes" \
  "equal on $(wc -l < "$out/native.render" | tr -d ' ') frames"

# bound NAME: the high-water and handle check on out/NAME.out.
bound() {
  first=$(grep '^bound ' "$out/$1.out" | head -n 1)
  last=$(grep '^bound ' "$out/$1.out" | tail -n 1)
  cat "$out/$1.out"
  num() { echo "$1" | sed -n "s/.* $2=\([0-9]*\).*/\1/p"; }
  for k in heap handles; do
    a=$(num "$first" $k)
    z=$(num "$last" $k)
    [ -n "$a" ] && [ -n "$z" ] && [ "$z" -le "$a" ] \
      || die "$1: $k grew from ${a:-?} at the first checkpoint to ${z:-?}" \
        "at the last"
  done
}
for f in $frames_list; do
  timed "bound-native-$f" "$out/replay" bound "$f"
  bound "bound-native-$f"
done
for f in $wasm_list; do
  timed "bound-wasm-$f" "$node" "$here/replay.mjs" "$out/step.mjs" bound "$f"
  bound "bound-wasm-$f"
done

rm -rf "$out/tmp"
echo "ok: replay equal on all lanes; heap and handles flat over" \
  "$frames_list frames (native) and ${wasm_list:-no} frames (wasm)"
