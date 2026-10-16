// The driver of tools/clang-wasm/math-check.sh (TODO t-fwjpak4c, step C):
// the same calls into the math functions, strtof, strtod and the %e/%f
// formatter, built once by emcc (its musl) and once by plain clang with
// tools/clang-wasm/libc.sh's archive, so math-check.mjs can compare the two
// bit for bit. Values cross the JS boundary as their bits (i64, i32): a JS
// number may not keep a NaN's payload.
//
// It is built with -fno-builtin, so every call reaches the library and
// none is folded or replaced by clang.

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MC_EXPORT __attribute__((used, visibility("default")))

static char mc_text[8192];

#ifndef __EMSCRIPTEN__
// The plain build links no libc but the archive, whose code calls these.
// Defined as patch 0004 defines them.
void* memcpy(void* restrict d, const void* restrict s, size_t n) {
  return __builtin_memcpy(d, s, n);
}

void* memset(void* d, int c, size_t n) {
  return __builtin_memset(d, c, n);
}

static int mc_errno;

int* __errno_location(void) {
  return &mc_errno;
}

int bend_fmt_fp(char* out, int cap, double v, int prec, int conv);
#endif

static double mc_d(uint64_t b) {
  double x;
  memcpy(&x, &b, sizeof x);
  return x;
}

static uint64_t mc_b(double x) {
  uint64_t b;
  memcpy(&b, &x, sizeof b);
  return b;
}

static float mc_fd(uint32_t b) {
  float x;
  memcpy(&x, &b, sizeof x);
  return x;
}

static uint32_t mc_fb(float x) {
  uint32_t b;
  memcpy(&b, &x, sizeof b);
  return b;
}

MC_EXPORT char* mc_buf(void) {
  return mc_text;
}

// The unary functions, in math-check.mjs's order.
MC_EXPORT uint64_t mc_f1(int op, uint64_t xb) {
  double x = mc_d(xb);
  double r;
  switch (op) {
    case 0: r = exp(x); break;
    case 1: r = log(x); break;
    case 2: r = log2(x); break;
    case 3: r = log10(x); break;
    case 4: r = sin(x); break;
    case 5: r = cos(x); break;
    case 6: r = tan(x); break;
    case 7: r = asin(x); break;
    case 8: r = acos(x); break;
    case 9: r = atan(x); break;
    case 10: r = sinh(x); break;
    case 11: r = cosh(x); break;
    case 12: r = tanh(x); break;
    default: __builtin_trap();
  }
  return mc_b(r);
}

MC_EXPORT uint64_t mc_f2(int op, uint64_t xb, uint64_t yb) {
  double x = mc_d(xb);
  double y = mc_d(yb);
  return mc_b(op == 0 ? atan2(x, y) : pow(x, y));
}

MC_EXPORT uint32_t mc_fmodf(uint32_t xb, uint32_t yb) {
  return mc_fb(fmodf(mc_fd(xb), mc_fd(yb)));
}

// strtof/strtod of the NUL-terminated text in mc_buf(); the bytes they
// took go to the int at mc_buf() + 8188 (the text stays shorter).
MC_EXPORT uint32_t mc_strtof(void) {
  char* end;
  uint32_t r = mc_fb(strtof(mc_text, &end));
  int n = (int)(end - mc_text);
  memcpy(mc_text + 8188, &n, sizeof n);
  return r;
}

MC_EXPORT uint64_t mc_strtod(void) {
  char* end;
  uint64_t r = mc_b(strtod(mc_text, &end));
  int n = (int)(end - mc_text);
  memcpy(mc_text + 8188, &n, sizeof n);
  return r;
}

// The text of v by %.*e (conv 'e') or %.*f ('f') into mc_buf(); its length,
// or -1. The emcc build goes through its snprintf, as the emcc runtime
// does; the plain one calls bend_fmt_fp, which patch 0004's printf calls
// for %e and %f (it copies the bytes as they come).
MC_EXPORT int mc_fmt(uint64_t vb, int prec, int conv) {
  double v = mc_d(vb);
#ifdef __EMSCRIPTEN__
  return snprintf(mc_text, sizeof mc_text, conv == 'e' ? "%.*e" : "%.*f",
    prec, v);
#else
  int n = bend_fmt_fp(mc_text, (int)sizeof mc_text - 1, v, prec, conv);
  if (n >= 0 && n < (int)sizeof mc_text) {
    mc_text[n] = 0;
  }
  return n;
#endif
}
