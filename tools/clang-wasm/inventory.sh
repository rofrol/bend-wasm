#!/bin/sh
# What libc does a plain-clang wasm build of Bend's C need? (TODO
# t-fwjpak4c, step A; docs/clang-wasm.md)
#
# Emits the C of every program in tests/differential/corpus.txt (as the
# wasm lane of tests/differential/run.sh does) and of Robokill's step
# library (replay/robokill/step.bend in library mode, as glue/build.sh
# builds it), then, with the clang of the pinned Emscripten SDK and no
# emcc:
#
# - lists the headers each C file reaches with no sysroot at all (clang -M
#   -MG): the ones clang's own resource directory has, and the ones it does
#   not, which a bare `clang --target=wasm32` fails on;
# - compiles it for wasm32 with -nostdlib, taking only declarations from
#   the SDK's musl-based sysroot (--sysroot, no libc linked), and lists the
#   object's undefined symbols (llvm-nm -u).
#
# The compile uses scripts/wasm-flags' C flags (-std=c11 -O2 -mtail-call;
# the -s settings are emcc's link settings) and -D__EMSCRIPTEN__, the
# macro the patch series keys its wasm path on, which emcc's
# wasm32-unknown-emscripten target predefines and --target=wasm32 does
# not.
#
#   tools/clang-wasm/inventory.sh [OUTDIR]
#
# OUTDIR (default tools/clang-wasm/out, ignored) gets per program NAME.c,
# NAME.emit.log, NAME.deps (clang -M -MG), NAME.headers.missing,
# NAME.headers.clang, NAME.compile.log (clang's diagnostics), NAME.o and
# NAME.undef; and the unions with the number of programs needing each:
# symbols.txt, headers-missing.txt, headers-clang.txt, and warnings.txt
# (each distinct clang warning with its count). BEND_WASM_EMSDK points to
# another install of the same pin. Exit status: 0 when every program
# emitted and compiled.
set -u
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1
out=${1:-tools/clang-wasm/out}
sdk=${BEND_WASM_EMSDK:-$HOME/.cache/bend-wasm/emsdk-6.0.10}
bin=$sdk/upstream/bin
sysroot=$sdk/upstream/emscripten/cache/sysroot
for tool in clang llvm-nm; do
  if [ ! -x "$bin/$tool" ]; then
    echo "tools/clang-wasm/inventory.sh: no $tool in $bin" >&2
    exit 1
  fi
done
if [ ! -f "$sysroot/include/stdio.h" ]; then
  echo "tools/clang-wasm/inventory.sh: no sysroot headers in $sysroot" >&2
  exit 1
fi

rm -rf "$out"
mkdir -p "$out/tmp"
out=$(cd "$out" && pwd)
# clang's and Bend's temporary files stay in the output directory.
export TMPDIR="$out/tmp"
# shellcheck disable=SC2046 # the flags are words on purpose
set -- $("$root/scripts/wasm-flags")
cflags=
for f in "$@"; do
  case $f in -s*) ;; *) cflags="$cflags $f" ;; esac
done
cflags="--target=wasm32 -nostdlib -D__EMSCRIPTEN__$cflags"
"$bin/clang" --version | head -n 1 > "$out/toolchain.txt"
echo "flags: $cflags --sysroot=$sysroot -c" >> "$out/toolchain.txt"

status=0
programs=0
# inventory NAME SRC [--lib DEFS]: one program, into $out/NAME.*.
inventory() {
  name=$1 src=$2
  shift 2
  programs=$((programs + 1))
  b=$out/$name
  if ! scripts/bend "$src" -o "$b.c" "$@" > "$b.emit.log" 2>&1; then
    echo "$name: FAILED, emit: $(head -n 1 "$b.emit.log")"
    status=1
    return
  fi
  # No sysroot: -MG lists a header clang cannot find under the name the C
  # gives; a header it finds (its resource directory) has a full path.
  # shellcheck disable=SC2086
  "$bin/clang" $cflags -M -MG "$b.c" > "$b.deps" 2> "$b.deps.log"
  sed 's/\\$//' "$b.deps" | tr ' ' '\n' | sed '1d' | grep -v '^$' | grep -v "^$b.c\$" \
    > "$b.deps.list"
  grep -v '^/' "$b.deps.list" | sort -u > "$b.headers.missing"
  grep '^/' "$b.deps.list" | sed 's|.*/include/||' | sort -u \
    > "$b.headers.clang"
  # shellcheck disable=SC2086
  if ! "$bin/clang" $cflags --sysroot="$sysroot" -c "$b.c" -o "$b.o" \
    > "$b.compile.log" 2>&1; then
    echo "$name: FAILED, compile: $(grep -m 1 'error:' "$b.compile.log")"
    status=1
    return
  fi
  "$bin/llvm-nm" -u "$b.o" | awk '{ print $NF }' | sort -u > "$b.undef"
  echo "$name: $(wc -l < "$b.undef" | tr -d ' ') undefined," \
    "$(wc -l < "$b.headers.missing" | tr -d ' ') headers missing"
}

while read -r src rest; do
  case $src in '' | '#'*) continue ;; esac
  inventory "$(echo "$src" | sed 's|^vendor/bend/tests/||; s|\.bend$||; s|/|_|g')" \
    "$src"
done < tests/differential/corpus.txt
inventory robokill_step replay/robokill/step.bend --lib init,input_at,step,hash,render

# union FILES: each line with the number of files that have it.
union() {
  cat "$@" 2>/dev/null | sort | uniq -c | sort -k1,1nr -k2
}
union "$out"/*.undef > "$out/symbols.txt"
union "$out"/*.headers.missing > "$out/headers-missing.txt"
union "$out"/*.headers.clang > "$out/headers-clang.txt"
for l in "$out"/*.compile.log; do
  grep -o 'warning: .*' "$l" | sort -u
done | union > "$out/warnings.txt"
echo "programs: $programs; symbols: $(wc -l < "$out/symbols.txt" | tr -d ' ');" \
  "headers missing without a sysroot: $(wc -l < "$out/headers-missing.txt" | tr -d ' ')"
rm -rf "$out/tmp"
exit $status
