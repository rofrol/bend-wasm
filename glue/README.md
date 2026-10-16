# Wasm glue with the JS lane's shape

The question (TODO t-2czhzqqy): can a host swap Bend's JS lane for the
wasm build of the same module by changing one import? Yes for Robokill:
`import G from "./dist/step.mjs"` becomes `import G from
"./dist/step.wasm.mjs"`, and `glue/test/run.sh` drives both through the
same host code with identical output.

## Build

```sh
glue/build.sh MODULE.bend DEFS OUTDIR NAME   # emits C with --lib DEFS first
glue/build.sh FILE.c OUTDIR NAME             # from library-mode C
```

`OUTDIR` gets `NAME.wasm.mjs` (what the host imports), `bend-glue.mjs`
(a copy of `glue.mjs`, the runtime), and the Emscripten build
`NAME.lib.mjs` + `NAME.lib.wasm` (`scripts/wasm-flags`, `-sMODULARIZE
-sEXPORT_ES6 -sENVIRONMENT=web,node`; memory growth off). Outputs are
ignored by git wherever they are built (`glue/out/`,
`bench/robokill/dist/`).

`glue/gen.mjs` writes `NAME.wasm.mjs` from the line patch 0003 writes
above each exported def (`// render: consumes State, Array<F32> from the
F32 region -> a handle of State & Array<F32> into the F32 region`). It
checks that the C parameter list follows from that line and stops on any
form it does not know, so if the emitter changes, the build fails here
and the glue cannot pass arguments wrongly without anyone noticing.

## The shape

The default export has one function per `--lib` def, called as the JS
lane's (Robokill: `init(n, seed)`, `input_at(frame)`, `step(s, inp)`,
`hash(s)`, `render(s, out)`):

- U32 and F32 are numbers (a U32 result is unsigned), a Nat is a BigInt,
  as on the JS lane's boundary.
- A tuple result is `{$: "Tuple", fst, snd}`, nested for more parts, as
  the JS lane returns it.
- Any other value is a `Handle`: a frozen object with private fields (the
  u64 slot and generation, the instance), a `type` name and nothing else.
  The host never sees a raw term or the handle's number. Passing a handle
  to a consuming parameter consumes it, as Bend's affine use says; the
  library refuses a consumed one (below).
- `Array<F32>` is the library's F32 region (`bend_f32()`, 16,384 floats).
  The glue makes a `Float32Array` view of it once at startup (memory
  growth is off, so the view stays valid). `render(s, out)` takes the
  host's `Float32Array(16384)` and returns it as `snd`, filled: after the
  call the glue copies the region into `out`, the one copy per call. The
  library itself copies the region into its array block before the def
  and back after it (patch 0003), inside wasm, and that is counted in the
  frame times below. The glue copies `out` into the region before a call
  only when `out` is not the array the last call filled. A host that
  writes into that array between calls is therefore not seen; Robokill's
  host only reads it.
- The copy is 16,384 floats, 64 KiB. One `Float32Array.prototype.set` of
  that size out of a wasm memory takes 1.1 to 1.3 µs in the SDK's Node
  24.19 on this Mac (`bench/robokill/node-bench.mjs`), about 0.4% of the
  0.31 ms wasm frame at n = 2,000. Robokill uploads only the
  `(n + 256) * 4` floats it uses, but the glue copies the whole array,
  because only the array's length is in the contract, not how much the
  def wrote.

Named exports beside the default: `reset()` (below), `dispose(h)` (drops
a handle the host will not pass on), `timings()` (read, compile,
instantiate and `bend_init` times in ms) and `stats()` (`bend_heap_words`
and `bend_handles`, for leak checks).

Not like the JS lane: the JS lane's garbage collector frees values the
host drops, while here a handle the host drops without consuming or
disposing it keeps its slot (4,096 by default) until the instance goes.
The functions take all their arguments at once (the JS lane also curries).

## Failure rule

A library misuse (a consumed, disposed or foreign handle; a full handle
table; any `bend: ...` fail-stop) and a wasm trap inside a call both
become a thrown JS `Error`:

- a misuse: the library's own message, e.g. `bend: step: a handle that
  was consumed, disposed or never made (handle 0x100000001)`. The
  library's `_exit` reaches the glue's own `proc_exit` import, which
  throws instead of Emscripten's, so the process's `process.exitCode`
  stays untouched in Node;
- a trap: `bend-wasm: <def>: wasm trap: RuntimeError: ...`, with any
  stderr lines before it; `cause` is the original error.

The instance is then poisoned: the call stopped halfway through the
runtime's state, so every later call throws `bend-wasm: the instance is
poisoned by an earlier failure (...)`. Recovery is explicit:
`await reset()` makes a fresh instance from the compiled module (no
recompilation), calls `bend_init` and refuses every handle of the old
instance (`a State handle of an instance before reset()`), because a new
instance numbers its slots from scratch and an old handle could otherwise
name a new value. A fresh import (`import("./step.wasm.mjs?2")`) is a
separate instance too, but `reset()` is the documented way, as the host
keeps its `G`. Each instance has its own 528 MB memory; the old one is
freed once nothing refers to it.

Errors the glue finds before entering wasm (not a handle of this module,
a handle from before `reset()`, a `Float32Array` of the wrong length, a
Nat that is not a BigInt) throw without poisoning, as nothing has run.

## Tests

`glue/test/run.sh` (the SDK's Node, about 40 s) builds Robokill's
`step.bend` (`replay/robokill/`, vendored from Robokill `63031ab`) as the
JS lane and through the glue, and requires:

- `glue/test/replay.mjs`, Robokill's replay protocol written as a host
  (seed 12345, n = 500 and 2,000, 10,000 frames, `step` and `render` into
  a `Float32Array(16384)` each frame, the state hash every 1,000th),
  prints the same 20,022 lines through both lanes: the 22 checkpoints and
  the FNV-1a hash of `out` after every frame;
- those checkpoints equal `replay.bend`'s native output, final hashes
  603820250 and 819172968 as Robokill's RESULTS.md;
- `glue/test/failure.mjs`: argument errors do not poison; reusing a
  consumed handle throws the library's message and poisons; `reset()`
  refuses old handles and the new instance hashes as the first did; a
  forced trap (`glue/test/trap.c`, `__builtin_trap()` in a def appended to
  the same C) throws and poisons; with `BEND_LIB_SLOTS` 4 a fifth `init`
  throws `bend: every handle slot is in use (BEND_LIB_SLOTS)` and poisons;
  a fresh import works beside the poisoned instance; `process.exitCode`
  stays unset.
