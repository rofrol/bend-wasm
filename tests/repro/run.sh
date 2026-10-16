#!/bin/sh
# Reproducibility of the emitted C (tests/repro/README.md): the programs
# below are compiled to C twice, each pass by a fresh copy of the patched
# compiler (scripts/bend run from a scratch root, so it builds its own
# .toolchain/ there and the repository's stays untouched) with an empty
# Bun transpiler cache, the second pass in another environment (TZ,
# locale, cwd, TMPDIR). The two outputs of every program must be byte
# identical; the first one that differs is named.
#
# Output: a scratch directory from mktemp, removed at the end. Exit status:
# 0 only when every program compiled in both passes to the same bytes.
set -u
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"

# PROGRAM [scripts/bend arguments after -o]: a handful of the differential
# corpus (tests/differential/corpus.txt) covering numbers, floats, ADTs,
# closures, strings, fibers and a foreign effect, plus the Robokill step
# library as replay/robokill/run.sh builds it.
programs='vendor/bend/tests/run/nat_native.bend
vendor/bend/tests/run/float_printing.bend
vendor/bend/tests/run/expr_interpreter.bend
vendor/bend/tests/run/fn_capture_owns.bend
vendor/bend/tests/run/string_algorithms.bend
vendor/bend/tests/io/fiber_single_join.bend
vendor/bend/tests/io/nat_host_bounds.bend
replay/robokill/step.bend --lib init,input_at,step,hash,render'

work=$(mktemp -d "${TMPDIR:-/tmp}/bend-repro.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM

# pass NAME ENV...: compiles every program into $work/NAME/c/ with a fresh
# compiler copy under $work/NAME/root, from cwd $work/NAME, with ENV
# (VAR=value words) added to the environment.
pass() {
  name=$1
  shift
  d=$work/$name
  mkdir -p "$d/root/scripts" "$d/c" "$d/tmp" "$d/bun-cache"
  cp scripts/bend "$d/root/scripts/bend"
  ln -s "$root/vendor" "$d/root/vendor"
  ln -s "$root/patches" "$d/root/patches"
  echo "$programs" | while read -r src args; do
    p=$(echo "$src" | sed 's|^vendor/bend/tests/||; s|\.bend$||; s|/|_|g')
    # shellcheck disable=SC2086 # the arguments are words on purpose
    if ! (cd "$d" && env "$@" TMPDIR="$d/tmp" \
      BUN_RUNTIME_TRANSPILER_CACHE_PATH="$d/bun-cache" \
      "$d/root/scripts/bend" "$root/$src" -o "$d/c/$p.c" $args) \
      > "$d/$p.log" 2>&1; then
      echo "$p: FAILED to compile in pass $name: $(head -n 1 "$d/$p.log")"
      return 1
    fi
  done
}

pass a TZ=UTC LANG=C LC_ALL=C || exit 1
pass b TZ=Pacific/Chatham LANG=pl_PL.UTF-8 LC_ALL=pl_PL.UTF-8 || exit 1

status=0
n=0
for f in "$work"/a/c/*.c; do
  n=$((n + 1))
  p=$(basename "$f" .c)
  if ! cmp "$f" "$work/b/c/$p.c"; then
    echo "$p: DIFFERS between the two passes"
    status=1
    break
  fi
  echo "$p: ok"
done
[ "$status" = 0 ] && echo "programs: $n; the emitted C is byte identical"
exit $status
