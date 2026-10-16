#!/bin/sh
# Negative checks (tests/negative/README.md): each case runs one of the
# repository's checks against a known-bad build or setup and expects it to
# FAIL, for the named reason (its message is matched). The mutants are
# patch files here, appended to the real series only for this run through
# scripts/bend's BEND_PATCH_EXTRA; the patches/ series is never touched.
#
# Output: tests/negative/out/ (ignored), one log per case. Exit status: 0
# only when the good build passes and every case failed as expected.
set -u
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
here=tests/negative
out=$here/out
sdk=${BEND_WASM_EMSDK:-$HOME/.cache/bend-wasm/emsdk-6.0.10}
node=$(find "$sdk/node" -path '*/bin/node' -type f 2>/dev/null | head -n 1)
if [ -z "$node" ]; then
  echo "tests/negative/run.sh: no node in $sdk/node" >&2
  exit 1
fi
cc=${CC:-clang}
rm -rf "$out"
mkdir -p "$out/tmp"
status=0
ok() {
  echo "ok: $*"
}
bad() {
  echo "NOT CAUGHT: $*"
  status=1
}

# expect_fail NAME CMD...: runs CMD into $out/NAME.log and requires a
# non-zero exit.
expect_fail() {
  name=$1
  shift
  "$@" > "$out/$name.log" 2>&1
  code=$?
  if [ "$code" = 0 ]; then
    bad "$name: the check passed (log $out/$name.log)"
    return 1
  fi
}

# Baseline: probe/lib passes on the real series, so the failures below come
# from the mutants. Its library build also serves case 2's consumed-handle
# drivers.
if sh probe/lib/run.sh > "$out/baseline.log" 2>&1; then
  ok "baseline: probe/lib/run.sh passes on the real series"
else
  echo "tests/negative/run.sh: probe/lib/run.sh fails on the real series:" >&2
  tail -n 20 "$out/baseline.log" >&2
  exit 1
fi
cp probe/lib/out/counter.c probe/lib/out/counter.mjs probe/lib/out/counter.wasm \
  "$out/"

# 1. Leak: library mode leaks a task node per call. Natively probe/lib's
# heap bound must report the high-water growing. In wasm the default
# corpus (patch 0002) may fill first: either the growth message or the
# runtime's out-of-memory error (ERR_HEAP) is detection. With ERR_HEAP the
# wasm drivers (the run and the misuse run) exit 1 with that error, so
# their output differs from native's; nothing else may fail.
if expect_fail leak env BEND_PATCH_EXTRA=$here/leak.patch sh probe/lib/run.sh
then
  log=$out/leak.log
  native=$(grep -c '^FAILED: native: the heap high-water grew' "$log")
  grown=$(grep -c '^FAILED: wasm: the heap high-water grew' "$log")
  oom=$(grep -c '^bend: out of memory: ' "$log")
  exited=$(grep -c '^FAILED: wasm driver exited 1$' "$log")
  others=$(grep '^FAILED: ' "$log" | grep -v \
    -e '^FAILED: native: the heap high-water grew' \
    -e '^FAILED: wasm: the heap high-water grew' \
    -e '^FAILED: wasm driver exited 1$' \
    -e '^FAILED: native and wasm differ ' \
    -e '/node: a disposed handle gave exit 1: bend: out of memory: ' \
    | grep -c .)
  if [ "$native" = 1 ] && [ "$grown" = 1 ] && [ "$oom" = 0 ] \
    && [ "$exited" = 0 ] && [ "$others" = 0 ]; then
    ok "leak: probe/lib/run.sh fails on the heap bound, native and wasm"
  elif [ "$native" = 1 ] && [ "$grown" = 0 ] && [ "$oom" -ge 1 ] \
    && [ "$exited" = 1 ] && [ "$others" = 0 ]; then
    ok "leak: probe/lib/run.sh fails on the heap bound (native) and" \
      "out of memory (wasm)"
  else
    bad "leak: probe/lib/run.sh failed for another reason (log $log)"
  fi
fi

# 2. Stale handle. On the real series a handle that step consumed ends in
# the library's error, natively and in wasm (the Emscripten build and the
# plain-clang one, the latter through tools/clang-wasm/node.mjs's factory,
# so the same consumed.mjs drives both); with the generation check
# removed, probe/lib's disposed-handle check must fail on both.
if ! TMPDIR="$root/$out/tmp" "$cc" -std=c11 -O3 "$out/counter.c" \
  "$here/consumed.c" -lpthread -lm -o "$out/consumed" > "$out/consumed.build.log" 2>&1
