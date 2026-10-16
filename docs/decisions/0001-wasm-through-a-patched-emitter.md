# Wasm through a patched emitter

## Context

The user requires a WebAssembly build of Bend programs (decision
d-fus365v2, 2026-10-16), although Bend 2.0.35's JS lane already meets
Robokill's frame budget (p95 1.09 ms for 2,000 bodies against 8 ms;
`DECISIONS.md`, "No comp.ts patch"). Bend has no wasm target. The probe
(`docs/probe.md`) showed that the generated C compiles and links to wasm
with flags alone but does not run: every blocker is in the runtime template
of `vendor/bend/bend2/comp.ts`. Consult round `20261016-125354-86b1` agreed
on the approach below; the coordinator checked its claims against
`comp.ts`.

## Decision

- A separable patch series on the pinned Bend, applied to a cached copy:
  portable limits (unguarded, upstreamable), an Emscripten platform patch
  (wasm32, fixed corpus without in-place growth, explicit stack bound, one
  worker, unsupported IO failing loudly), and a library mode in the emitter,
  each as its own patch. Never edits to generated C. Each patch names the
  upstream change that retires it; the upstream discussion is
  https://github.com/bendlang/bend/issues/1598.
- JS holds opaque generation-checked handles, never raw terms. Render data
  goes through a fixed exported F32 region with memory growth off.
- Persistent state across calls is proven before the game bridge is built:
  a state stepped 100,000 times keeps the heap bounded. Kill criterion: if
  it does not stay bounded, stop and report to the user before any further
  wasm work.
- Conformance gate: identical stdout and exit codes on the differential
  harness, identical state hashes and render bytes on Robokill's replays.
  Robokill switches (its decision 0003) only if wasm is conformant and
  faster than the JS lane.

Steps and checks: `TODO.md`; the plan: `docs/plan.md`.

## Alternatives

- A separate Bend-to-wasm backend: a second compiler to maintain and keep
  semantically equal to Bend's own.
- Waiting for upstream only: no date; the issue stays open for the patches
  to retire into.
- Raw 64-bit terms as JS handles: unsafe once a term moves or is freed.
- Build flags and shim headers only: the probe showed the blockers are in
  the runtime template, and shims would have to fake behaviour.

## Consequences

- The project maintains a patch series that must apply to exactly the
  pinned commit; a pin move means rebasing it.
- Wasm work stops at the persistent-state spike if the heap is not bounded.
- The JS lane stays the production path until the conformance gate and
  Robokill's benchmark say otherwise.
