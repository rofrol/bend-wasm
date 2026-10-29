Part of #1598; fixes the `byval` error reported there in https://github.com/bendlang/bend/issues/1598#issuecomment-6481687363.

The host work-loop segments take `Env e` (two pointers) by value and leave through `musttail` (`WL_JMP`, `WL_DYN`). The wasm32 C ABI passes such a struct as a pointer to a copy in the caller's frame, and a tail call frees that frame before the callee reads it. Emscripten 6.0.12's clang rejects it:

```
error: WebAssembly does not support tail calling with byval arguments
```

Emscripten 6.0.10's clang accepted the same code and miscompiled it silently: the callee read `e.alc` as 0, and `heap_alloc` took free chains from address 0.

**Change** (`bend2/comp.ts`, host only): `WL_SIG` takes Env's two words, `WL_ALL` passes `e.mem, e.alc`, and the host `WL_OPEN` rebuilds `Env e` from them. Segment bodies are unchanged. The device lanes (Metal, CUDA) do not use `WL_SIG`, so their code is the same.

**Checked** on 4f99f4c1, Apple M1 Pro:
- I compiled the C of every test with a `main` (1,611) with `emcc -O2 -mtail-call -c` (Emscripten 6.0.12). The `byval` error hits 872 tests on main and none on this branch, at `-O0` as well. For `alias_def` the `-O2` output has 16 `return_call`s. 7 tests fail on both sides for an unrelated reason: effect sources that do not build for wasm (`process_run`, `random_u32`, `file_open`).
- I built the same tests with `bend t.bend -o t` and ran them natively on main and on this branch. 879 of them build. All of them give the same stdout and exit status on both sides except `tests/gfx/window`, which counts window events and gives different output from run to run on main as well.
- Native arm64 code for `tests/compile/alias_def`, `clang -O3`: same object size and the same instructions. In one segment (`WL_FID_main_out`) they come in a different order: the frame setup moved to the slow path. On arm64 and x86-64 SysV a 16-byte struct already goes in two registers.
- `bun gates/repo.ts`: 54 / 54. comp.ts is 65,989 ttok (main 65,956; cap 66,000).

Compiling does not show that the code runs. The run evidence comes from the downstream series linked in #1598 (https://github.com/rofrol/bend/tree/wasm-2.0.35, patch 0002), which makes the same change on 2.0.35. With it, 51 programs give the same stdout, stderr and exit status on wasm32 as natively.

I did not run the cluster gates (`gates/test.ts`, `gates/perf.ts`). There is no test for this in `tests/`, because it needs a wasm32 compile and the gates don't have one. If you want a check for it, tell me where it should go.
