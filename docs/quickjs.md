# Bend's compiler on QuickJS

Question (TODO t-xz35srdq): does Bend's TypeScript compiler, bundled into
one JS file, run on QuickJS, a small C JavaScript engine that Debian and
Guix build from source, so that emitting C would not need Bun?

Answer: **yes, for emitting C**, with about 200 lines of probe shims over
QuickJS's own `std` and `os` modules. The C it emits for the two programs
tried is byte-identical to `scripts/bend`'s. Bun is still needed to make
the bundle (one `bun build` run, whose output could be checked in or
built once), and the other commands (running a program, building a
binary, `--verdict`, publishing, bundling a page) hit the walls listed
below.

Checked 2026-10-16 on an arm64 Mac (macOS 27.0.1).

## Versions

- Bend `v2.0.35`, commit `79df8d9c40722ee9507a1e253f283b51025f9d6c`, with
  the patch series `d69c06785be794fc` (`0001-portable-limits`,
  `0002-emscripten`, `0003-library-mode`): the copy `scripts/bend` runs.
- Bun `1.4.2+50a8a8387` (the pin), for the bundle and the reference C.
- QuickJS `2026-06-04` (Bellard's release), `quickjs-2026-06-04.tar.xz`,
  sha256 `b376e839b322978313d929fd20663b11ba58b75df5a46c126dd19ea2fa70ad2a`,
  unpacked at `~/.cache/bend-wasm/quickjs-2026-06-04/`; `qjs` built with
  its own Makefile (`make qjs`, about 10 s) and Apple clang 21.0.0.

## Reproducing

`tools/quickjs/run.sh` does all of it in a fresh directory under
`$TMPDIR` and exits nonzero when the C differs or qjs fails
(`QUICKJS_KEEP=1` keeps the directory, `QUICKJS_SRC` points to another
unpacked copy of the release):

1. copies the unpacked release and runs `make qjs` in the copy;
2. `bun build <copy>/bend2/main.ts --target=bun --format=esm` into one
   file, placed next to copies of `base.bend` and `effs/` (the compiler
   finds them in its own directory, `BEND_DIR`);
3. drops the shebang, prepends `import "./shim/globals.mjs";` and points
   every `node:*` import at `tools/quickjs/shim/` (sed): `fs`, `path`,
   `url` and `os` at their shims, `child_process`, `crypto`, `module` and
   `worker_threads` at the empty `missing.mjs`, since the C emit path
   calls none of them;
4. for each program, `scripts/bend <args> -o a.c` and
   `qjs --stack-size 6M --std -m main.mjs <args> -o b.c`, then `cmp`.

The programs: `vendor/bend/tests/run/nat_native.bend` and
`replay/robokill/step.bend --lib init,input_at,step,hash,render`.

A deliberately broken shim (an extra byte in every written file) makes it
print `FAIL ...: the C differs` for both programs and exit 1.

## Choosing the bundle target

| `--target` | size | what is left for the engine |
| --- | --- | --- |
| `bun` (used) | 344 KB | `node:*` imports kept as imports; `import.meta.main` and `import.meta.require` kept |
| `node` | 377 KB | the same imports, plus `import.meta.main` turned into `__require.main == __require.module` (needs CommonJS `require`) and a second copy of `bend.ts` |
| `browser` | 1.3 MB | `node:*` replaced by browser polyfills (fs and child_process empty, `url.fileURLToPath` missing); the compiler cannot read its sources |

`--target=bun` leaves the fewest Bun-only constructs: QuickJS provides
`import.meta.main` and `import.meta.url` itself (`file://` plus the real
path), and the shims replace the `node:*` imports by path.

## Bun-only and Node-only APIs the bundle needs

Each with the command path that needs it. "Shimmed" means the C emit path
calls it and `tools/quickjs/shim/` provides it.

| API | needed by | on QuickJS |
| --- | --- | --- |
| `process` (`argv`, `env`, `exit`, `exitCode`, `platform`) | every command | shimmed, `globals.mjs`, ~15 lines over `scriptArgs`, `std.getenviron`, `std.exit` |
| `typeof Bun` guard in `main.ts` (prints "bend runs on Bun", exits) | every command | shimmed by `globalThis.Bun = {}`; the emit path uses no `Bun.*` member. A real port would patch the guard out |
| `URL` (`new URL(".", import.meta.url)`) | `BEND_DIR` in `bend.ts`, at load | shimmed, that one form only, ~10 lines |
| `node:fs` `readFileSync`, `writeFileSync`, `writeSync` (fd 1, 2), `existsSync`, `realpathSync`, `statSync`, `readdirSync`, `mkdirSync` | reading sources, `base.bend` and `effs/`; writing the output; messages | shimmed, `fs.mjs`, ~90 lines over `std.loadFile`, `std.open`, `os.stat`, `os.realpath`, `os.readdir`, `os.mkdir`; UTF-8 strings only, no `Buffer` |
| `node:path` `join`, `dirname`, `basename`, `resolve`, `delimiter`, `posix` | everywhere | shimmed, `path.mjs`, ~55 lines, POSIX only |
| `node:url` `fileURLToPath` | `BEND_DIR` | shimmed, `url.mjs`, 8 lines |
| `node:os` `homedir`, `tmpdir` | `BEND_LIB` at load | shimmed, `os.mjs`, 10 lines |
| JS stack deeper than 1 MiB | checking and compiling Robokill's `step.bend` (2 MiB fails with `InternalError: stack overflow`, 4 MiB passes) | `qjs --stack-size 6M`, under the default 8 MiB main-thread stack |
| `fs.mkdtempSync`, `fs.rmSync`, `node:child_process` `spawnSync` | building a binary (`-o out`, no extension): emit C to a temp dir, run `cc` | not shimmed (`TypeError: not a function`); a small shim over `os.exec` and `os.remove`, ~30 lines, untried |
| `import.meta.require`, `TextEncoder`/`TextDecoder`, `performance.now`, `bun:ffi` `dlopen` of libc | running a program in-process (`bend f.bend`): `Comp.io_run` evaluates the JS lane with `new Function("require", ...)`; sockets, `select`, `fcntl` and `strerror` go through `bun:ffi` | not shimmed (`ReferenceError: 'TextEncoder' is not defined`). The text APIs and `require("fs")` are small shims; `bun:ffi` is the wall: QuickJS has no FFI, so the IO effects need a C module compiled into `qjs` |
| `node:crypto` `createHash`, `node:child_process` `spawnSync` of `lean` | `--verdict` (hashing and running the BendTT kernel) | not shimmed (`TypeError: not a function`); SHA-256 in JS plus `os.exec`, medium; also needs Lean |
| `fetch`, `crypto.subtle`, `node:crypto` `hash`, `node:worker_threads` `Worker`, `os.availableParallelism`, `os.hostname`, `Bun.spawn` | `--publish`, `login`, `link`, hub imports, the daily version check (off with `BEND_NO_TELEMETRY=1`) | not shimmed; QuickJS has no HTTP client (only `std.urlGet` through the `curl` command) and its workers differ from Node's |
| `Bun.build`, `Bun.plugin`, `node:module` `register` | bundling a page (`bend page.html -o dir`), importing `.bend` from JS | no equivalent; out of scope |

## Results

| program | C bytes | identical | one emit: `scripts/bend` (Bun) | one emit: qjs |
| --- | --- | --- | --- | --- |
| `vendor/bend/tests/run/nat_native.bend` | 87013 | yes | 191–292 ms | 315–332 ms |
| `replay/robokill/step.bend --lib init,input_at,step,hash,render` | 206628 | yes | 399–406 ms | 1512–1532 ms |

Two runs of `tools/quickjs/run.sh`; wall-clock times. The Bun column
includes `scripts/bend`'s own work (`git rev-parse`, hashing the patch
series), so the engine gap is a little larger than the numbers show:
QuickJS, an interpreter, is about 4 times slower on Robokill than Bun's
JIT.

Also tried by hand with the same bundle on `nat_native.bend`:

- `--check-only` prints `ALL PROOFS CHECK`, as on Bun.
- `-o x.bendtt` is byte-identical to `scripts/bend`'s.
- `-o x.js` and `-o x.mjs` run but differ from `scripts/bend`'s at line
  73. Not an engine difference: `comp.ts` splices the source text of
  `Bend.f32_round` (`${Bend.f32_round}`) into the JS runtime, and that text
  is whatever the compiler's own transpiler printed. `bun main.ts`
  constant-folds `2 ** 128` and `Infinity`; `bun build` keeps them. The
  same bundle run on Bun gives exactly qjs's output, so the JS lane's text
  depends on how the compiler is bundled, not on the engine. The C emit
  splices no function source, so it is unaffected.

## What it would take

For the C lane only (what the wasm build uses): the bundle plus these
shims, run with `--stack-size`. To make it a real path rather than a
probe: patch the `typeof Bun` guard instead of faking `Bun`, keep the
bundle (or the bundling step) pinned, size `--stack-size` against the
largest program in the corpus, and run the whole corpus through the
byte-identity check, not two programs. Bun remains needed once to produce
the bundle; `esbuild` or `tsc` could replace it there, untried.
