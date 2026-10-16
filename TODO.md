# TODO

Plan and context: `docs/plan.md`.

## Next, in order

- [ ] Differential test harness: one script builds a corpus native, JS lane and [t-ucc65gif]
  wasm and diffs stdout and exit code; start with at least 20 deterministic
  programs from Bend's own tests; list exclusions with reasons.
  Decided by the user 2026-10-16 (d-lx22tkg5): start now with native and
  JS lane only; wasm joins once a wasm build runs (t-xwj7ptut).

## Needs a decision

- [ ] If the probe allows it: a CPU-only single-worker build of the pure [t-xwj7ptut]
  program runs under Node and in a browser page without cross-origin
  isolation, with output identical to the native build.
  Depends on t-3oqripea: the probe shows no run without a `comp.ts` change
  (`docs/probe.md`, blockers 2 to 4).
  The JS lane met Robokill's frame budget (DECISIONS.md, "No comp.ts patch"),
  so no patch is approved and wasm is an experiment. Continue the wasm work?
  Options: park it, keep issue 1598 open and resume when a workload misses the JS-lane budget or upstream adds a wasm mode | continue as an experiment with the consult round's minimal patch | drop the wasm target
  Decided by the user 2026-10-16 (d-fus365v2): "wasm is a must; you take
  care of it; ask the models." The coordinator decides the approach after a
  consult round and records it here; a `comp.ts` patch set on the pinned
  Bend is within that mandate (AGENTS.md Rule 6: small, separable, pinned,
  with the upstream change that retires it).

## Proposed
