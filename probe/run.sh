#!/bin/sh
# Rebuilds the Emscripten probe of Bend's generated C from scratch
# (docs/probe.md). For each program in probe/*.bend it records the native
# output, emits C with `scripts/bend -o`, and tries every build variant
# below with `scripts/emcc` and build flags only: the generated C is never
# edited and no header is added. Each program stops at its first failing
# step (emitting the C, or the native reference); each variant stops at its
# first failing step (build, run under Node, comparison with native).
#
# A program with a line `# probe-expect: <stderr line>` must instead fail
# under Node with exit 1 and that stderr line (deep.bend, exhaust.bend):
# its native run is recorded whatever it does, and does not stop it.
#
# Output: probe/out/ (ignored), one log per step, and summary.txt.
# Exit status: 0 when every variant of every program matched native.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
out=probe/out
sdk=${BEND_WASM_EMSDK:-$HOME/.cache/bend-wasm/emsdk-6.0.10}
node=$(find "$sdk/node" -path '*/bin/node' -type f | head -n 1)
if [ -z "$node" ]; then
  echo "probe/run.sh: no node in $sdk/node" >&2
  exit 1
fi

# name|flags|run: run is "node" (run and compare) or "build" (build only).
variants='w32|-std=c11 -O2|node
w32-tc-grow|-std=c11 -O2 -mtail-call -sALLOW_MEMORY_GROWTH -sMAXIMUM_MEMORY=4GB|node
w64|-std=c11 -O2 -m64 -mtail-call -sALLOW_MEMORY_GROWTH -sMAXIMUM_MEMORY=16GB|node
w64-pthread|-std=c11 -O2 -m64 -mtail-call -pthread -sALLOW_MEMORY_GROWTH -sMAXIMUM_MEMORY=16GB|node
w64-web|-std=c11 -O2 -m64 -mtail-call -sALLOW_MEMORY_GROWTH -sMAXIMUM_MEMORY=16GB -sENVIRONMENT=web|build
w32-patched|-std=c11 -O2 -mtail-call -sALLOW_MEMORY_GROWTH=0 -sINITIAL_MEMORY=528MB|node'
# w32-patched is the target of patch 0002: its 528 MB hold the 512 MiB
# corpus and the 8 MiB Term stack (patch 0002's defaults) and 8 MiB for
# the static data, Emscripten's own stack and malloc (520 MB aborts with
# OOM at the stack's mmap).

rm -rf "$out"
mkdir -p "$out"
summary=$out/summary.txt
{
  scripts/bend --toolchain
  echo "node $("$node" --version)"
  echo
} > "$summary"
status=0

say() {
  echo "$*" | tee -a "$summary"
}

for src in probe/*.bend; do
  p=$(basename "$src" .bend)
  expect=$(sed -n 's/^# probe-expect: //p' "$src")
  # Native reference: stdout and exit code of the pinned compiler's binary.
  scripts/bend "$src" > "$out/$p.native.out" 2> "$out/$p.native.err"
  echo $? > "$out/$p.native.code"
  if [ -n "$expect" ]; then
    say "$p: native exit $(cat "$out/$p.native.code"):" \
      "$(head -n 1 "$out/$p.native.out") $(head -n 1 "$out/$p.native.err")"
  elif [ "$(cat "$out/$p.native.code")" != 0 ]; then
    say "$p: native run failed (exit $(cat "$out/$p.native.code")); stop"
    status=1
    continue
  fi
  if ! scripts/bend "$src" -o "$out/$p.c" > "$out/$p.emit.log" 2>&1; then
    say "$p: scripts/bend -o $p.c failed; stop"
    status=1
    continue
  fi
  echo "$variants" | while IFS='|' read -r v flags run; do
    base=$out/$p.$v
    # shellcheck disable=SC2086 # flags are words on purpose
    if ! scripts/emcc $flags "$out/$p.c" -o "$base.js" > "$base.build.log" 2>&1; then
      say "$p $v: build FAILED ($flags)"
      continue
    fi
    if [ "$run" = build ]; then
      say "$p $v: build ok, not run ($flags)"
      continue
    fi
    "$node" "$base.js" > "$base.out" 2> "$base.err"
    code=$?
    # A wasm trap's first stderr line is only its location.
    why=$(grep -m 1 -E 'Error|^bend:|^Aborted' "$base.err" \
      || head -n 1 "$base.err")
    if [ -n "$expect" ]; then
      if [ "$code" = 1 ] && grep -qxF "$expect" "$base.err"; then
        say "$p $v: run fails as expected, exit 1: $expect ($flags)"
      else
        say "$p $v: run FAILED, not the expected error, exit $code: $why" \
          "($flags)"
      fi
      continue
    fi
    if [ "$code" != 0 ]; then
      say "$p $v: run FAILED, exit $code: $why ($flags)"
      continue
    fi
    if cmp -s "$base.out" "$out/$p.native.out"; then
      say "$p $v: run ok, output matches native ($flags)"
    else
      say "$p $v: run ok, output DIFFERS from native ($flags)"
    fi
  done
done

# A variant that did not match native fails the probe.
if grep -q -e FAILED -e DIFFERS -e 'not run' "$summary"; then
  status=1
fi
exit $status
