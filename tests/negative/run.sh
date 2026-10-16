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

# 1. Leak: library mode leaks a task node per call; probe/lib's heap bound
# must report the high-water growing, natively and in wasm, and nothing
# else.
if expect_fail leak env BEND_PATCH_EXTRA=$here/leak.patch sh probe/lib/run.sh
then
  grown=$(grep -Ec '^FAILED: (native|wasm): the heap high-water grew' \
    "$out/leak.log")
  others=$(grep '^FAILED: ' "$out/leak.log" | grep -vc 'heap high-water grew')
  if [ "$grown" = 2 ] && [ "$others" = 0 ]; then
    ok "leak: probe/lib/run.sh fails on the heap bound, native and wasm"
  else
    bad "leak: probe/lib/run.sh failed for another reason (log $out/leak.log)"
  fi
fi

# 2. Stale handle. On the real series a handle that step consumed ends in
# the library's error, natively and in wasm; with the generation check
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
  perl -e 'alarm 5; exec @ARGV or exit 127' "$@" > "$out/consumed.$lane.out" 2> "$out/consumed.$lane.err"
  code=$?
  if [ "$code" = 1 ] && grep -q \
    '^bend: peek: a handle that was consumed, disposed or never made' \
    "$out/consumed.$lane.err"; then
    ok "stale: a consumed handle fails with exit 1 and the handle message ($lane)"
  else
    bad "stale: a consumed handle gave exit $code ($lane):" \
      "$(head -n 1 "$out/consumed.$lane.err")"
  fi
}
consumed native "$out/consumed"
consumed wasm "$node" "$here/consumed.mjs" "$out/counter.mjs"
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

# 3. Env ABI: patch 0002's two-word Env passing reverted; the wasm lane of
# the differential run must report exactly the three programs it fixed.
want='reg_nat_chain run_bst_insert run_string_algorithms'
if expect_fail env-abi env BEND_PATCH_EXTRA=$here/env-abi.patch LANES=wasm \
  sh tests/differential/run.sh
then
  got=$(sed -En 's/^([^ ]*) wasm: (DIFFERS|FAILED).*/\1/p' \
    "$out/env-abi.log" | sort | paste -sd' ' -)
  if [ "$got" = "$want" ]; then
    ok "env-abi: the wasm lane reports $want"
  else
    bad "env-abi: the wasm lane reports '$got', want '$want'" \
      "(log $out/env-abi.log)"
  fi
fi

# 4. Missing lane: under BEND_PATCH=0 the wasm lane cannot be built, and a
# run that expects it must fail at once.
if expect_fail missing-lane env BEND_PATCH=0 sh tests/differential/run.sh
then
  if grep -q '^wasm: FAILED, not available' "$out/missing-lane.log"; then
    ok "missing-lane: the differential run fails without the wasm lane"
  else
    bad "missing-lane: the run failed for another reason" \
      "(log $out/missing-lane.log)"
  fi
fi

rm -rf "$out/tmp"
[ "$status" = 0 ] && echo "ok: every negative case failed as expected"
exit $status
