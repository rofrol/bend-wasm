# Corpus layout audit for a CPU-sized wasm build

TODO t-ap3q3hvo, read-only. This report changes no code. It answers what
patch t-xes4fk35 (wasm memory) needs to know. The 536 MiB tab is described
in TODO.md and in DECISIONS.md, "Wasm module, glue and benchmark".

Line references are to the patched copy that `scripts/bend` builds,
`.toolchain/79df8d9c40722ee9507a1e253f283b51025f9d6c-29bf2961ef35fa51/bend2/comp.ts`
(the Bend pin plus patches 0001 to 0003). In this region the unpatched
pin's lines are about 400 lower: TODO.md's "3462-3497" are the pin's
lines for the patched 3862-3899.

Toolchain of every measurement: `bend 79df8d9`, patches `29bf2961ef35fa51`
(0001, 0002, 0003), bun 1.4.2, emcc 6.0.10, the SDK's Node v24.19.0, Apple
M1 Pro, macOS (16 KiB pages).

## Summary

- On the CPU, two of the corpus's four lane areas are never touched. The
  per-lane allocator rows (`ALC_OFF`, 8 MiB) and stacks (`STAK_OFF`,
  256 MiB) are the device's. The host keeps its allocator rows in the
  static `ALC[w]` and its Term stacks in `pool_stack` mappings. The rings
  (128.25 MiB) are used only by programs with `!` forks (`BANGS != 0`).
  Robokill, the counter, `probe/hello` and the 51 differential programs
  have no `!` forks.
- A run touches very little of the corpus. Robokill at n = 2,000 over
  10,000 frames touches 0.33 MiB resident natively, and 0.38 MiB of the
  corpus holds a non-zero word in wasm. Of the 528 MiB linear memory,
  1.06 MiB holds a non-zero byte.
- Layout offsets never reach output, state hashes or render bytes.
  Locations are word indices from the corpus base, and nothing prints or
  hashes them. A smaller layout does not change Robokill's hashes; it
  changes only when `ERR_HEAP` and `ERR_RING` fire.
- The runtime needs zeros only in the header words `[0, ALC_OFF)` and in
  the rings' get/put words, plus the slot lap bits once more than one
  thread runs. A fresh corpus with any other byte pattern elsewhere gives
  identical results. So a corpus from fresh linear memory without a
  memset is safe.
- New finding (a bug in patch 0001 on wasm32): `corpus_map` casts its
  address hints `1 << 45` down to `1 << 32` to a 32-bit pointer, so each
  of them becomes NULL. Emscripten's `mmap(NULL)` then succeeds, the
  result differs from the hint, and the runtime unmaps it and halves the
  hint. `bend_init` therefore maps, zeroes and unmaps 512 MiB 14 times
  before the final map: 15 successful 512 MiB maps, 7,688 MiB zeroed in
  all with the stack. That is all of `bend_init`'s 140 ms in Node, and
  the cause of the 134 to 344 ms load seen in Chrome.
- A prototype in scratch space served every `mmap` from a static `.bss`
  arena. It needed no memset, no hint loop and no patch to `comp.ts`.
  Node's RSS fell from 567 MiB to 47 MiB after `bend_init` and from
  573 MiB to 53 MiB after the replay (bare Node: 42 MiB). `bend_init`
  fell from 140 ms to 0.0 ms. The hash stayed 819172968.
- Recommended order for t-xes4fk35: first (b), the corpus from `.bss`
  with the hint loop skipped on 32-bit pointers. It is a few lines and
  fixes the resident size and the load time without changing the layout.
  Then (e), a host layout under `__EMSCRIPTEN__` without the device areas
  and with rings only when `BANGS != 0`. It shrinks the reservation and
  `INITIAL_MEMORY`: Robokill's minimum corpus becomes about 331 KiB
  before headroom, against 409.5 MiB today. (a), a smaller `CUBE_T`, is
  not recommended: it changes the `!` schedule and breaks a hidden
  coupling (`RING_WORDS`).

## 1. The layout constants on the CPU path

### Definitions (3862-3912)

