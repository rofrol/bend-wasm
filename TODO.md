# TODO

Plan and context: `docs/plan.md`.

## Next, in order

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

- [ ] Patch the Bend emitter (`comp.ts`) if the probe shows that flags and [t-3oqripea]
  shims are not enough?
  Options: decide after seeing the blocker inventory | no patches, upstream only
  Decided by the user 2026-10-16 (d-bfbxt6rp): decide after seeing the
  classified blocker inventory in `docs/probe.md`; ask again then.

## Proposed
