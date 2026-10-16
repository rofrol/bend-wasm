// Native driver of the persistent-state spike (probe/lib/README.md):
// links the library-mode C of counter.bend (patch 0003) and runs init, then
// 100,000 steps with x = 0, 1, ..., a peek after every 10,000, then
// dispose. Prints each peek and the heap high-water mark in words.
// `drive --misuse` then peeks the disposed handle, which must fail.
#include <inttypes.h>
#include <stdio.h>
#include <string.h>

void     bend_init(void);
void     bend_dispose(uint64_t h);
uint64_t bend_heap_words(void);
uint64_t bend_def_init(uint32_t n);
uint64_t bend_def_step(uint64_t s, uint32_t x);
uint32_t bend_def_peek(uint64_t s);

int main(int argc, char** argv) {
  bend_init();
  uint64_t s = bend_def_init(5);
  printf("init heap %" PRIu64 "\n", bend_heap_words());
  for (uint32_t i = 0; i < 100000; i += 1) {
    s = bend_def_step(s, i);
    if ((i + 1) % 10000 == 0) {
      uint32_t p = bend_def_peek(s);
      printf("step %u peek %u heap %" PRIu64 "\n", i + 1, p,
        bend_heap_words());
    }
  }
  bend_dispose(s);
  printf("disposed heap %" PRIu64 "\n", bend_heap_words());
  fflush(stdout);
  if (argc > 1 && strcmp(argv[1], "--misuse") == 0) {
    bend_def_peek(s);
    printf("misuse not caught\n");
  }
  return 0;
}
