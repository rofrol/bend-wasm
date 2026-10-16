#!/bin/sh
# Builds Bend's C into wasm with the pinned Emscripten SDK's plain clang
# and wasm-ld, no emcc and no SDK library (TODO t-fwjpak4c, steps B and C;
# docs/clang-wasm.md):
#
#   tools/clang-wasm/build.sh FILE.c OUTDIR NAME
#
# FILE.c is the C of scripts/bend (a program, or library mode's --lib).
# It compiles with --target=wasm32 -nostdlib, scripts/wasm-flags' C flags
# (-std=c11 -O2 -mtail-call; its -s settings are emcc's), bulk memory, and
# -DBEND_WASM_FREESTANDING, the guard of patch 0004, which supplies the
# libc the runtime calls and turns on the series' wasm path; the SDK's
# musl headers give only declarations (--sysroot, as step A). The math
# functions, strtof, strtod and printf's %e/%f come from vendored musl and
# compiler-rt sources, which tools/clang-wasm/libc.sh builds into
# OUTDIR/libc.a (step C). wasm-ld links the two with --no-entry and
# exports:
#
# - a library (the C defines bend_init): what glue/build.sh's emcc build
#   exports (glue/gen.mjs exports: bend_init, bend_dispose,
#   bend_heap_words, bend_handles, bend_f32, bend_f32_len, malloc, each
#   bend_def_*);
# - a program: __main_argc_argv (main(argc, argv)) and malloc, for the
#   host to place argv;
# - both: memory and __wasm_call_ctors, which the host calls once before
#   anything else (the effects register themselves in constructors).
#
# Memory is sized as scripts/wasm-flags sizes emcc's: the static image,
# a 64 KiB stack (placed first, so an overflow traps) and a 1 MiB heap
# (--initial-heap), and it never grows (--no-growable-memory: the maximum
# is the initial size). malloc asks memory.grow for more, which then
# fails, and the run stops with "bend: host allocation failed", as under
# emcc; the glue's views of memory stay valid.
#
# Then binaryen's wasm-opt --memory-packing (from the same SDK; only that
# pass) drops the zero runs of the data: clang evaluates the effects'
# constructors at compile time, so the 512 KiB io_eff_rows of a program
# becomes initialized data, nearly all zeros, which wasm-ld writes out
# whole. emcc's own wasm-opt does the same. It also drops the name
# section, so the tail-call check below reads the linked module.
#
# Writes OUTDIR/NAME.wasm, and beside it libc.a, NAME.o, NAME.ld.wasm (wasm-ld's
# output, with names), NAME.exports (one per line), NAME.imports
# (module.name kind per line), NAME.dis (llvm-objdump -d of NAME.ld.wasm),
# NAME.tail (below) and NAME.build.log. Fails when a step fails or a
# musttail is not a tail call. BEND_WASM_EMSDK points to another install
# of the same pin.
set -u
if [ $# != 3 ]; then
  echo "usage: tools/clang-wasm/build.sh FILE.c OUTDIR NAME" >&2
  exit 2
fi
c=$1 out=$2 name=$3
root=$(cd "$(dirname "$0")/../.." && pwd)
sdk=${BEND_WASM_EMSDK:-$HOME/.cache/bend-wasm/emsdk-6.0.10}
bin=$sdk/upstream/bin
sysroot=$sdk/upstream/emscripten/cache/sysroot
node=$(find "$sdk/node" -path '*/bin/node' -type f 2>/dev/null | head -n 1)
for tool in clang wasm-ld wasm-opt llvm-objdump; do
  if [ ! -x "$bin/$tool" ]; then
    echo "tools/clang-wasm/build.sh: no $tool in $bin" >&2
    exit 1
  fi
done
if [ -z "$node" ]; then
  echo "tools/clang-wasm/build.sh: no node in $sdk/node" >&2
  exit 1
fi
mkdir -p "$out"
b=$out/$name
log=$b.build.log
: > "$log"

fail() {
  echo "tools/clang-wasm/build.sh: $name: $*" >&2
  exit 1
}

# shellcheck disable=SC2046 # the flags are words on purpose
set -- $("$root/scripts/wasm-flags")
cflags="--target=wasm32 -nostdlib -mbulk-memory -DBEND_WASM_FREESTANDING"
for f in "$@"; do
  case $f in -s*) ;; *) cflags="$cflags $f" ;; esac
