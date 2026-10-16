#!/bin/sh
# Does Bend's compiler run on QuickJS? (docs/quickjs.md)
#
# Builds qjs from a copy of the unpacked QuickJS release in the cache, never
# inside the cache; bundles the patched compiler that scripts/bend runs into
# one file with the pinned Bun (bun build --target=bun); points its node:*
# imports at the probe shims in tools/quickjs/shim/; then emits C for each
# program below with qjs and with scripts/bend, compares the two files byte
# for byte and prints the time of each emit.
#
# Everything goes into a fresh directory under $TMPDIR (QUICKJS_KEEP=1
# keeps it). QUICKJS_SRC points to another unpacked copy of the same
# release. Exit status: 0 when every program's C is byte-identical.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
version=2026-06-04
src=${QUICKJS_SRC:-$HOME/.cache/bend-wasm/quickjs-$version}
if [ "$(cat "$src/VERSION" 2>/dev/null)" != "$version" ]; then
  echo "tools/quickjs/run.sh: no QuickJS $version at $src (set QUICKJS_SRC)" >&2
  exit 1
fi
work=$(mktemp -d "${TMPDIR:-/tmp}/quickjs.XXXXXX")
if [ "${QUICKJS_KEEP:-0}" = 1 ]; then
  echo "work directory: $work"
else
  trap 'rm -rf "$work"' EXIT
fi
trap 'exit 1' HUP INT TERM

# qjs, built from a writable copy with its own Makefile and the system cc.
cp -R "$src" "$work/qjs-src"
chmod -R u+w "$work/qjs-src"
make -C "$work/qjs-src" qjs > "$work/qjs-build.log" 2>&1 || {
  tail -n 20 "$work/qjs-build.log" >&2
  exit 1
}
qjs=$work/qjs-src/qjs

# The compiler copy scripts/bend runs: .toolchain/<pin>-<series hash>, or
# vendor/bend when the series is empty or off.
tc=$(scripts/bend --toolchain)
pin=$(echo "$tc" | sed -n 's/^bend [^ ]* //p')
sum=$(echo "$tc" | sed -n 's/^patches: \([0-9a-f]\{16\}\) .*/\1/p')
bend2=vendor/bend/bend2
if [ -n "$sum" ]; then
  bend2=.toolchain/$pin-$sum/bend2
fi
echo "$tc" | sed 's/^/# /'
echo "# qjs $("$qjs" --help | head -n 1)"

# One-file bundle next to base.bend and effs/ (BEND_DIR is the bundle's
# directory), with every node:* import pointed at a shim and the globals
# shim first.
out=$work/bend2
mkdir -p "$out/shim"
cp tools/quickjs/shim/*.mjs "$out/shim/"
cp "$bend2/base.bend" "$out/"
cp -R "$bend2/effs" "$out/"
bun build "$bend2/main.ts" --target=bun --format=esm --outfile="$out/bundle.mjs" \
  > "$work/bun-build.log" 2>&1 || { cat "$work/bun-build.log" >&2; exit 1; }
{
  echo 'import "./shim/globals.mjs";'
  sed -E \
    -e '1{/^#!/d;}' \
    -e 's#from "(node:)?(fs|path|url|os)"#from "./shim/\2.mjs"#' \
    -e 's#from "(node:)?(child_process|crypto|module|worker_threads)"#from "./shim/missing.mjs"#' \
    "$out/bundle.mjs"
} > "$out/main.mjs"
if grep -nE '^import .* from "(node:|bun)' "$out/main.mjs" >&2; then
  echo "tools/quickjs/run.sh: an import is not shimmed (above)" >&2
  exit 1
fi

# now_ms prints a wall-clock timestamp in milliseconds.
now_ms() {
  perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'
}

bad=0
emit() {
  name=$1
  shift
  t0=$(now_ms)
  scripts/bend "$@" -o "$work/$name.bun.c"
  t1=$(now_ms)
  # qjs's default JS stack limit is 1 MiB; Robokill's step.bend needs more
  # than 2 MiB and passes at 4 MiB. 6 MiB stays under macOS's default 8 MiB
  # main-thread stack (ulimit -s), so qjs reports an overflow, not a crash.
  if ! BEND_NO_TELEMETRY=1 "$qjs" --stack-size 6M --std -m "$out/main.mjs" "$@" -o "$work/$name.qjs.c" \
    2> "$work/$name.qjs.err"; then
    echo "FAIL $name: qjs exited nonzero:" >&2
    cat "$work/$name.qjs.err" >&2
    bad=1
    return
  fi
  t2=$(now_ms)
  if cmp -s "$work/$name.bun.c" "$work/$name.qjs.c"; then
    echo "same $name: $(wc -c < "$work/$name.qjs.c" | tr -d ' ') bytes," \
      "bun $((t1 - t0)) ms, qjs $((t2 - t1)) ms"
  else
    echo "FAIL $name: the C differs" >&2
    cmp "$work/$name.bun.c" "$work/$name.qjs.c" >&2 || true
    bad=1
  fi
}

emit nat_native vendor/bend/tests/run/nat_native.bend
emit robokill replay/robokill/step.bend --lib init,input_at,step,hash,render
exit $bad
