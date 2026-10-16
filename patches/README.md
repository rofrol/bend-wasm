# Patches to the pinned Bend

Our changes to the Bend compiler and runtime
(`docs/decisions/0001-wasm-through-a-patched-emitter.md`). `vendor/bend`
stays a clean checkout of the pinned commit; `scripts/bend` copies it into
`.toolchain/` and applies this series there (`docs/workflow.md`, "Patches").

## Convention

- One unified diff per file, named `NNNN-short-name.patch`, applied in name
  order with `git apply`. Paths are relative to the Bend checkout
  (`a/bend2/comp.ts`), as `git diff` writes them there.
- Each file starts with a header: the lines before the first `diff --git`,
  which `git apply` ignores. It says what the patch changes, why, and
  `Retired by:` the upstream change (an issue, a pull request or a release)
  that would make it unnecessary.
- Every patch applies cleanly, in order, to exactly the pinned commit:
  `scripts/check-patches` checks this and the `Retired by:` line.

## Making a patch

Edit a scratch copy of the pin with the earlier patches applied, never
`vendor/bend` itself:

```sh
scratch=/path/to/scratch           # outside the repository
git -C vendor/bend archive HEAD | (mkdir -p "$scratch" && tar -x -C "$scratch")
cd "$scratch" && git init -q && git add -A && git commit -qm pin
for p in /path/to/bend-wasm/patches/*.patch; do git apply "$p"; done
git add -A && git commit -qm series
# edit, then:
{ printf '%s\n' 'What it changes and why.' 'Retired by: <upstream link>' ''
  git diff | sed 's/^ $//'; } > /path/to/bend-wasm/patches/NNNN-short-name.patch
```

The `sed` empties the context lines of blank source lines, which `git diff`
writes as a single space: committed as is, they fail the `whitespace`
check (`git diff --check`). `git apply` reads an empty line in a hunk as
that same blank context line, so the patch applies to the same result.
Trailing whitespace of any other kind comes from the Bend source itself
and cannot be stripped without breaking `git apply`; if the check still
fails, report it instead of editing the patch by hand.

Then run `scripts/check-patches` and the checks of the item. To change an
existing patch, apply the series up to the one before it, edit, and write
the patch again the same way; check that the later ones still apply.