done
# shellcheck disable=SC2086
"$bin/clang" $cflags --sysroot="$sysroot" -c "$c" -o "$b.o" >> "$log" 2>&1 \
  || fail "compile failed (log $log)"

# The libc part from vendored musl and compiler-rt sources (step C).
lib=$out/libc.a
sh "$root/tools/clang-wasm/libc.sh" "$lib" >> "$log" 2>&1 \
  || fail "the libc archive failed (log $log)"

if grep -q '^void bend_init(void) {$' "$c"; then
  exports=$("$node" "$root/glue/gen.mjs" exports "$c" | tr ',' '\n' \
    | sed 's/^_//') || fail "glue/gen.mjs exports failed"
else
  exports="__main_argc_argv
malloc"
fi
exports="$exports
__wasm_call_ctors"
printf '%s\n' "$exports" > "$b.exports"
flags=
for x in $exports; do
  flags="$flags --export=$x"
done
# shellcheck disable=SC2086
"$bin/wasm-ld" --no-entry $flags -z stack-size=65536 --stack-first \
  --initial-heap=1048576 --no-growable-memory "$b.o" "$lib" -o "$b.ld.wasm" \
  >> "$log" 2>&1 || fail "link failed (log $log)"
"$bin/wasm-opt" --memory-packing "$b.ld.wasm" -o "$b.wasm" >> "$log" 2>&1 \
  || fail "wasm-opt failed (log $log)"

"$bin/llvm-objdump" -d "$b.ld.wasm" > "$b.dis" 2>> "$log" \
  || fail "llvm-objdump failed (log $log)"
"$node" "$root/tools/clang-wasm/check.mjs" imports "$b.ld.wasm" > "$b.imports" \
  || fail "reading the imports failed"

# Tail calls. Every musttail of the template is a segment (WL_*) entering
# another segment, directly or through wl_tab; clang refuses one it cannot
# honour, and -mtail-call lowers it to return_call(_indirect). The check:
# no segment of the module enters a segment by a plain call or any
# call_indirect (wl_tab is the only function table a segment reaches), and
# the module has return_calls. Their number can be below the musttail
# sites of the preprocessed C: a site on a path the optimizer proves dead
# (FID_EXIT's continuation when no def's continuation has a frame) leaves
# no code.
# shellcheck disable=SC2086
"$bin/clang" $cflags --sysroot="$sysroot" -E -P "$c" -o "$b.i" >> "$log" 2>&1 \
  || fail "preprocessing failed (log $log)"
sites=$(grep -o 'musttail' "$b.i" | wc -l | tr -d ' ')
rm -f "$b.i"
# llvm-objdump names a call's target by its index: the imported functions
# come first, then the module's in the order of the listing.
nimp=$(grep -c ' function$' "$b.imports")
awk -v nimp="$nimp" '
  /^[0-9a-f]+ <.*>:$/ {
    fn = $2; gsub(/[<>:]/, "", fn)
    if (FNR == NR) {
      if (fn != "CODE") { name[nimp + k] = fn; k += 1 }
      next
    }
    seg = fn ~ /^WL_/
  }
  FNR == NR { next }
  /\treturn_call(_indirect)?\t/ { tail += 1; next }
  seg && /\tcall_indirect\t/ { print fn ": " $0 }
  seg && /\tcall\t/ && name[$NF] ~ /^WL_/ { print fn ": " $0 " (" name[$NF] ")" }
  END { print tail + 0 > "/dev/stderr" }
' "$b.dis" "$b.dis" > "$b.tail.plain" 2> "$b.tail.n"
calls=$(cat "$b.tail.n")
plain=$(wc -l < "$b.tail.plain" | tr -d ' ')
# wasm-opt must keep them all.
final=$("$bin/llvm-objdump" -d "$b.wasm" 2>> "$log" \
  | grep -cE '	return_call(_indirect)?	')
{
  echo "musttail sites in the preprocessed C: $sites"
  echo "return_call and return_call_indirect in the module: $calls"
  echo "of them after wasm-opt: $final"
  echo "segments entering a segment without a tail call: $plain"
  cat "$b.tail.plain"
} > "$b.tail"
rm -f "$b.tail.plain" "$b.tail.n"
if [ "$plain" != 0 ] || [ "$final" != "$calls" ] \
  || { [ "$calls" = 0 ] && [ "$sites" != 0 ]; }; then
  fail "a musttail is not a return_call ($b.tail)"
fi
exit 0
