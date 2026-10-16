// Probe driver: the ring area's boundaries (docs/probe.md, "After step 2").
// A Bend program on one worker cannot fill a ring: probe/forks.bend's
// 4,194,304 leaves push 510 tasks, at most one per ring at a time, into
// rings 0 to 255. So this driver includes the emitted C of a `!` program
// and drives ring_push itself on the top ring (LANES - 1), whose put word
// is the last word of the ring area, right below the static image on wasm
// (patch 0002's host layout) and below the device stacks natively.
// RING_LEN pushes fit; the next one posts ERR_RING, which on the host
// stops the run with "bend: runtime fail-stop". It prints the same lines
// natively and in wasm; probe/run.sh builds it against PROBE_C.
// probe-include: forks
// probe-expect: bend: runtime fail-stop
#define main bend_main
#include PROBE_C
#undef main

static void need(bool ok, const char* what) {
  if (!ok) {
    fprintf(stderr, "rings: %s\n", what);
    exit(2);
  }
}

int main(void) {
  u64* H = corpus_setup(false, 1, 0);
#if defined(__EMSCRIPTEN__)
  need(RING_OFF == ALC_OFF && STAT_OFF == RING_OFF + CUBE * RING_WORDS,
    "the host layout is not ALC_OFF, rings, static image");
#else
  need(STAK_OFF == RING_OFF + CUBE * RING_WORDS, "the native layout moved");
#endif
  need(LANES * (RING_LEN + 2) == CUBE * RING_WORDS,
    "the rings do not fill their area exactly");
  u32 top = (u32)(LANES - 1);
  need(ring_word(H, 0, 0) == H + RING_OFF, "ring 0 does not start the area");
  need(ring_word(H, top, RING_LEN + 1) == H + RING_OFF + CUBE * RING_WORDS - 1,
    "the top ring's put word is not the area's last word");
  printf("ring %u's put word is the last word of the ring area\n", top);
  for (u32 i = 0; i < RING_LEN; i += 1) {
    ring_push(H, top, ((u64)i << 4) | TAG_TSK);
  }
  need(*ring_put(H, top) == RING_LEN && *ring_get(H, top) == 0,
    "the put counter is not RING_LEN");
  need(memcmp(H + STAT_OFF, STAT_IMG, STAT_LEN * sizeof(u64)) == 0,
    "a push wrote into the static image");
  need(H[H_ERROR_CODE] == 0, "an error was posted before the ring was full");
  printf("%u pushes fit ring %u, the static image is intact\n",
    (u32)RING_LEN, top);
  printf("push %u:\n", (u32)RING_LEN + 1);
  fflush(stdout);
  ring_push(H, top, TAG_TSK);
  printf("push %u did not stop the run\n", (u32)RING_LEN + 1);
  return 0;
}
