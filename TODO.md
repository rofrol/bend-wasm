# TODO

Plan and context: `docs/plan.md`.

## Next, in order

- [ ] Pin Bend 2.0.35 (commit 79df8d9 of https://github.com/bendlang/bend) and [t-3fa5ws5p]
  a Bun version the way `~/personal_projects/herdr-bend` does (vendor
  submodule plus `scripts/bend`), and install Emscripten pinned by version;
  record the toolchain in `docs/workflow.md`.
- [ ] Probe: compile a hello world and a pure arithmetic program through [t-jk5jg2zk]
  `bend -o x.c` and `emcc` with build flags only; record every error in
  `docs/probe.md` and classify each blocker as shim-able, emitter change or
  architectural, with the `comp.ts` lines involved.
- [ ] If the probe allows it: a CPU-only single-worker build of the pure [t-xwj7ptut]
  program runs under Node and in a browser page without cross-origin
  isolation, with output identical to the native build.
- [ ] Differential test harness: one script builds a corpus native, JS lane and [t-ucc65gif]
  wasm and diffs stdout and exit code; start with at least 20 deterministic
  programs from Bend's own tests; list exclusions with reasons.

## Needs a decision

- [ ] Open the upstream issue at https://github.com/bendlang/bend with the [t-ymygf5au]
  outline in `docs/plan.md`, once the probe has its first errors?
  Options: yes, after the probe | not yet | never
- [ ] Patch the Bend emitter (`comp.ts`) if the probe shows that flags and [t-3oqripea]
  shims are not enough?
  Options: decide after seeing the blocker inventory | no patches, upstream only

## Proposed