then
  bad "stale: consumed.c does not build (log $out/consumed.build.log)"
fi
consumed() {
  lane=$1
  shift
  # The hang guard of probe/lib/run.sh's timed, for the same drivers.
  scripts/guard "$@" > "$out/consumed.$lane.out" 2> "$out/consumed.$lane.err"
  code=$?
  if [ "$code" = 1 ] && grep -q \
    '^bend: peek: a handle that was consumed, disposed or never made' \
    "$out/consumed.$lane.err"; then
    ok "stale: a consumed handle fails with exit 1 and the handle message ($lane)"
  else
    t=
    [ "$code" = 152 ] && t=", timeout (stopped by the hang guard)"
    bad "stale: a consumed handle gave exit $code$t ($lane):" \
      "$(head -n 1 "$out/consumed.$lane.err")"
  fi
}
consumed native "$out/consumed"
consumed wasm "$node" "$here/consumed.mjs" "$out/counter.mjs"
if sh tools/clang-wasm/build.sh "$out/counter.c" "$out/clang" counter \
  > "$out/consumed.clang.build.log" 2>&1 \
  && "$node" tools/clang-wasm/node.mjs factory "$out/clang/counter.wasm" \
    > "$out/counter-clang.mjs"
then
  consumed clang-wasm "$node" "$here/consumed.mjs" "$out/counter-clang.mjs"
else
  bad "stale: the plain-clang counter does not build" \
    "(log $out/consumed.clang.build.log)"
fi
if expect_fail stale env BEND_PATCH_EXTRA=$here/stale-handle.patch \
  sh probe/lib/run.sh
then
  n=$(grep -c '^FAILED: .*: a disposed handle gave exit' "$out/stale.log")
  others=$(grep '^FAILED: ' "$out/stale.log" | grep -vc 'a disposed handle')
  if [ "$n" = 2 ] && [ "$others" = 0 ]; then
    ok "stale: probe/lib/run.sh fails on the disposed handle, native and wasm"
  else
    bad "stale: probe/lib/run.sh failed for another reason (log $out/stale.log)"
  fi
fi

# 3. Env ABI: patch 0002's two-word Env passing reverted; each wasm lane of
# the differential run (Emscripten's, and the plain-clang build, which takes
# the same __EMSCRIPTEN__ path under patch 0004's guard) must report
# exactly the programs it breaks there: the three patch 0002 fixed, and on
# the plain-clang build also run_insertion_sort. A segment then reads Env
# from a frame the tail call freed, so which programs go wrong depends on
# what the code writes over that frame, which differs between the builds
# (emcc also optimizes with wasm-opt); both builds are reproducible.
if expect_fail env-abi env BEND_PATCH_EXTRA=$here/env-abi.patch \
  LANES="wasm clang-wasm" DIFFERENTIAL_OUT=$out/env-abi \
  sh tests/differential/run.sh
then
  for lane in wasm clang-wasm; do
    case $lane in
      wasm) want='reg_nat_chain run_bst_insert run_string_algorithms' ;;
      clang-wasm) want='reg_nat_chain run_bst_insert run_insertion_sort run_string_algorithms' ;;
    esac
    got=$(sed -En "s/^([^ ]*) $lane: (DIFFERS|FAILED).*/\\1/p" \
      "$out/env-abi.log" | sort | paste -sd' ' -)
    if [ "$got" = "$want" ]; then
      ok "env-abi: the $lane lane reports $want"
    else
      bad "env-abi: the $lane lane reports '$got', want '$want'" \
        "(log $out/env-abi.log)"
    fi
  done
fi

# 4. Missing lane: under BEND_PATCH=0 the wasm lanes cannot be built, and
# a run that expects them must fail at once, naming both.
if expect_fail missing-lane env BEND_PATCH=0 \
  DIFFERENTIAL_OUT=$out/missing-lane sh tests/differential/run.sh
then
  if grep -q '^wasm: FAILED, not available' "$out/missing-lane.log" \
    && grep -q '^clang-wasm: FAILED, not available' "$out/missing-lane.log"
  then
    ok "missing-lane: the differential run fails without the wasm lanes"
  else
    bad "missing-lane: the run failed for another reason" \
      "(log $out/missing-lane.log)"
  fi
fi

rm -rf "$out/tmp"
[ "$status" = 0 ] && echo "ok: every negative case failed as expected"
exit $status
