// Native driver of the Robokill replay (replay/robokill/README.md): links
// the library-mode C of step.bend (patch 0003) and runs Robokill's replay
// protocol through it.
//
// `replay` (the default): for n = 500 and n = 2,000 from seed 12345, the
// state hash at frames 0, 1,000, ..., 10,000, printed as replay.bend does
// ("n=500 frame=0 hash=..."), and after every step a render into the F32
// region, printed as "render n=500 frame=1 hash=..." with an FNV-1a hash
// of the region's 32-bit words.
// `bound FRAMES` (n = 500): FRAMES frames of step, render and hash, and at
// every tenth of them "bound frame=... heap=... handles=...", the
// allocator's high-water mark in words and the number of live handles.
// replay.mjs does the same in wasm with the same output.
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void     bend_init(void);
uint64_t bend_heap_words(void);
uint32_t bend_handles(void);
float*   bend_f32(void);
uint32_t bend_f32_len(void);
uint64_t bend_def_init(uint32_t n, uint32_t seed);
uint32_t bend_def_input_at(uint32_t frame);
uint64_t bend_def_step(uint64_t s, uint32_t inp);
uint64_t bend_def_hash(uint64_t s, uint32_t* h);
uint64_t bend_def_render(uint64_t s);

static uint32_t region_hash(void) {
  const float* f   = bend_f32();
  uint32_t     len = bend_f32_len();
  uint32_t     h   = 2166136261u;
  for (uint32_t i = 0; i < len; i += 1) {
    uint32_t w;
    memcpy(&w, &f[i], 4);
    h = (h ^ w) * 16777619u;
  }
  return h;
}

static void replay(uint32_t n) {
  uint64_t s = bend_def_init(n, 12345);
  for (uint32_t fr = 0;; fr += 1) {
    if (fr % 1000 == 0) {
      uint32_t h;
      s = bend_def_hash(s, &h);
      printf("n=%u frame=%u hash=%u\n", n, fr, h);
    }
    if (fr == 10000) {
      break;
    }
    s = bend_def_step(s, bend_def_input_at(fr));
    s = bend_def_render(s);
    printf("render n=%u frame=%u hash=%u\n", n, fr + 1, region_hash());
  }
}

static void bound(uint32_t frames) {
  uint64_t s = bend_def_init(500, 12345);
  for (uint32_t fr = 0; fr < frames; fr += 1) {
    uint32_t h;
    s = bend_def_step(s, bend_def_input_at(fr));
    s = bend_def_render(s);
    s = bend_def_hash(s, &h);
    if ((fr + 1) % (frames / 10) == 0) {
      printf("bound frame=%u heap=%" PRIu64 " handles=%u\n", fr + 1,
        bend_heap_words(), bend_handles());
    }
  }
}

int main(int argc, char** argv) {
  bend_init();
  if (argc > 2 && strcmp(argv[1], "bound") == 0) {
    bound((uint32_t)strtoul(argv[2], NULL, 10));
  } else {
    replay(500);
    replay(2000);
  }
  return 0;
}
