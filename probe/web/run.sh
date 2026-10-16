#!/bin/sh
# Browser check of the wasm target (docs/probe.md, "Browser"): builds the
# pure probe programs with the flags of scripts/wasm-flags plus what a
# plain page needs (the wasm embedded in the JS so the page works from
# file://, synchronous compilation so the run ends before the load event,
# no -pthread and so no cross-origin isolation), opens
# probe/web/index.html?p=NAME in headless Chrome with --dump-dom and
# compares the program's stdout in the dumped page with the native binary
# (`scripts/bend NAME.bend -o NAME.bin`).
#
# Chrome cannot start inside the herdr worker sandbox (exit 21); run this
# script outside it.
# CHROME=/path/to/chrome picks another Chrome binary.
# Output: probe/web/out/ (ignored), one log per step, and summary.txt.
# Exit status: 0 when every program matched native, exit code 0 included,
# in a page that was not cross-origin isolated.
set -u
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
web=probe/web
out=$web/out
chrome=${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}
flags="$(scripts/wasm-flags) -sENVIRONMENT=web -sSINGLE_FILE=1 -sWASM_ASYNC_COMPILATION=0 -sEXIT_RUNTIME=1"

rm -rf "$out"
mkdir -p "$out"
summary=$out/summary.txt
{
  scripts/bend --toolchain
  "$chrome" --version
  echo "flags: $flags"
  echo
} > "$summary"

say() {
  echo "$*" | tee -a "$summary"
}

# The text of the element with id $1 in the dumped page $2, unescaped.
element() {
  perl -0777 -ne 'if (/<(\w+) id="'"$1"'">(.*?)<\/\1>/s) {
    $_ = $2; s/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&#39;/'"'"'/g;
    s/&nbsp;/ /g; s/&amp;/&/g; print }' "$2"
}

for p in hello arith; do
  src=probe/$p.bend
  base=$out/$p
  if ! scripts/bend "$src" -o "$base.bin" > "$base.native.log" 2>&1 \
    || ! "$base.bin" > "$base.native.out" 2> "$base.native.err"; then
    say "$p: native build or run FAILED; stop"
    continue
  fi
  if ! scripts/bend "$src" -o "$base.c" > "$base.emit.log" 2>&1; then
    say "$p: scripts/bend -o $p.c FAILED; stop"
    continue
  fi
  # shellcheck disable=SC2086 # flags are words on purpose
  if ! scripts/emcc $flags "$base.c" -o "$base.js" > "$base.build.log" 2>&1; then
    say "$p: build FAILED"
    continue
  fi
  # A fresh profile per run, so no cache or setting carries over. The
  # alarm only bounds a hung browser; --dump-dom exits by itself.
  rm -rf "$base.profile"
  perl -e 'alarm 120; exec @ARGV or exit 127' "$chrome" --headless=new \
    --disable-gpu --no-first-run --no-default-browser-check \
    --user-data-dir="$root/$base.profile" \
    --dump-dom "file://$root/$web/index.html?p=$p" \
    > "$base.dom.html" 2> "$base.chrome.log"
  code=$?
  rm -rf "$base.profile"
  if [ "$code" != 0 ]; then
    say "$p: Chrome FAILED, exit $code (see $base.chrome.log)"
    continue
  fi
  element stdout "$base.dom.html" > "$base.out"
  element stderr "$base.dom.html" > "$base.err"
  isolated=$(element isolated "$base.dom.html")
  exit_code=$(element exit "$base.dom.html")
  if [ "$isolated" != false ]; then
    say "$p: page FAILED, crossOriginIsolated is '$isolated', not false"
  elif [ "$exit_code" != 0 ]; then
    say "$p: run FAILED, exit '$exit_code': $(head -n 1 "$base.err")"
  elif cmp -s "$base.out" "$base.native.out"; then
    say "$p: output matches native, exit 0, crossOriginIsolated false"
  else
    say "$p: output DIFFERS from native (diff $base.native.out $base.out)"
  fi
done

if grep -q -e FAILED -e DIFFERS "$summary"; then
  exit 1
fi
exit 0
