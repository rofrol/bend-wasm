#!/bin/sh
# Rebuilds the Emscripten probe of Bend's generated C from scratch
# (docs/probe.md). For each program in probe/*.bend it records the native
# reference (the clang binary of `scripts/bend P -o P.bin`, run with
# `--threads 1`, as wasm runs one worker), emits C with `scripts/bend -o`,
# and tries every build variant below with `scripts/emcc` and build flags
# only: the generated C is never edited and no header is added. Each
# program stops at its first failing step (emitting the C, or the native
# reference); each variant stops at its first failing step (build, run
# under Node, comparison with its expected result).
#
# Variants and their expected results:
#
# - w32, w32-tc-grow, w64, w64-pthread (run) and w64-web (build only)
#   document the original probe, so they build the C of the unpatched pin
#   (BEND_PATCH=0). Expected, as the probe found: the program does not
#   run. A run stops before any Bend code with exit 1, no stdout and
#   `bend: reservation failed` or `RuntimeError: memory access out of
#   bounds`; a build fails only on an undeclared libc function (the
#   random and process effects, which patch 0002 makes compile); w64-web
#   otherwise builds.
# - w32-patched, the target, builds the C of the patch series with
#   scripts/wasm-flags. Expected: stdout and exit 0 equal to native, or,
#   for a program with a line `# probe-expect: <stderr line>`, exit 1 with
#   that stderr line (its native run is recorded whatever it does). A line
#   `# probe-cflags: <flags>` adds flags to every wasm build of the program.
#
# Drivers: a probe/*.c with a line `// probe-include: P` includes P's
# emitted series C (as PROBE_C) and is built natively with clang and with
# scripts/wasm-flags; both must print the same stdout and end as its
# `// probe-expect:` line says (exit 1 with that stderr line), or exit 0.
#
# Output: probe/out/ (ignored), one log per step, and summary.txt.
# Exit status: 0 when every variant of every program and every driver
# gave its expected result.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
out=probe/out
cc=${CC:-clang}
sdk=${BEND_WASM_EMSDK:-$HOME/.cache/bend-wasm/emsdk-6.0.10}
node=$(find "$sdk/node" -path '*/bin/node' -type f | head -n 1)
if [ -z "$node" ]; then
  echo "probe/run.sh: no node in $sdk/node" >&2
  exit 1
fi

# name|C|flags|run: C is "pin" or "series"; run is "node" (run and check)
# or "build" (build only).
variants='w32|pin|-std=c11 -O2|node
w32-tc-grow|pin|-std=c11 -O2 -mtail-call -sALLOW_MEMORY_GROWTH -sMAXIMUM_MEMORY=4GB|node
w64|pin|-std=c11 -O2 -m64 -mtail-call -sALLOW_MEMORY_GROWTH -sMAXIMUM_MEMORY=16GB|node
w64-pthread|pin|-std=c11 -O2 -m64 -mtail-call -pthread -sALLOW_MEMORY_GROWTH -sMAXIMUM_MEMORY=16GB|node
w64-web|pin|-std=c11 -O2 -m64 -mtail-call -sALLOW_MEMORY_GROWTH -sMAXIMUM_MEMORY=16GB -sENVIRONMENT=web|build
w32-patched|series|'"$(scripts/wasm-flags)"'|node'
# w32-patched is the target of patch 0002; scripts/wasm-flags defines its
# flags and says how its memory is sized.

rm -rf "$out"
mkdir -p "$out/tmp"
# clang's and Bend's temporary files stay in the output directory.
export TMPDIR="$root/$out/tmp"
summary=$out/summary.txt
{
  scripts/bend --toolchain
  echo "pin: $(BEND_PATCH=0 scripts/bend --toolchain | sed -n 2p)"
  echo "node $("$node" --version)"
  echo
} > "$summary"

say() {
  echo "$*" | tee -a "$summary"
}

# why FILE: the line of a run's stderr that says why it stopped (a wasm
# trap's first stderr line is only its location).
why() {
  grep -m 1 -E 'Error|^bend:|^Aborted' "$1" || head -n 1 "$1"
}

# pin P V BASE RUN: the expected result of the pin's variant V.
pin() {
  if [ ! -f "$3.js" ]; then
    if grep -q 'call to undeclared function' "$3.build.log"; then
      say "$1 $2 (pin): build fails as expected:" \
        "$(grep -m 1 -o "undeclared function '[a-z_]*'" "$3.build.log")"
    else
      say "$1 $2 (pin): build FAILED, UNEXPECTED: $(head -n 1 "$3.build.log")"
    fi
    return
  fi
  if [ "$4" = build ]; then
    say "$1 $2 (pin): builds, as expected (build only)"
    return
  fi
  "$node" "$3.js" > "$3.out" 2> "$3.err"
  code=$?
  if [ "$code" = 1 ] && [ ! -s "$3.out" ] \
    && grep -q -e '^bend: reservation failed$' \
      -e 'RuntimeError: memory access out of bounds' "$3.err"; then
    say "$1 $2 (pin): does not run, as expected, exit 1: $(why "$3.err")"
  else
    say "$1 $2 (pin): UNEXPECTED, exit $code: $(why "$3.err")"
  fi
}