| Name | Value | Line |
| --- | --- | --- |
| `LINE` | 16 | 3862 |
| `PAGE_BITS`, `PAGE_LEN` | 7, 128 words | 3863-3864 |
| `CUBE_T` | 128 | 3865 |
| `CUBE` | `CUBE_T * CUBE_T` = 16,384 | 3866 |
| `CUBE_G` | `1 << CUBE_LOG` = 128 on the host | 3867 |
| `LANES` | `CUBE_T << CUBE_LOG` = 16,384 on the host | 3868 |
| `RING_LOG`, `RING_LEN` | `17 - CUBE_LOG` = 10, 1,024 | 3869-3870 |
| `STAK_LEN` | 2,048 | 3871 |
| `RING_WORDS` | `(1 << 10) + 2` = 1,026, fixed | 3884 |
| `H_BUMP`, `H_CAP`, `H_CURSOR`, `H_ROOT_DONE`, `H_ERROR_CODE`, `H_ROOT_WORD`, `H_BANK` | 0, 1, 16, 32, 48, 64, 64 + `WL_RESW` | 3886-3892 |
| `PAGE_UP(n)` | round up to 128 words | 3894 |
| `ALC_OFF` | `PAGE_UP(H_BANK + 3 * NCLS_ALL)` = 256 for `WL_RESW` <= 96 | 3895 |
| `RING_OFF` | `ALC_OFF + CUBE * 2 * NCLS_ALL` = 1,048,832 | 3896 |
| `STAK_OFF` | `RING_OFF + CUBE * RING_WORDS` = 17,858,816 | 3897 |
| `STAT_OFF` | `STAK_OFF + CUBE * STAK_LEN` = 51,413,248 | 3898 |
| `HEAP_OFF` | `STAT_OFF + PAGE_UP(STAT_LEN)` | 3899 |
| `ALC` (host) | `static u64 ALC[CUBE_T + 1][3 * NCLS_ALL]` | 3910 |
| `CUBE_LOG` (host) | `static u32 CUBE_LOG = 7`; only CUDA changes it (5408) | 3912 |

`CUBE_LOG` is a `-D` constant on the device (3904) and a variable on the
host. Only `gpu_init` for CUDA sets it, to 4..7 (5408). On the CPU path it
is always 7, so `LANES == CUBE` and `RING_LEN == 1024`.

There are no `STAT_*` names beyond `STAT_LEN` (2852), `STAT_IMG` (2873)
and `STAT_OFF`. No `PAGE_*` names beyond `PAGE_BITS`, `PAGE_LEN` and
`PAGE_UP`.

### Uses on the host, by name

- `PAGE_BITS`/`PAGE_LEN`. A heap page is 128 words. The bump counter
  `H_BUMP` counts pages (u32): `heap_alloc_miss` takes `pages = (n << cls)
  >> PAGE_BITS` and returns `HEAP_OFF + (p << PAGE_BITS)` (4198-4205).
  `bend_heap_words` returns `H_BUMP << PAGE_BITS` (3185), a count that
  does not depend on the layout. `QUANTUM` (3879) is
  `min(KEEP_WORDS, 32 * PAGE_LEN)` = 4,096 words on the host. `PAGE_UP`
  needs `PAGE_LEN` to be a power of two (it masks).
- `CUBE_T`, as a row width.
  - `row_grow` visits `CUBE_T` rings `base + i * stride` (5043-5067).
  - `ring_pick` masks with `CUBE_T - 1` (4630), so `CUBE_T` must be a
    power of two.
  - `ring_flip(i) = (i % CUBE_T << CUBE_LOG) + i / CUBE_T` (4626-4628) is
    a bijection on `[0, LANES)` exactly because `LANES = CUBE_T <<
    CUBE_LOG`.
  - `pool_step` computes `CUBE_T >> (31 - CLZ(min(per, LINE)))` (5134-5137)
    and `cube_run` computes `want = (pool_size - 1) / (CUBE_T / LINE) + 1`
    (5582). Both need `CUBE_T >= LINE`, or they shift to 0 or divide by
    zero.
  - `pool_rows` (5139-5168) and `pool_turn` (5229) claim rows through
    `pool_row`, packed as turn << 24 | grow << 23 | rows << 15 | r. That
    needs rows <= 255, so `CUBE_G` <= 128 here, and r < 32,768.
  - `pool_size` is capped at `CUBE_T` (5703), and `ALC` has `CUBE_T + 1`
    rows.
- `CUBE`. Each lane area holds `CUBE` lanes (3896-3898). On the host
  `cube_run` skips the grow turn once the frontier reaches `CUBE`
  (`if (f < CUBE)`, 5587). `corpus_lay` requires `cap > CUBE` (5645).
