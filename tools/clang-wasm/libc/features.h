#ifndef BEND_LIBC_FEATURES_H
#define BEND_LIBC_FEATURES_H

// The vendored musl sources (tools/clang-wasm/musl) expect musl's internal
// src/include/features.h: the public header plus these three macros. That
// file reaches the public one by a relative path into musl's tree, which is
// not vendored; the public headers come from the SDK's sysroot here.
#include_next <features.h>

#define weak __attribute__((__weak__))
#define hidden __attribute__((__visibility__("hidden")))
#define weak_alias(old, new) \
	extern __typeof(old) new __attribute__((__weak__, __alias__(#old)))

#endif
