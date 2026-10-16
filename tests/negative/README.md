# Negative checks

`tests/negative/run.sh` (herdr check `negative`) shows that the
repository's checks fail on known-bad builds, for the intended reason: each
case runs a check, requires a non-zero exit and matches its message. It
exits 0 only when every case failed as expected. Output, one log per case:
`tests/negative/out/` (ignored).

```sh
sh tests/negative/run.sh
```

## Mechanism

A mutant is a small patch file here, a diff against the pin with the whole
series applied. `scripts/bend` appends the files named in
`BEND_PATCH_EXTRA` (paths relative to the repository) to the series; they
are part of the series hash, so each mutant builds into its own
`.toolchain/` copy and the real series' copy is never changed. Only this
check sets the variable. No mutation framework: a mutant is written by
hand the way `patches/README.md` says, on a scratch copy of the patched
pin.

## Cases

First, `probe/lib/run.sh` must pass on the real series, so the failures
below come from the mutants.

| Case | Known-bad build | Check that must fail, and its message |
| --- | --- | --- |
| leak | `leak.patch`: every library-mode call allocates a task node it never frees | `probe/lib/run.sh`: `FAILED: native: the heap high-water grew ...` (the mark at 100,000 steps above the mark at 10,000); in wasm the same message, or the runtime's out-of-memory error (`ERR_HEAP`, `bend: out of memory: ...`) when the default corpus fills first, with only its consequences (the wasm drivers exit 1, their output differs from native's); nothing else |
| stale | real series: `consumed.c` and `consumed.mjs` peek a handle `step` consumed | `bend: peek: a handle that was consumed, disposed or never made` and exit 1, natively and in wasm |
| stale | `stale-handle.patch`: `lib_take` no longer checks liveness and generation | `probe/lib/run.sh`: `a disposed handle gave exit ...` for both drivers (they loop until the hang guard stops them), and nothing else |
| env-abi | `env-abi.patch`: reverts patch 0002's two-word `Env` passing | `LANES=wasm tests/differential/run.sh`: exactly `reg_nat_chain`, `run_bst_insert`, `run_string_algorithms` DIFFER or FAIL on the wasm lane |
| missing-lane | `BEND_PATCH=0`, so the wasm lane cannot be built | `tests/differential/run.sh` with its default lanes: `wasm: FAILED, not available` |

It takes about 2.5 minutes (2026-10-16, Apple arm64 Mac, warm
`.toolchain/` and Emscripten cache), most of it the env-abi case's
differential run.