- `CUBE_G`. It is the number of rows. `cube_run`'s column grow walks the
  row heads 0, 128, 256, ... (`row_grow(..., 0, CUBE_G, want)`, 5584).
  `pool_turn` caps a turn at `CUBE_G` rows (5225), and so does
  `ring_rewind` (5550). It is also a GPU grid size (5275-5277).
- `LANES`.
  - `ring_word(H, r, w) = H + RING_OFF + w * LANES + r` (4606). The ring
    area is transposed: word w of every ring is contiguous, and one ring's
    words are `LANES` words apart.
  - `task_deal` deals a join's children to `ring_flip(g & (LANES - 1))`
    with g from the shared cursor `H_CURSOR` (4669-4691). So `LANES` must
    be a power of two.
- `RING_LEN`, `RING_LOG`. The slot mask is `p & (RING_LEN - 1)` (4607)
  and the lap bit is `~(pos / RING_LEN) & 1` (4612). `ring_push` posts
  `ERR_RING` when `pos - get >= RING_LEN` (4617). `ring_rewind` keeps a
  ring's pending tasks in `Term keep[RING_LEN]` on the C stack (5549):
  8 KiB at `RING_LEN` 1,024.
- The ring's two extra words. Words `RING_LEN` and `RING_LEN + 1` of each
  ring are its get and put counters, a u32 in the low half of each u64
  word (`ring_get`, `ring_put`, 4608-4609). They are not sentinels.
  `RING_WORDS` is `RING_LEN + 2` for `CUBE_LOG` 7, written as a literal.
  The area reserves `CUBE * RING_WORDS`. The rings actually use
  `LANES * (RING_LEN + 2) = 2^24 + 2^(8 + CUBE_LOG)` words, which fits for
  every `CUBE_LOG` <= 7. The total ring capacity is `2^24` slots whatever
  `CUBE_LOG` is: lowering `CUBE_LOG` makes fewer, longer rings and saves
  nothing.
- `STAK_LEN`, `STAK_OFF`. Device only: `stk = H + STAK_OFF + me` (4958),
  and the device's `WL_ROOM` checks against `STAT_OFF` (3793). The host's
  Term stack is `pool_stack` (5093-5119), a separate mapping of
  `BEND_STACK_BYTES`, one per thread (`io_stk` for main and library mode,
  5175 for pool threads). Under Emscripten `WL_ROOM` checks `stk_end`
  (3784-3790).
- `ALC_OFF`. Device only: `Env e = { H, H + ALC_OFF + me }` (4957), with
  `LANE_STEP = CUBE` strides (3764, 4161). The host's `Env.alc` is
  `ALC[w]`, a static row per worker: `ALC[0]` in `corpus_eval` (5708),
  `lib_env` (3109-3114), `pool_turn` (5232) and `cube_run` (5584), and
  `ALC[w]` for pool thread w (5175). CUDA zeroes `[0, STAK_OFF)` with
  `cuMemsetD8` (5693).
- `STAT_OFF`. The static image is copied in at `STAT_OFF` (5698). The
  emitter writes static literals as `term_ctr(cid, STAT_OFF + at)` (1056),
  so `STAT_IMG` holds `STAT_OFF`-relative constants, fixed at compile time.
- `HEAP_OFF`.
  - The heap's base: the first page is `HEAP_OFF + (1 << 7)`, since
    `H_BUMP` starts at 1 (5699).
  - On exhaustion `heap_alloc_miss` posts `ERR_HEAP` and returns
    `HEAP_OFF` as a dummy location (4203). Page 0 of the heap is that
    scratch page.
  - `term_triv`: a location below `HEAP_OFF` is static and is never
    counted or freed (4276). `spare_free` frees only `>= HEAP_OFF` (4238),
    and the emitter's spare reuse tests `>= HEAP_OFF` (1063).

### Lane indexing: by worker or by task

- Allocator rows: by worker on the host (`ALC[w]`). By device lane in
  `[ALC_OFF, RING_OFF)`, which the host never touches.
- Term stacks: by worker on the host (`pool_stack` per thread). By device
  lane in `[STAK_OFF, STAT_OFF)`, which the host never touches.
- Rings: by task. `task_deal` maps the cursor value g to ring
  `ring_flip(g)`. The grow turns walk rows. Any worker drains any row it
  claims from `pool_row` (5139-5168), so one CPU worker uses many rings.
  Measured with one thread (`--threads 1`, natively): `tests/run/array_fork`
  and `tests/run/stencil3d` left slots in 28 rings (highest index 142,
  slot depth at most 3), and `tests/run/fork_leaf_result_loop` in 6 rings.
