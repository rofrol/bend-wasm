# Reproducibility of the emitted C

`tests/repro/run.sh` checks that the patched compiler emits the same C,
byte for byte, for the same program, so the wasm build depends only on the
pinned toolchain (`docs/workflow.md`) and the source, never on ordering,
time or the environment.

```sh
sh tests/repro/run.sh
```

It compiles a handful of programs from `tests/differential/corpus.txt` and
`replay/robokill/step.bend` (with `--lib init,input_at,step,hash,render`,
as `replay/robokill/run.sh` builds it) to C in two passes. Each pass runs
`scripts/bend` from its own scratch root, so it builds a fresh patched copy
of the pin there (its `.toolchain/`; the repository's is not touched), with
an empty Bun transpiler cache (`BUN_RUNTIME_TRANSPILER_CACHE_PATH`). The
first pass runs with `TZ=UTC` and the C locale, the second with another
time zone, the Polish UTF-8 locale, another working directory and another
`TMPDIR`. It prints one line per program and stops at the first program
whose two outputs differ (`cmp` names the first differing byte). The
scratch directory comes from `mktemp` and is removed at the end. Exit
status 0 only when every program gave identical C.

Checked 2026-10-16 (Bend v2.0.35 with patches 0001 to 0003, Bun
`1.4.2+50a8a8387`, macOS arm64): all 8 programs identical. A temporary
patch that made `bend2/main.ts` prepend `new Date().toString()` to the
emitted C made the check fail on the first program, as expected.
