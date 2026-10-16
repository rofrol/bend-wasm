# Persistent-state spike: library mode (patch 0003)

The question (TODO t-esggsei6, `docs/decisions/0001-wasm-through-a-patched-emitter.md`):
can Bend state live across many calls from a host without the heap
growing, natively and in wasm? Yes, for this program: the heap high-water
mark is flat after warm-up on both.

`run.sh` builds and runs everything; output in `out/` (ignored).

## CLI shape

```sh
scripts/bend P.bend -o P.c --lib init,step,peek
```

One flag on the existing `-o <file>.c` path: the output is still C, only
without `main()`, so `-o`'s extension rule is unchanged and no new output
kind is needed. `--lib` takes exactly one `-o <out>.c`. The C exports:

- `void bend_init(void)`: what `main` does before running main (corpus,
  allocator, one worker and its stack); once.
- `bend_def_<name>(...)` per named def (`bend_def_` because the defs may
  be called `init`). Callable defs are the ones `-o x.mjs` exports to JS.
  U32 is `uint32_t`, F32 `float`, Nat `uint64_t` (up to 2^48-1, else an
  error); any other closure-free datatype is a `uint64_t` handle. Other
  types (functions, open types) stop the emitter with an error naming the
  def and parameter.
- A tuple result (`A & B`, nested ones flattened) returns its first part;
  part i >= 1 goes through a pointer parameter `r<i>` after the def's own.
- An `Array<F32>` crosses as the F32 region (below), never as a C value:
  a parameter of that type has no C parameter, a result part none either
  (the function is `void` when it is the first). At most one each way.
- `float* bend_f32(void)`, `uint32_t bend_f32_len(void)`: the F32 region,
  `BEND_LIB_F32` floats (`-D`, a power of two, default 16,384). A call
  copies the region into the Bend array block the library holds
  (allocated on first use) and the def owns that block; a returned block
  is copied back into the region and held for the next call. So between
  calls the region is the array; an `Array<F32>` result of another length
  fails. `replay/robokill/` uses it for Robokill's `render`.
- `void bend_dispose(uint64_t h)`: drops a handle's value.
- `uint64_t bend_heap_words(void)`: debug, the heap high-water mark in
  words (pages the allocator ever took from the corpus; freed words go
  back to its lists).
- `uint32_t bend_handles(void)`: debug, the number of live handles.

In wasm, add `-sEXPORTED_FUNCTIONS=_bend_init,...`; u64 crosses as BigInt.

## Handles

A handle is a root-table slot (low 32 bits) and its generation (high 32
bits); the slot holds the value's words in the def's own layout and its
type. The terms stay in the corpus, which is mapped once and never reset.

- A handle passed as a `+` parameter (`def peek(+s: State)`) is borrowed:
  the host keeps it with `term_keep` and it stays valid. `+` is Bend's mark
  that the def may copy the value, which only a `Data` type allows, so
  sharing it with the host is what the def's type already permits; library
  mode makes such types "hot" so the def accepts a shared value. When the
  emitter's own lend analysis finds the def only reads the value, the keep
  is skipped.
- Any other handle argument is consumed, Bend's default affine use
  (`def step(s: State, ...)`): its slot dies and the generation moves on.
- A consumed, disposed or never-made handle, or one of another type, fails
  with `bend: <def>: a handle that was consumed, disposed or never made
  (handle 0x...)` and exit 1, as the runtime's own fail-stops do. Consumed
  arguments are taken before borrowed ones, so passing one handle twice
  fails.

Why not borrow by the emitter's analysis alone: it rarely borrows a value
the def reads in full (`peek` reads its whole list and owns it, also in an
ordinary build), and the choice would then change with the def's body.

## Measurements

2026-10-16, `scripts/bend --toolchain`: bend 79df8d9 (v2.0.35), patches
0001-0003, bun 1.4.2, emcc 6.0.10; Node 24.19.0 of the SDK; macOS arm64.

`counter.bend`: `State{n, sum, xs}` with an 8-element list; `step` frees
the list's head and builds a new spine (about 9 cells per call). `init(5)`,
100,000 `step`s with x = 0, 1, ..., a `peek` after every 10,000, then
`dispose`. Native and wasm print the same lines:

| checkpoint | peek | heap words |
| --- | --- | --- |
| init | | 12,416 |
| 10,000 | 577,643 | 16,512 |
| 20,000 | 1,135,435 | 16,512 |
| 30,000 | 620,235 | 16,512 |
| 40,000 | 2,310,571 | 16,512 |
| 50,000 | 568,811 | 16,512 |
| 60,000 | 1,237,195 | 16,512 |
| 70,000 | 3,649,355 | 16,512 |
| 80,000 | 4,538,795 | 16,512 |
| 90,000 | 3,428,075 | 16,512 |
| 100,000 | 1,170,891 | 16,512 |
| disposed | | 16,512 |

The peeks equal counter.bend's own `main` (built natively; the JS lane
takes about 8 ms per step on this program, so it is not used). The mark
does see leaks: 4,000 `init`s disposing every second one grew it by
12,288 words per 1,000.
