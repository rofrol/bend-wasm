# TODO

Plan and context: `docs/plan.md`.

## Next, in order

- [ ] Probe: compile a hello world and a pure arithmetic program through [t-jk5jg2zk]
  `bend -o x.c` and `emcc` with build flags only; record every error in
  `docs/probe.md` and classify each blocker as shim-able, emitter change or
  architectural, with the `comp.ts` lines involved.

- [ ] Open the upstream issue at https://github.com/bendlang/bend with the [t-ymygf5au]
  outline in `docs/plan.md`, once the probe has its first errors?
  Decided by the user 2026-10-16 (d-kznksmaz): yes, after the probe; the
  coordinator shows the issue text for approval before posting.

- [ ] If the probe allows it: a CPU-only single-worker build of the pure [t-xwj7ptut]
  program runs under Node and in a browser page without cross-origin
  isolation, with output identical to the native build.
- [ ] Differential test harness: one script builds a corpus native, JS lane and [t-ucc65gif]
  wasm and diffs stdout and exit code; start with at least 20 deterministic
  programs from Bend's own tests; list exclusions with reasons.

## Needs a decision

- [ ] How does t-3fa5ws5p get its network steps, given that herdr workers [t-7qwx2nm3]
  have no network by design?
  Options: the coordinator runs only the network steps (git submodule add of vendor/bend at v2.0.35, emsdk SDK download into ~/.cache/bend-wasm/emsdk-<ver>) and commits the submodule, then a worker writes scripts/bend, scripts/emcc (EM_CACHE inside the repository) and docs/workflow.md offline | the coordinator does the whole item itself | a herdr per-repository worker network allowlist (github.com, storage.googleapis.com), a herdr TODO item and a security boundary change
  Decided by the user 2026-10-16 (d-6x44i4p5): the coordinator fetches
  (vendor/bend submodule at v2.0.35, emsdk SDK into ~/.cache/bend-wasm),
  a worker does the rest offline. emsdk pin: 6.0.10 (2026-09-21), the
  newest tag at least two weeks old (6.0.11 is from 2026-10-02).
  Checked: run r-yzprvcca (attempt 1) stopped with WORKER-BLOCKED,
  `git ls-remote` to github.com:443 denied ("host is not on the allow
  list"); herdr `src/workers/mod.rs:283` starts every worker with an empty
  `network.allowedDomains` and `strictAllowlist`. The run waits in review
  at event 147167 for a retry with the new task.

- [ ] Patch the Bend emitter (`comp.ts`) if the probe shows that flags and [t-3oqripea]
  shims are not enough?
  Options: decide after seeing the blocker inventory | no patches, upstream only
  Decided by the user 2026-10-16 (d-bfbxt6rp): decide after seeing the
  classified blocker inventory in `docs/probe.md`; ask again then.

## Proposed
