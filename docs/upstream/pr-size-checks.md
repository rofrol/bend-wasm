Part of #1598.

`pool_try` passes a `u64` length to `mmap`'s `size_t`. Where `size_t` is 32 bits (wasm32), the CPU corpus's 8 GiB (`1ull << 33`) is truncated to 0. The map then succeeds with a length of 0, and the runtime writes past it.

**Change** (`bend2/comp.ts`): `pool_try` answers `MAP_FAILED` when the length does not fit `size_t`, as if `mmap` had refused the map. Its callers already handle that: `pool_mmap` reports `reservation failed`, `corpus_at` moves on to the next hint, and `corpus_grow` stops growing in place. Where `size_t` is 64 bits, clang removes the check.

On wasm32, `-Wshorten-64-to-32` reports more `u64`-to-`size_t` narrowings in the runtime. I left them alone because none of them can truncate there:
- `corpus_at`'s `munmap` gets a length that `pool_try` has just mapped.
- `pool_stack`'s `ss_size` is `4 * SIGSTKSZ`.
- `io_wait`'s `calloc`/`memset` length comes from the highest parked fd.
- `io_out`'s `fwrite` length and `io_cbuf`'s `malloc`/`realloc` capacity are bounded by a String that is already in the heap. Each cons cell is at least 16 bytes and adds at most 4 UTF-8 bytes. So the buffer is under a quarter of the heap, and its doubled capacity stays under 4 GiB.

**Checked** on 4f99f4c1:
- wasm32, Emscripten 6.0.12, `tests/compile/alias_def.bend`, run in Node, with #<ENV_PR> applied so that it compiles: `RuntimeError: memory access out of bounds` before this change, `bend: reservation failed` (exit 1) after.
- Every test with a `main`, built with `bend t.bend -o t` and run natively (879 build): the same stdout and exit status as main for all of them except `tests/gfx/window`, which counts window events and gives different output from run to run on main as well.
- `bun gates/repo.ts`: 54 / 54. comp.ts is 65,967 ttok on its own (main 65,956). With #<ENV_PR> it is 66,000, exactly the cap; I checked the gate passes on both together.

I did not run the cluster gates.
