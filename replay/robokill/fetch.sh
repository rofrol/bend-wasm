#!/bin/sh
# Re-copies the vendored test inputs of the Robokill replay
# (replay/robokill/README.md) from Robokill's pinned commit: spike/step.bend
# and spike/replay.bend, each behind one header line naming the source.
# It only reads the Robokill checkout (git show), never builds or edits it.
#
# Usage: ROBOKILL=/path/to/Robokill replay/robokill/fetch.sh
# Exit status: 0 when every copy equals the committed one; 1 when one
# differs (the fresh copy is left in place, so `git diff` shows how) or
# the commit cannot be read.
set -u
here=$(cd "$(dirname "$0")" && pwd)
commit=63031ab
src=${ROBOKILL:?set ROBOKILL to a Robokill checkout}
status=0
for f in step.bend replay.bend; do
  tmp=$here/.$f.tmp
  if ! { echo "# Vendored test input, not bend-wasm code: spike/$f of the" \
    "Robokill repository at commit $commit (replay/robokill/fetch.sh" \
    "re-copies it)."
    git -C "$src" show "$commit:spike/$f"; } > "$tmp"; then
    rm -f "$tmp"
    echo "fetch.sh: cannot read spike/$f at $commit in $src" >&2
    exit 1
  fi
  if cmp -s "$tmp" "$here/$f"; then
    rm -f "$tmp"
  else
    mv "$tmp" "$here/$f"
    echo "fetch.sh: replay/robokill/$f differs from Robokill $commit; the" \
      "fresh copy is in place" >&2
    status=1
  fi
done
exit $status
