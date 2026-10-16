# Differential test: native vs JS and wasm lanes

`tests/differential/run.sh` builds every program in `corpus.txt` on each
lane and compares its stdout and exit code byte for byte with the native
lane (`docs/plan.md`, "Correctness and value checks"). It is the herdr check
`differential` (`.herdr/checks.toml`).

```sh
sh tests/differential/run.sh
```

It prints one line per program and lane (`ok`, `DIFFERS`, `FAILED` with the
reason, `not available`) and a summary, writes everything to
`tests/differential/out/` (ignored), and exits 0 only when every program
matched native on every available lane.

The native and JS lanes build a program as Bend's own gate does
(`vendor/bend/gates/test.ts`); all lanes go through `scripts/bend`:

| Lane | Build | Run |
| --- | --- | --- |
| native | `scripts/bend P -o P.bin` (clang `-O3`) | `./P.bin` |
| js | `scripts/bend P -o P.js` | `bun P.js`, the Bun `scripts/bend` pins, with the gate's `BUN_JSC_maxPerThreadStackUsage` |
| wasm | `scripts/bend P -o P.c`, then `scripts/emcc $(scripts/wasm-flags) P.c -o P.js` (the probe's `w32-patched` target: wasm32, `-mtail-call`, fixed 528 MB memory; `docs/probe.md`) | `node P.js`, the Node of the pinned Emscripten SDK |

The wasm lane needs patches 0001 and 0002: under `BEND_PATCH=0` it reports
`not available` for every program, and the run compares native and JS
only.

A lane is a name in `lanes` plus its `lane_build_<name>` and
`lane_run_<name>` functions in `run.sh`. Each run has a 5 s hang guard,
mirroring Bend's own gate for the same non-`!` programs
(`vendor/bend/gates/test.ts:136`); it only stops a program that never ends,
which then counts as FAILED with "timeout".

## How the corpus was picked

Bend's tests end in the `#|` lines their run must print; the gate builds a
test for the C and JS lanes when it has `import Base` and a `def main`, has
no foreign import without a twin for the lane, and is not expected to fail
its check. From the directories whose tests carry such output (`run/`,
`eval/`, `io/`, `reg/`), every test that met those rules and used no GPU
`!(`, no files in `/tmp`, and none of `IO.sleep`, `IO.now`,
`IO.random_u*`, `IO.spawn`, `IO.get_env`, `IO.args`, `IO.write` was tried
on 2026-10-16 (Bend v2.0.35, Bun 1.4.2, Apple clang 21, in herdr's worker
sandbox): 262 programs. 238 matched native on the JS lane. The corpus
keeps 51 of them that cover the plan's list: arithmetic and `Nat`, F32,
ADT matching and affine frees, recursion, shared values and reference
counts, strings, IO with fail-stops (non-zero exits), and a foreign effect
with a C and a JS twin.

F32 output is compared byte for byte, like everything else. A program that
differs only in F32 formatting or NaN goes to the exclusions with its diff;
the comparison is not loosened. All four F32 programs in the corpus match.

## Exclusions

Every tried program that is not in the corpus:

- Differs, native vs JS (a finding; may be a Bend bug):
  - `io/process_run.bend`: the JS lane prints
    `inherited pipe: unexpected failure` and
    `descendant output: unexpected failure` where native and the test's
    `#|` lines say `True` (the cases `sh -c "sleep 3 & echo hi"` and
    `sh -c "yes & echo hi"` with a 1500 ms timeout: a descendant keeps the
    output pipe open). Reproduced twice, in herdr's worker sandbox only;
    it also spawns processes and depends on wall-clock timeouts.
- Need network or local sockets (in the sandbox both lanes fail alike, so
  they matched without testing anything): `io/tcp_bytes`,
  `io/tcp_listen_backlog`, `io/tcp_listen_close`, `io/tcp_loopback`,
  `io/tcp_recv_max_zero`, `io/tcp_short_recv`, `io/udp_bad_address`,
  `io/udp_loopback`, `io/udp_send_recv`, `io/udp_truncate`,
  `io/port_bound`, `io/server_bind_host`.
- Spawn processes: `io/process_run_parallel`.
- `main` cannot be built (the compiler refuses to print a function, a
  `Type` or an erased field; Bend's gate only checks and interprets these):
  `run/harness_cache_compile_double`, `run/harness_cache_purity_grow`,
  `run/harness_cache_purity_shrink`, `run/harness_cache_stats_flip`,
  `eval/efq_arm_value`, `eval/eta_expand_print`,
  `eval/float_builtin_print`, `eval/forall_type_print`,
  `eval/hoas_binder_refresh`, `eval/io_effect_tree`,
  `eval/nat_literal_roundtrip`, `eval/neq_unfold`,
  `eval/open_closure_pipe`, `eval/partial_app_snf`,
  `eval/printer_fixpoint`, `eval/printer_fresh_binder_pick`,
  `eval/stuck_rewrite_print`, `eval/stuck_split_mint`,
  `eval/toplevel_ref_print`, `eval/underscore_print`,
  `eval/wildcard_chain_print`, `io/readback_sugars`,
  `reg/interp_arm_share`.
- Depend on the machine rather than the program (signals, thread count,
  an audio device), so the wasm lane could not match them: `io/select_eintr`,
  `io/thread_count`, `io/confluence_threads`, `io/audio_only_open`,
  `io/audio_only_write`, `io/audio_only_close`.
- Wasm lane only, unsupported effects: patch 0002 makes the wasm target
  stop with an error at helper-thread effects (files, processes, random
  numbers: `bend: blocking effects (files, processes, random numbers) are
  not supported on this target (wasm)`), timer and stream waits (`bend:
  waiting on a timer or a stream is not supported on this target (wasm)`)
  and sockets (`bend: sockets are not supported on this target (wasm)`).
  No program of the corpus reaches one: on 2026-10-16 all 51 matched
  native on the wasm lane, so none is excluded for it.
- Matched, left out only to keep the check short: the other 168 matching
  programs of `run/`, `eval/`, `io/` and `reg/`. To try them again, add
  their paths to `corpus.txt`.

Not tried, by the rules above: tests with GPU `!(`, a foreign import with
only a JS twin (the native lane cannot build them), files in `/tmp`,
`IO.sleep`, `IO.now`, `IO.random_u*`, `IO.spawn`, `IO.get_env`, `IO.args`
or `IO.write`, and tests without `import Base` or a `def main`.