- One worker therefore uses many rings, one stack (outside the corpus) and
  one allocator row (outside the corpus).

### When the rings are used at all

`corpus_eval` runs `work_loop(e, io_stk, t, !BANGS && pool_size == 1)`
(5711). `BANGS` is the number of `!`-marked references (2853, 1377).

- With `seq` set, a fork runs its branches in sequence: the emitter puts
  the task-making code behind `if (!seq)` (2527 in `emit_fork`; 2055-2056
  in `emit_jump`). `work_loop` then never returns a join, and `task_deal`
  and `cube_run` (5739-5741) are never reached.
- On wasm, patch 0002 forces one thread. Library mode calls
  `corpus_setup(false, 1, 0)` (3120). So the rings are untouched unless
  the program has a `!` fork. Measured below: 0 non-zero ring chunks for
  hello, the counter and Robokill.

### `+ 10` and `> CUBE` in `corpus_lay` (5642-5658)

```c
cap = (span - HEAP_OFF) / (PAGE_LEN + 10)   // heap pages that fit
if (cap <= CUBE) fail("the GPU span is under the rings, stacks and a page per lane")
```

- `+ 10`: the 32 per-class banks sit above the heap pages, at
  `HEAP_OFF + cap * 128`. Bank c gets `2 * (cap >> (max(c, NCLS) - 7))`
  entries (5654). That is about cap for each of the 8 classes below
  `NCLS`, and cap + cap/2 + ... < 2 cap for classes 8 to 31, so less than
  10 cap words in all. Each heap page therefore costs 128 + 10 words. The
  factor 2 is the device's double buffering of a bank (pops below `rd`,
  pushes above `top`, 4120-4121). The bank arrays are sized so that they
  cannot overflow, and `bank_push` (4142-4150) has no bound check.
- `> CUBE`: at least one heap page per device lane, as the error text
  says. It is a GPU requirement, but it is checked on the CPU too. With
  today's offsets it is the whole reason for the 409.5 MiB minimum (patch
  0002's header has the arithmetic): `span >= HEAP_OFF + 16,385 * 138`
  words.
- `cap` is also clamped below `2^32 - 1` (5648), because `H_CAP` and
  `H_BUMP` are u32 page counts.

### Can `CUBE_T`/`CUBE_LOG` be smaller for a one-worker CPU build without changing results?

- `CUBE_LOG`: yes, but it saves nothing. Total ring capacity stays `2^24`
  slots, and it changes `ring_flip`'s order. `ring_rewind`'s
  `keep[RING_LEN]` then grows to 64 KiB at `CUBE_LOG` 4, which is all of
  Emscripten's default C stack (`STACK_SIZE` 64 KiB).
- `CUBE_T`, for programs without `!` forks (Robokill, the counter, the
  differential corpus): yes. The rings are never used, so only offsets
  change, and offsets are not observable (part 2). The constraints are
  that it stays a power of two and `>= LINE` (16), and that `RING_WORDS`
  follows. With `CUBE_T` 16 and `CUBE_LOG` 7, `LANES` (2,048) would exceed
  `CUBE` (256) and the rings would overrun the stack area. So `CUBE_LOG`
  must drop to <= log2 `CUBE_T`. Then `RING_LOG = 17 - CUBE_LOG` grows
  `RING_LEN` to 8,192 while `RING_WORDS` stays 1,026, and
  `LANES * (RING_LEN + 2)` (2,097,664 words) overruns
  `CUBE * RING_WORDS` (262,656). The literal `RING_WORDS` and the `17` in
  `RING_LOG` both assume `CUBE_T` 128.
- `CUBE_T`, for programs with `!` forks: the results of pure code stay the
  same, but three things change.
  - The schedule: row width, `ring_flip`'s order, and the `f < CUBE` grow
    bound. So does the order of F32 atomic adds (`A32_LOOP(fadd, ...)`,
    4115, as in `tests/run/array_atomic_fadd.bend`), whose sums may
    differ in the last bits.
  - The `ERR_RING` threshold.
  - Native runs (several threads by default) already schedule
    differently from wasm (one thread), and the differential corpus leaves
    `!` programs out.

## 2. Can a layout offset reach observable output?

