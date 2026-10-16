# TODO

Plan and context: `docs/plan.md`.

## Next, in order

- [ ] Open the upstream issue at https://github.com/bendlang/bend with the [t-ymygf5au]
  outline in `docs/plan.md`, once the probe has its first errors?
  Decided by the user 2026-10-16 (d-kznksmaz): yes, after the probe; the
  coordinator shows the issue text for approval before posting.

- [ ] Differential test harness: one script builds a corpus native, JS lane and [t-ucc65gif]
  wasm and diffs stdout and exit code; start with at least 20 deterministic
  programs from Bend's own tests; list exclusions with reasons.

## Needs a decision

- [ ] Patch the Bend emitter (`comp.ts`) if the probe shows that flags and [t-3oqripea]
  shims are not enough?
  Options: decide after seeing the blocker inventory | no patches, upstream only
  Decided by the user 2026-10-16 (d-bfbxt6rp): decide after seeing the
  classified blocker inventory in `docs/probe.md`; ask again then.
  Consult round `20261016-124353-d5c1` (sol, mimo, deepseek, wonder; argon
  rate-limited), all four agree: do the JS-lane value check first; if
  patching, one separable patch behind `__EMSCRIPTEN__`, wasm32, a corpus
  size knob with `mmap(NULL)`, no in-place growth (explicit failure on
  exhaustion), `SIZE_MAX` checks on every u64-to-size_t length, a small
  stack with an explicit bound check (Emscripten's `mprotect` is a stub),
  single worker asserted. Also raised: the generated C is a `main()`
  program, while the game needs an exported, re-entrant `step` ABI (wonder,
  sol); Nat as BigInt skews the JS lane (mimo). Coordinator check: Robokill
  has no `step` yet (only `docs/`, `binaries/`, `tools/`), so the value
  check cannot run today.
  Options: wait for the JS-lane value check on Robokill's step | patch now as an experiment, the minimal set above | no patches, upstream only

- [ ] If the probe allows it: a CPU-only single-worker build of the pure [t-xwj7ptut]
  program runs under Node and in a browser page without cross-origin
  isolation, with output identical to the native build.
  Depends on t-3oqripea: the probe shows no run without a `comp.ts` change
  (`docs/probe.md`, blockers 2 to 4).

## Proposed
