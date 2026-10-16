#!/bin/sh
# Conformance and failure tests of the wasm glue (glue/README.md), in the
# SDK's Node. Builds Robokill's step.bend (replay/robokill/, vendored from
# Robokill 63031ab) four ways into glue/out/ (ignored):
#
# - the JS lane, `scripts/bend step.bend -o step.mjs`;
# - the wasm lane, Node-capable, `glue/build.sh --node step.bend
#   init,input_at,step,hash,render`;
# - the shipped build of the same step.c, `glue/build.sh step.c web step`,
#   into glue/out/web/;
# - a trap module: the same C with BEND_LIB_SLOTS 4 and glue/test/trap.c
#   appended, for the failure test;
#
# and the native reference `scripts/bend replay.bend -o ref.bin`. Checks,
# stopping at the first that fails:
#
# - glue/test/replay.mjs prints the same lines through the JS lane and the
#   wasm glue (22 checkpoints and the render hash of all 20,000 frames);
# - its checkpoint lines equal replay.bend's, and the final hashes are
#   Robokill's (spike/RESULTS.md): 603820250 and 819172968;
# - glue/test/failure.mjs: misuse, trap, poisoning and reset;
# - glue/test/shipped.sh: the shipped build names no Node API and its
#   wasm is the tested one, byte for byte.
#
# Exit status: 0 when every check holds.
set -u
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
out=glue/out
rk=replay/robokill
sdk=${BEND_WASM_EMSDK:-$HOME/.cache/bend-wasm/emsdk-6.0.10}
node=$(find "$sdk/node" -path '*/bin/node' -type f 2>/dev/null | head -n 1)
if [ -z "$node" ]; then
  echo "glue/test/run.sh: no node in $sdk/node" >&2
  exit 1
fi

rm -rf "$out"
mkdir -p "$out/tmp"
export TMPDIR="$root/$out/tmp"

die() {
  echo "FAILED: $*"
  exit 1
}

step() {
  log=$out/$1.log
  shift
  if ! "$@" > "$log" 2>&1; then
    echo "glue/test/run.sh: $* failed:" >&2
    tail -n 20 "$log" >&2
    exit 1
  fi
}

step js scripts/bend "$rk/step.bend" -o "$out/step.mjs"
sh glue/build.sh --node "$rk/step.bend" init,input_at,step,hash,render \
  "$out" step || die "glue/build.sh step"
sh glue/build.sh "$out/step.c" "$out/web" step || die "glue/build.sh web step"
{ echo "#define BEND_LIB_SLOTS 4"; cat "$out/step.c" glue/test/trap.c; } \
  > "$out/trap-src.c"
sh glue/build.sh --node "$out/trap-src.c" "$out" trap \
  || die "glue/build.sh trap"
step ref scripts/bend "$rk/replay.bend" -o "$out/ref.bin"

"$out/ref.bin" > "$out/ref.out" || die "ref.bin exited $?"
for lane in step step.wasm; do
  "$node" glue/test/replay.mjs "$out/$lane.mjs" > "$out/$lane.out" \
    2> "$out/$lane.err" || { tail -n 5 "$out/$lane.err"; die "replay $lane"; }
done
if ! cmp -s "$out/step.out" "$out/step.wasm.out"; then
  cmp "$out/step.out" "$out/step.wasm.out"
  die "the JS lane and the wasm glue print different lines"
fi
grep -v '^render ' "$out/step.wasm.out" > "$out/points"
cmp -s "$out/ref.out" "$out/points" \
  || die "checkpoints differ from replay.bend (diff $out/ref.out $out/points)"
grep -qx 'n=500 frame=10000 hash=603820250' "$out/points" \
  && grep -qx 'n=2000 frame=10000 hash=819172968' "$out/points" \
  || die "final hashes differ from Robokill's RESULTS.md"
echo "ok: the JS lane and the wasm glue print the same" \
  "$(wc -l < "$out/step.out" | tr -d ' ') lines; the" \
  "$(wc -l < "$out/points" | tr -d ' ') checkpoints equal replay.bend's," \
  "final hashes as RESULTS.md"

"$node" glue/test/failure.mjs "$out/step.wasm.mjs" "$out/trap.wasm.mjs" \
  || die "glue/test/failure.mjs"
sh glue/test/shipped.sh "$out/web" "$out" step || die "glue/test/shipped.sh"
rm -rf "$out/tmp"
echo "ok: glue conformance and failure tests"