No, for every path checked.

- A term's location is a word index from `CORPUS` (`H[loc]`), never a
  machine address. A different corpus base gives the same terms: wasm
  runs at base 0x30000 to 0xb0000 and natively at `2^45` with identical
  output.
- Printing (`show_val`, 6225 on) follows locations to values and prints
  only values. A packed (`TAG_PAK`) payload is a value. Library handles
  are slot | generation << 32 (3085-3152), not locations. Error messages
  name handles and codes. Host IO handles (`io_hand`, 5771) carry host
  fds or pointers, opaquely, and are never printed. No pointer
  comparison decides a value.
- Hashes and render bytes are computed by Bend code (Robokill's
  `step.bend`) over values, and by the drivers over the F32 region's
  contents.
- `bend_heap_words` (3183-3186) counts pages. It depends on `PAGE_BITS`,
  `QUANTUM` and `KEEP_WORDS`, not on any offset. The replay's heap-bound
  output (39,040 words) stays the same if those stay the same.
- What does change with the layout is when a run fails: `ERR_HEAP` once
  `cap` pages are used (4200-4203), and `ERR_RING` for `!` programs. Both
  are by design and must be tested at the new size.

Evidence: Robokill gives hash 819172968 at n = 2,000 and frame 10,000
(RESULTS.md's value) in five runs.

- Natively with an 8 GiB corpus (cap 7,408,178 pages).
- Natively with a 512 MiB corpus.
- In wasm with a 512 MiB corpus at base 0x90000 (cap 113,736).
- In the `.bss` prototype at base 0x70000.
- With garbage-filled spare regions (part 3).

So a smaller layout would not change Robokill's replay hashes.

## 3. What the runtime assumes is zero

A fresh `mmap` is zero natively. Emscripten's `mmap` is
`memalign + memset` (TODO.md's analysis). Nothing in the runtime ever
resets the corpus. In library mode it is mapped once (patch 0003). The
glue's `reset()` re-instantiates the module (`glue/glue.mjs:11`), which
gives a new, zero memory. `corpus_grow` (native only) maps new pages.

| Region | Must start zero? | Why |
| --- | --- | --- |
| `[0, ALC_OFF)` header | yes | `H_CURSOR`, `H_ROOT_DONE` and `H_ERROR_CODE` are read before any write. The bank records (`off`, `rd`, `wr`, `top`; 4123) are too: `corpus_lay` copies `b->wr` words from `b->off` (5652), and `bank_pop` tests `rd` (4129). `H_BUMP` (5699), `H_CAP` (5657) and `H_ROOT_WORD` are written first. |
| ring get/put words | yes, when the rings are used | `ring_push` and `monk_step` compare them (4615-4623, 4851-4861). `ring_rewind` skips a ring whose get is 0 and resets both (5551-5562). |
| ring slots | only with more than one thread or on the device | A reader may see `put` move before the slot is stored. The lap bit in the high word (4612, 4623, 4858) rejects a stale slot, which needs unwritten slots to have bit 31 clear on the first lap. With one worker the push precedes every read of the slot. `ring_rewind` clears the high words it frees (5559-5561). |
| `[ALC_OFF, RING_OFF)`, `[STAK_OFF, STAT_OFF)` | device only | Never touched on the host (part 1). CUDA zeroes `[0, STAK_OFF)` (5693). Metal relies on fresh memory. |
| `[STAT_OFF, HEAP_OFF)` | no | Copied from `STAT_IMG` (5698). |
| heap pages | no | A fresh quantum's free chain is written before use (4206-4208). Every allocation writes its words, since a reused block already holds stale words. |
| bank arrays | no | Written at `wr` before being read below it. |

Experiment (scratch driver, below). A debug build filled the given
regions of a fresh 512 MiB corpus with 0xA5 bytes right after its `mmap`.

- `GARBAGE=1`: everything except the header and the rings, so the
  allocator rows, stacks, static area, heap and banks.
- `GARBAGE=2`: the same plus every ring slot word, but not the get/put
  words.

These programs gave output identical to the clean build in both modes:
`probe/hello`, `tests/run/array_fork`, `tests/run/fork_leaf_result_loop`
and `tests/run/stencil3d` (`!` programs, `--threads 1`), the counter
(peek 1170891), and Robokill (n = 2,000, 10,000 frames, hash 819172968).

Negative controls show that the probe can fail:

- Garbage in the header (`GARBAGE=3`): hello and stencil3d crash
  (SIGSEGV, exit 139).
- Garbage in the put words (`GARBAGE=4`): stencil3d stops with "bend:
  runtime fail-stop". Hello passes, since it uses no rings.

Conclusion: a corpus from fresh linear memory without a memset is safe,
provided the memory has never been used before. Wasm memory is zero at
instantiation by the spec. Memory that malloc handed out and took back is
not zero: the hint loop's unmapped 512 MiB blocks go back to Emscripten's
allocator. So the corpus must not come from `memalign` without a memset.

## 4. How much of the corpus a run touches

The method is a scratch driver in the worker's temp dir, not committed. It
`#include`s the emitted C, so `CORPUS`, `corpus_size` and the layout
macros are visible. After the workload it reports each region `[0,
ALC_OFF)`, `[ALC_OFF, RING_OFF)`, `[RING_OFF, STAK_OFF)`, `[STAK_OFF,
STAT_OFF)`, `[STAT_OFF, HEAP_OFF)`, the heap pages, the banks, and the
whole corpus.

- Natively, residency by `mincore`, taken before any scan reads the
  memory.
- In both, the 64 KiB chunks that hold a non-zero word.
- In wasm, also the 64 KiB pages of the whole linear memory that hold a
  non-zero byte, and Node's `process.memoryUsage().rss`.

The workloads:

- hello runs as `main`.
- The counter does init(5) and 100,000 steps, as `probe/lib/drive.c`.
- Robokill does init(2000, 12345), 10,000 frames of step and render, then
  a hash.

The native builds use clang -O2 and the default 8 GiB corpus. The wasm
builds use `scripts/emcc $(scripts/wasm-flags)` with `-std=gnu11` for
`EM_ASM`.

| Run | Heap high-water | Corpus touched natively (resident) | Corpus non-zero, wasm | Linear memory non-zero, wasm |
| --- | --- | --- | --- | --- |
| `probe/hello` | 97 pages (12,416 words) | 0.12 MiB | 0.19 MiB (3 chunks) | 0.62 MiB of 528 |
| counter | 129 pages (16,512 words) | 0.16 MiB | 0.25 MiB (4 chunks) | 0.75 MiB of 528 |
| Robokill n = 2,000 | 305 pages (39,040 words) | 0.33 MiB | 0.38 MiB (6 chunks) | 1.06 MiB of 528 |

In all three runs the allocator-row, ring, stack and bank areas held no
non-zero chunk, and natively no page of them was resident. The page count
includes the stack at the edge of `[0, ALC_OFF)`; resident pages at a
region's edge are 16 KiB pages that it shares with its neighbour. The `!`
programs at one thread touched 2 to 3 ring chunks (0.12 to 0.19 MiB):
slot 0 to 2 of their rings, which in the transposed layout are the area's
first `LANES`-word rows.

Node RSS and `bend_init` time for Robokill (wasm):

| Build | `bend_init` | RSS after init | RSS after replay |
| --- | --- | --- | --- |
| today's (`mmap`, 528 MB) | 139.9 ms; with an `mmap` counter, 147.5 ms | 567.1 MiB | 572.9 MiB |
| `.bss` arena prototype (600 MB) | 0.0 ms | 46.9 MiB | 53.0 MiB |
| bare Node | | 42.3 MiB | |

With a counting `mmap` wrapper, today's `bend_init` made 19 `mmap` calls
and 14 `munmap` calls.

- `mmap(0, 512 MiB)` 14 times (hints `2^45` to `2^32` truncated to NULL),
  each succeeding at 0x90000 and then unmapped.
- Hints 0x80000000, 0x40000000 and 0x20000000, which fail (EINVAL).
- The final `mmap(NULL)`.
- The 8 MiB + 16 KiB stack.

In all, 7,688 MiB were mapped and zeroed by Emscripten's memset. The
`.bss` prototype serves every `mmap` with a NULL address from a static
arena and fails every hint, as Emscripten does for non-NULL hints. The
`!` programs and hello also gave native output in it, at an RSS of 47.8
to 48.2 MiB.

Not measured: Chrome's tab footprint after the change (t-2lsz77ug), and
`/usr/bin/time -l` RSS (the sandbox refuses its `sysctl`; `mincore` and
Node's RSS were used instead).

## 5. Patch shapes

Every change goes under `#if defined(__EMSCRIPTEN__)`. That keeps native
C byte-identical, and the device kernels, which are compiled from the
same text with `DEVICE` set, never see it.

### (b) The corpus from fresh memory, without the memset (do first)

- In `corpus_map` (5621-5640), under Emscripten, return a static,
  64 KiB-aligned `static u64 corpus_bss[BEND_CORPUS_BYTES / 8]`, with no
  `mmap` and no hint loop.
  - Non-shared wasm memory is zero at instantiation, and wasm-ld writes
    no data segment for `.bss`, so nothing touches those pages before the
    runtime does. V8 commits them lazily.
  - `corpus_grow` already fails under Emscripten, and `bend_init` already
    refuses a second call, so the array is used once per instance.
- The same for `pool_stack` (5099-5104), which memsets 8 MiB today:
  `static char stack_bss[BEND_STACK_BYTES + 16384]`.
- Fix the hint loop in any case. Patch 0001's loop (5622-5630) should not
  run where `sizeof(void*) < 8`. Key it on pointer width, not on the
  toolchain, since every wasm32 or 32-bit host has the bug. Patch 0001's
  header ("Emscripten's mmap refuses every hint with EINVAL") is true only
  of hints below `2^32`.
- `INITIAL_MEMORY` must then hold the static image including the arrays,
  plus Emscripten's stack and malloc arena. Today's numbers would barely
  change (528 MB = 512 MiB + 8 MiB + 8 MiB); the prototype used 600 MB
  and was not tuned. A too-small value fails loudly at link time.
- Minimum corpus: unchanged (409.5 MiB), but only about 0.4 MiB of it is
  resident.
- Rejected alternatives:
  - `memalign` or `sbrk` without a memset: it may return memory that was
    used and freed, and the hint loop does exactly that today.
  - `memory.grow`: the coordinator's decision is no memory growth.

### (e) A host layout without the device areas (recommended second)

```c
#if defined(__EMSCRIPTEN__)
// One worker on the host: the device's per-lane allocator rows and stacks
// are not in the corpus; rings only when a `!` fork can deal tasks.
#define RING_OFF ALC_OFF
#define STAK_OFF (RING_OFF + (BANGS ? CUBE * RING_WORDS : 0))
#define STAT_OFF STAK_OFF
#else
... (3896-3898 as today)
#endif
```

`corpus_lay`'s `cap <= CUBE` (5645) becomes `cap < 2` under Emscripten:
page 0 of the heap is the scratch page, and running out later is
`ERR_HEAP`. `CUBE_T`, `CUBE_LOG`, `RING_LEN` and the schedule stay as they
are.

Minimum corpus, with S the static image in words:

- `BANGS == 0`: `256 + PAGE_UP(S) + 138 * pages` words. For Robokill
  (S = 0, 305 pages) that is 42,346 words, about 331 KiB. Its real size
  comes from t-xes4fk35's stress run plus headroom.
- `BANGS != 0`: add 16,809,984 words (128.25 MiB) of rings. Of these, a
  run touches only the first few slot rows, and with (b) the rest stays
  non-resident.

If keeping the rings is preferred, `cap > CUBE` alone can be dropped:
`(256 + 16,809,984 + S) * 8` bytes plus the heap, about 128.3 MiB.

### (a) A CPU-sized `CUBE_T` (not recommended)

`CUBE_T` 16 needs `CUBE_LOG` <= 4 and a `RING_LOG` that no longer grows as
`CUBE_LOG` falls. With `RING_LOG` fixed at 10 and `RING_WORDS` as
`RING_LEN + 2`:

- allocator rows 16,384 words, rings 262,656 words, stacks 524,288 words;
- `HEAP_OFF` about 803,584 + S words;
- with `cap > CUBE`, a minimum of about 839,000 words (6.4 MiB).

It touches six coupled constants, changes the `!` schedule (part 1) and
gains nothing over (e) for programs without `!` forks.

### Tests that would catch a mistake

All of today's gates, run at the new size:

- the differential;
- the negative checks;
- the replay, with checkpoint hashes, render bytes and the heap bound;
- `probe/deep.bend` (`ERR_DEEP`) and `probe/exhaust.bend` (`ERR_HEAP`);
- `probe/lib`.

New tests:

- Lane boundaries: `!` programs on wasm compared with native
  `--threads 1`. Candidates are the `tests/run` programs with `!(`:
  `array_fork`, `fork_leaf_result_loop`, `stencil3d`,
  `array_atomic_fadd`, `array_redirect_race`, `gpu_mark` and `gpu_trig`.
  The differential corpus leaves `!` programs out today. Also one program whose frontier reaches `CUBE` (16,384 or more
  tasks: a balanced fork tree of depth 14 or more). It takes
  `ring_flip`'s top rings (`LANES - 1`) and `cube_run`'s `f >= CUBE`
  branch. Under (e), a `BANGS != 0` program must get its rings: a test
  with the `BANGS` term removed must fail.
- Ring near full: a `!` program that deals more than `RING_LEN` (1,024)
  tasks into one ring before a drain. It must give `ERR_RING` natively and
  in wasm, and one just under the limit must pass. `ERR_RING`'s text is
  the generic "runtime fail-stop" (`ERRS`, 138-142), the same as the
  header and ring-counter faults, so the test should check where the
  failure comes from as well as the text. That also
  covers `ring_rewind`'s `n > RING_LEN` guard (5553).
- Stack near the limit: on the host the bound is `BEND_STACK_BYTES`, not
  `STAK_LEN` (`STAK_LEN` is the device's). `probe/deep.bend` must stop
  with `ERR_DEEP`, and a recursion just under the bound must pass. Under
  (b) this checks that `stk_end` is still the array's end.
- Exhaustion: at the new corpus size, `probe/exhaust.bend` and a
  library-mode leak loop (a handle never disposed) must end in
  `ERR_HEAP`'s message, not a trap. Its text, "out of memory: run again
  with a bigger span, as in --gpu 8GB", names a GPU flag that a wasm
  build lacks. An allocation that takes exactly the
  last page (`p + pages == H_CAP`, 4200) must succeed. The banks are
  sized from `cap`, so a free-heavy run at the small size must not
  overrun them (`bank_push` has no bound check).
- Zero assumptions: a debug build that fills everything but the header and
  the get/put words with garbage gives identical output (`GARBAGE=2`
  above). Its negative control, garbage in the header, must fail.
- `bend_init`: no `munmap` and at most the expected number of maps
  (counted by a wrapper, or by asserting that `bend_init` touches no more
  than a few pages). This catches a return of the hint loop or a memset.
- Static checks in the C (`_Static_assert`): `STAT_OFF <= HEAP_OFF`;
  `RING_WORDS >= RING_LEN + 2` and `CUBE * RING_WORDS >= LANES *
  (RING_LEN + 2)`; `CUBE_T` a power of two and `>= LINE`; the areas
  page-aligned.
- Native unchanged: the emitted C of a program compiles to the same
  layout natively (preprocess with and without the patch), and the
  differential's native lane is the reference.

### Risks

- `term_triv` and `spare_free` treat every location below `HEAP_OFF` as
  static. The layout must keep `STAT` below `HEAP_OFF` and keep heap
  page 0 as `heap_alloc_miss`'s error page.
- Under (e), the layout depends on `BANGS`. A `!` program built with an
  emitter that miscounts `BANGS` would deal into the static area. The
  "rings removed" negative test above guards it.
- Shared memory (a pthread build) makes wasm-ld zero `.bss` with
  `memory.fill` at start. That is still correct, but the time cost
  returns.
- A smaller corpus brings `ERR_HEAP` closer, which is observable by
  design. Size it from the stress run, not from the steady 39,040 words.
- If the toolchain changes, the guard macros must change with it (below).

### If the toolchain became a freestanding wasm32 build

The layout analysis stays the same. The layout, the lane areas, the zero
assumptions and what reaches output are all in `comp.ts` and depend only
on `DEVICE`, the constants and `BANGS`, not on the compiler or libc.
These parts would differ:

- There is no `mmap`. The corpus and stack come from a static array or
  from initial memory past `__heap_base`, both zero by the spec, so (b)
  becomes the natural shape with no memset to avoid. A libc subset whose
  `mmap` emulation zeroes would bring the cost back.
- Patch 0002's guards (`WL_ROOM`, `pool_stack`, one thread, the effects,
  the two-word `Env`) and (b)/(e) key on `__EMSCRIPTEN__`. They would have
  to key on `__wasm__`, or on a `BEND_WASM` macro the build sets.
- The hint-truncation bug belongs to any 32-bit target where
  `mmap(NULL)` succeeds, so it should be fixed by pointer width.
- The `.bss` and shared-memory note applies to wasm-ld either way.
