# Working in bend-wasm

Project-specific rules for every person and agent working here. They add to
the general policy in `AGENTS.md`. The plan is `docs/plan.md`.

## The pinned toolchain

| Tool | Pin | Where |
| --- | --- | --- |
| Bend 2 | tag `v2.0.35`, commit `79df8d9c40722ee9507a1e253f283b51025f9d6c` | `vendor/bend`, a shallow submodule of https://github.com/bendlang/bend |
| Bun | `1.4.2` | `want_bun` in `scripts/bend` |
| Emscripten | emsdk tag `6.0.10`, SDK `6.0.10` | `~/.cache/bend-wasm/emsdk-6.0.10`, pinned in `scripts/emcc` |

The emsdk pin is the newest release tag that was at least two weeks old
when it was chosen (2026-10-16: `6.0.10` is from 2026-09-21, `6.0.11` from
2026-10-02).

The SDK lives outside the repository because herdr workers have no network
and cannot write outside their folder: it is installed once per machine
(below) and the scripts only read it. Builds never write into it:
`scripts/emcc` sets `EM_CACHE` to the repository's `.cache/emscripten`
(ignored).

Without network, herdr's worker folder
(`../herdr-worktrees/bend-wasm/worker`, relative to the repository) has no
`vendor/bend` checkout until the coordinator runs
`git submodule update --init --depth 1 vendor/bend` in that folder, before
dispatching an item that runs `scripts/bend`. Workers never fetch it
themselves; `scripts/bend` stops with that command when it is missing.

## Running the tools

- Build, check and run Bend only with `scripts/bend`, never a global
  `bend`. It runs `vendor/bend/bend2/main.ts` with the pinned Bun
  (`BEND_BUN=/path/to/bun` picks another binary of the same version) and
  `BEND_NO_TELEMETRY=1`. If `vendor/bend` is not checked out, it prints
  `git submodule update --init --depth 1 vendor/bend` and exits 1.
- Compile with `scripts/emcc`, never a system-wide `emcc`. It takes the
  same arguments as `emcc`, sources the pinned SDK's `emsdk_env.sh`,
  checks that `emcc --version` reports the pin, and fails with the install
  commands otherwise. `BEND_WASM_EMSDK=/path/to/emsdk` points to another
  install of the same pin.
- `scripts/bend --toolchain` prints the Bend tag and commit, the Bun
  version and the first line of `scripts/emcc --version`; record it with
  results.

## Installing the SDK on a new machine

```sh
dir=~/.cache/bend-wasm/emsdk-6.0.10
git clone --depth 1 --branch 6.0.10 https://github.com/emscripten-core/emsdk "$dir"
"$dir/emsdk" install 6.0.10
"$dir/emsdk" activate 6.0.10
scripts/emcc --version
```

## Moving a pin

Moving a pin is its own commit, with `scripts/bend --toolchain` output and
the rerun checks in its message or results:

- Bend: check out the new tag in `vendor/bend` (shallow), update the tag
  and commit in this file, and update `want_bun` in `scripts/bend` if the
  release needs another Bun. The coordinator then updates `vendor/bend` in
  herdr's worker folder the same way.
- Bun: change `want_bun` in `scripts/bend` and the table above.
- Emscripten: install the new SDK into `~/.cache/bend-wasm/emsdk-<ver>` as
  above, change `want` in `scripts/emcc` and the table above.