# series P V BASE EXPECT: the expected result of the series' variant V.
series() {
  if [ ! -f "$3.js" ]; then
    say "$1 $2: build FAILED: $(grep -m 1 error "$3.build.log")"
    return
  fi
  "$node" "$3.js" > "$3.out" 2> "$3.err"
  code=$?
  if [ -n "$4" ]; then
    if [ "$code" = 1 ] && grep -qxF "$4" "$3.err"; then
      say "$1 $2: run fails as expected, exit 1: $4"
    else
      say "$1 $2: run FAILED, not the expected error, exit $code:" \
        "$(why "$3.err")"
    fi
  elif [ "$code" != 0 ]; then
    say "$1 $2: run FAILED, exit $code: $(why "$3.err")"
  elif cmp -s "$3.out" "$out/$1.native.out"; then
    say "$1 $2: run ok, output matches native"
  else
    say "$1 $2: run ok, output DIFFERS from native"
  fi
}

for src in probe/*.bend; do
  p=$(basename "$src" .bend)
  expect=$(sed -n 's/^# probe-expect: //p' "$src")
  cflags=$(sed -n 's/^# probe-cflags: //p' "$src")
  if ! scripts/bend "$src" -o "$out/$p.native.bin" > "$out/$p.native.build.log" 2>&1; then
    say "$p: scripts/bend -o $p.native.bin failed; stop"
    continue
  fi
  "$out/$p.native.bin" --threads 1 > "$out/$p.native.out" 2> "$out/$p.native.err"
  echo $? > "$out/$p.native.code"
  if [ -n "$expect" ]; then
    say "$p: native exit $(cat "$out/$p.native.code"):" \
      "$(head -n 1 "$out/$p.native.out") $(head -n 1 "$out/$p.native.err")"
  elif [ "$(cat "$out/$p.native.code")" != 0 ]; then
    say "$p: native run FAILED (exit $(cat "$out/$p.native.code")); stop"
    continue
  fi
  if ! scripts/bend "$src" -o "$out/$p.c" > "$out/$p.emit.log" 2>&1 \
    || ! BEND_PATCH=0 scripts/bend "$src" -o "$out/$p.pin.c" \
      > "$out/$p.pin.emit.log" 2>&1; then
    say "$p: scripts/bend -o $p.c FAILED; stop"
    continue
  fi
  echo "$variants" | while IFS='|' read -r v c flags run; do
    base=$out/$p.$v
    src_c=$out/$p.c
    [ "$c" = pin ] && src_c=$out/$p.pin.c
    # shellcheck disable=SC2086 # flags are words on purpose
    scripts/emcc $flags $cflags "$src_c" -o "$base.js" > "$base.build.log" 2>&1 \
      || rm -f "$base.js"
    if [ "$c" = pin ]; then
      pin "$p" "$v" "$base" "$run"
    else
      series "$p" "$v" "$base" "$expect"
    fi
  done
done

for drv in probe/*.c; do
  d=$(basename "$drv" .c)
  inc=$(sed -n 's|^// probe-include: ||p' "$drv")
  expect=$(sed -n 's|^// probe-expect: ||p' "$drv")
  pc="\"$root/$out/$inc.c\""
  if ! "$cc" -std=c11 -O2 -DPROBE_C="$pc" "$drv" -lpthread -lm \
    -o "$out/$d.drv.bin" > "$out/$d.drv.native.build.log" 2>&1; then
    say "$d (driver of $inc): native build FAILED"
    continue
  fi
  # shellcheck disable=SC2046 # the flags are words on purpose
  if ! scripts/emcc $(scripts/wasm-flags) -DPROBE_C="$pc" "$drv" \
    -o "$out/$d.drv.js" > "$out/$d.drv.wasm.build.log" 2>&1; then
    say "$d (driver of $inc): wasm build FAILED"
    continue
  fi
  "$out/$d.drv.bin" > "$out/$d.drv.native.out" 2> "$out/$d.drv.native.err"
  ncode=$?
  "$node" "$out/$d.drv.js" > "$out/$d.drv.wasm.out" 2> "$out/$d.drv.wasm.err"
  wcode=$?
  want=0
  [ -n "$expect" ] && want=1
  for lane in native wasm; do
    code=$wcode
    [ "$lane" = native ] && code=$ncode
    if [ "$code" != "$want" ] || { [ -n "$expect" ] \
      && ! grep -qxF "$expect" "$out/$d.drv.$lane.err"; }; then
      say "$d (driver of $inc) $lane: FAILED, exit $code:" \
        "$(why "$out/$d.drv.$lane.err")"
    fi
  done
  if cmp -s "$out/$d.drv.native.out" "$out/$d.drv.wasm.out"; then
    say "$d (driver of $inc): native and wasm print the same," \
      "$(tail -n 1 "$out/$d.drv.wasm.out") ${expect:-exit 0}"
  else
    say "$d (driver of $inc): output DIFFERS between native and wasm"
  fi
done

rm -rf "$out/tmp"
# A variant or driver without its expected result fails the probe.
if grep -q -e FAILED -e DIFFERS -e UNEXPECTED "$summary"; then
  exit 1
fi
exit 0
