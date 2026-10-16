
// Appended by glue/test/run.sh to the library-mode C of step.bend, so the
// failure test has a def that really traps in wasm (unreachable) inside a
// call, as a fault in the runtime would. The line above the def is the one
// patch 0003 writes, so glue/gen.mjs wraps it like any def.

// trap: no arguments -> U32
u32 bend_def_trap(void) {
  __builtin_trap();
}
