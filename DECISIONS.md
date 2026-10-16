# Decisions

Closed TODO items and the decisions made on them, newest last. Durable
architectural decisions go to `docs/decisions/` (AGENTS.md, Rule 5).

## Pinned toolchain (t-3fa5ws5p)

Done 2026-10-16 (run r-yzprvcca). Bend `v2.0.35` (`79df8d9`) is the
shallow submodule `vendor/bend`; Bun `1.4.2` is pinned in `scripts/bend`;
Emscripten is emsdk/SDK `6.0.10` (2026-09-21, the newest tag at least two
weeks old) in `~/.cache/bend-wasm/emsdk-6.0.10`, pinned in `scripts/emcc`,
with `EM_CACHE` in the repository's ignored `.cache/`. Details:
`docs/workflow.md`.

Decided by the user 2026-10-16 (d-6x44i4p5): herdr workers have no network
(empty `network.allowedDomains` with `strictAllowlist`), so the coordinator
does the network steps (the submodule, the SDK download) and a worker does
the rest offline. The SDK lives outside the repository for that reason.

## Emscripten probe (t-jk5jg2zk)

Done 2026-10-16 (run r-x6alm2ho). `probe/run.sh` rebuilds it; the report
is `docs/probe.md`. Both programs emit C and link to wasm32 and wasm64 with
build flags only, but no run matches native: the runtime reserves an 8 GiB
corpus (`comp.ts:5231`) with an address-hinted `mmap` (`corpus_map`,
`comp.ts:5175-5189`), which Emscripten refuses (`EINVAL` for any hint,
`emscripten_mmap.c:106-108`); on wasm32 the 64-bit size is also silently
truncated to 0. `-mtail-call` settles `musttail`. Nine blockers are
classified there (1 and 9 shim-able by flags, 2 to 4 emitter changes, 5 to
8 architectural for a browser page); 5 to 9 come from reading the code, not
from runs. The coordinator checked the `comp.ts` and Emscripten lines.
Whether to patch `comp.ts` goes back to the user (t-3oqripea).
