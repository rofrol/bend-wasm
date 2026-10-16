# Robokill replay through library mode

The question (TODO t-byai25qu): does Robokill's simulation, built in
library mode (patch 0003) and driven from a host, give the same state
hashes and render bytes in wasm as natively, with a bounded heap? Yes:
every checkpoint of both 10,000-frame replays and every frame's render
bytes are equal, and the heap is flat over 1,000,000 frames on both. The
plain-clang build (`docs/clang-wasm.md`) is a third lane, `clang`, with the
same checks.

`run.sh` builds and checks everything; output in `out/` (ignored).

## Inputs

`step.bend` and `replay.bend` are Robokill's `spike/step.bend` and
`spike/replay.bend` at commit `63031ab`, copied unchanged behind one header
line: test inputs, not our code. `ROBOKILL=/path/to/Robokill fetch.sh`
copies them again from that commit and exits 1 when a copy differs (the
fresh copy is left in place for `git diff`). The replay protocol is
Robokill's (`spike/replay.bend`, `spike/replay.mjs`): seed 12345, the state
hash at frames 0, 1,000, ..., 10,000 for n = 500 and n = 2,000; the final
hashes in its `spike/RESULTS.md` are 603820250 and 819172968.

## How the host calls it

`scripts/bend step.bend -o step.c --lib init,input_at,step,hash,render`
gives (patch 0003 header and `probe/lib/README.md`):

```c
uint64_t bend_def_init(uint32_t n, uint32_t seed);   // a State handle
uint32_t bend_def_input_at(uint32_t frame);
uint64_t bend_def_step(uint64_t s, uint32_t inp);    // consumes s
uint64_t bend_def_hash(uint64_t s, uint32_t* h);     // State & U32
uint64_t bend_def_render(uint64_t s);                // State & Array<F32>
```

- A tuple result returns its first part; part i >= 1 goes through the
  pointer parameter `r<i>` (here the hash's U32). Every Robokill def takes
  its State and returns a new handle, so the host threads one handle.
- `render`'s `out: Array<F32>` is the F32 region, `bend_f32()` of
  `bend_f32_len()` floats (`BEND_LIB_F32`, default 16,384, the size of
  Robokill's `Float32Array`): no C argument, no C result. The call copies
  the region into the Bend array block the library holds, `render` writes
  into it, and the block comes back into the region; the library keeps the
  block for the next call. Between calls the region is the array, as the
  JS lane's typed array is: the host reads it in place (and could write it).
- In wasm, `replay.mjs` makes one `Uint32Array` view of the region and one
  4-byte `_malloc` for the hash at start; memory growth is off, so neither
  changes and nothing is allocated per frame on the JS side.

## Checks (`run.sh`)

The drivers `replay.c` (native, clang -O3) and `replay.mjs` (the SDK's Node
on the `scripts/wasm-flags` build, and on the plain-clang build of
`tools/clang-wasm/build.sh` through `tools/clang-wasm/node.mjs factory`)
link the same `step.c`. Per frame they
call `step` and `render` and print an FNV-1a hash of the region's 32-bit
words; at the checkpoints they call `hash` and print its line exactly as
`replay.bend` does. `run.sh` builds `replay.bend` natively as the
reference and requires: checkpoint lines equal for `replay.bend`, native
and wasm; the final hashes of `RESULTS.md`; render hashes equal natively
and in wasm on all 20,000 frames. On a difference it prints the first
differing frame with both values and stops.

Heap bound, n = 500, `step`, `render` and `hash` every frame, 100,000 and
1,000,000 frames on every lane (`BOUND_FRAMES`, `BOUND_WASM`,
`BOUND_CLANG`): the
allocator's high-water mark and the live handle count at every tenth; the
last may not exceed the first (after warm-up).

## Measurements

2026-10-16, `scripts/bend --toolchain`: bend 79df8d9 (v2.0.35), patches
0001-0003, bun 1.4.2, emcc 6.0.10; Node 24.19.0 of the SDK; Apple arm64
Mac (inside a herdr worker's sandbox).

- Replay: 22 checkpoints equal on all three, final hashes 603820250 and
  819172968, render hashes equal on 20,000 frames. Wall times of two runs
  (the machine was shared, so they vary): `replay.bend` 2.2 and 3.9 s,
  native driver 2.8 and 8.7 s, wasm driver 4.4 and 23.8 s (both drivers
  also render and hash 64 KiB every frame).
- Heap bound: 39,040 words of high-water and 1 live handle at every
  checkpoint, from frame 10,000 (100,000 frames) and 100,000 (1,000,000
  frames) on, natively and in wasm. Wall times of the same two runs:
  native 5.2 and 18.6 s (100,000), 44.1 and 67.3 s (1,000,000); wasm 20.4
  and 12.9 s, 114.5 and 95.7 s. The 1,000,000-frame run stays under a
  minute and a half natively, so it runs in wasm too.

2026-10-17, the same toolchain with patch 0004 and the plain-clang build
(`docs/clang-wasm.md`), one run in the worker sandbox: all three lanes'
checkpoints and render hashes equal; 39,040 words and 1 handle at every
checkpoint of 1,000,000 frames on the clang lane too. Wall times (a shared
machine): replay wasm 12.0 s, clang 14.0 s; 1,000,000 frames native
73.8 s, wasm 197.3 s, clang 213.7 s. The whole script took 9.5 minutes.
