#!/bin/sh
# Differential test of Bend's backends (docs/plan.md, "Correctness and value
# checks"): every program in tests/differential/corpus.txt is built and run
# on each lane, and each lane's stdout and exit code must match the native
# lane's byte for byte. The lanes build a program the way Bend's own test
# gate does (vendor/bend/gates/test.ts): `bend t.bend -o t` (clang) and run
# `./t`; `bend t.bend -o t.js` and run `bun t.js`. The wasm lane builds
# `bend t.bend -o t.c` with scripts/emcc and scripts/wasm-flags and runs
# the result with the Emscripten SDK's Node.
#
# Output: tests/differential/out/ (ignored; DIFFERENTIAL_OUT, a path
# relative to the repository root, overrides it, so tests/negative's runs
# do not clear a run beside them), per program and lane the build log,
# stdout, stderr and exit code, and summary.txt.
# Exit status: 0 when every program in the corpus matched native on every
# lane in LANES. A lane in LANES that cannot be built here (wasm under
# BEND_PATCH=0) fails the run at once; LANES=js is the explicit opt-out for
# a pin-only run.
set -u
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
here=tests/differential
out=${DIFFERENTIAL_OUT:-$here/out}
# The lanes compared with native, in order (LANES overrides the list). A
# lane is one more name here and its lane_build_<name> and lane_run_<name>
# functions below.
lanes=${LANES:-js wasm}

# Same Bun as scripts/bend, which checks its version on every build.
bun=${BEND_BUN:-$(command -v bun || true)}
# Bend's gate runs JS programs with this stack limit (gates/test.ts).
export BUN_JSC_maxPerThreadStackUsage=33554432
# clang's and Bend's temporary files stay in the output directory.
export TMPDIR="$root/$out/tmp"
# Node of the pinned Emscripten SDK, found as probe/run.sh finds it.
sdk=${BEND_WASM_EMSDK:-$HOME/.cache/bend-wasm/emsdk-6.0.10}
node=$(find "$sdk/node" -path '*/bin/node' -type f 2>/dev/null | head -n 1)
if [ -z "$bun" ]; then
  echo "tests/differential/run.sh: bun not found (set BEND_BUN)" >&2
  exit 1
fi

rm -rf "$out"
mkdir -p "$out/tmp"
summary=$out/summary.txt
scripts/bend --toolchain > "$summary" 2>&1 || {
  cat "$summary" >&2
  exit 1
}
echo >> "$summary"

say() {
  echo "$*" | tee -a "$summary"
}

# timed CMD...: runs CMD with the hang guard, scripts/guard (5 s of CPU
# time, as Bend's own gate for the same non-`!` test programs,
# vendor/bend/gates/test.ts:136). A program killed by the guard exits 152
# (SIGXCPU) and counts as FAILED with "timeout".
timed() {
  scripts/guard "$@"
}

# lane_build_<lane> SRC BASE: builds SRC into BASE.<lane files>.
# lane_run_<lane> BASE: runs the build, stdout and stderr as given.
lane_build_native() {
  scripts/bend "$1" -o "$2.bin"
}
lane_run_native() {
  timed "$1.bin"
}
lane_build_js() {
  scripts/bend "$1" -o "$2.js"
}
lane_run_js() {
  timed "$bun" "$1.js"
}
# The wasm target needs patches 0001 and 0002 (docs/probe.md): under
# BEND_PATCH=0 the lane is not available, and the run needs LANES=js.
if [ "${BEND_PATCH:-1}" != 0 ]; then
  lane_build_wasm() {
    if [ -z "$node" ]; then
      echo "no node in $sdk/node (the pinned Emscripten SDK, docs/workflow.md)"
      return 1
    fi
    scripts/bend "$1" -o "$2.c" || return 1
    # shellcheck disable=SC2046 # the flags are words on purpose
    scripts/emcc $(scripts/wasm-flags) "$2.c" -o "$2.js"
  }
  lane_run_wasm() {
    timed "$node" "$1.js"
  }
fi

for lane in $lanes; do
  if ! type "lane_build_$lane" > /dev/null 2>&1; then
    say "$lane: FAILED, not available (BEND_PATCH=${BEND_PATCH:-1});" \
      "set LANES to the lanes this run should compare, e.g. LANES=js"
    exit 1
  fi
done

# run_lane LANE SRC BASE: builds and runs SRC on LANE into BASE.LANE.*;
# prints "" when it ran, else the reason it did not.
run_lane() {
  b=$3.$1
  if ! lane_build_"$1" "$2" "$b" > "$b.build.log" 2>&1; then
    echo "build failed: $(head -n 1 "$b.build.log")"
    return
  fi
  lane_run_"$1" "$b" > "$b.out" 2> "$b.err"
  code=$?
  echo $code > "$b.code"
  if [ "$code" = 152 ]; then
    echo "timeout (stopped by the hang guard, exit 152)"
  fi
}

status=0
programs=0
while read -r src rest; do
  case $src in '' | '#'*) continue ;; esac
  programs=$((programs + 1))
  if [ ! -f "$src" ]; then
    say "$src: FAILED, no such file"
    status=1
    continue
  fi
  p=$(echo "$src" | sed 's|^vendor/bend/tests/||; s|\.bend$||; s|/|_|g')
  base=$out/$p
  why=$(run_lane native "$src" "$base")
  if [ -n "$why" ]; then
    say "$p native: FAILED, $why"
    status=1
    continue
  fi
  say "$p native: ran, exit $(cat "$base.native.code")"
  for lane in $lanes; do
    why=$(run_lane "$lane" "$src" "$base")
    if [ -n "$why" ]; then
      say "$p $lane: FAILED, $why"
      status=1
    elif ! cmp -s "$base.$lane.out" "$base.native.out"; then
      say "$p $lane: DIFFERS, stdout (diff $base.native.out $base.$lane.out)"
      status=1
    elif ! cmp -s "$base.$lane.code" "$base.native.code"; then
      say "$p $lane: DIFFERS, exit $(cat "$base.$lane.code"), native" \
        "$(cat "$base.native.code")"
      status=1
    else
      say "$p $lane: ok"
    fi
  done
done < "$here/corpus.txt"

say ""
say "programs: $programs; ok: $(grep -c ': ok$' "$summary")," \
  "DIFFERS: $(grep -c ': DIFFERS' "$summary")," \
  "FAILED: $(grep -c ': FAILED' "$summary"); lanes: native $lanes"
rm -rf "$out/tmp"
exit $status
