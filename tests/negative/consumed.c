// Negative check (tests/negative/README.md): links probe/lib's library-mode
// C of counter.bend and peeks a handle that step already consumed, which
// must fail with the library's handle message and exit 1.
#include <inttypes.h>
#include <stdio.h>

void     bend_init(void);
uint64_t bend_def_init(uint32_t n);
uint64_t bend_def_step(uint64_t s, uint32_t x);
uint32_t bend_def_peek(uint64_t s);

int main(void) {
  bend_init();
  uint64_t s = bend_def_init(5);
  bend_def_step(s, 0);
  bend_def_peek(s);
  printf("misuse not caught\n");
  return 0;
}
