// musl's __shgetc refills a real FILE through __uflow. The only scanner
// here is strtof/strtod over a string: sh_fromstring sets the end of its
// buffer to (void*)-1, so shgetc never runs out and never calls this.
// Reaching it is a programmer error.

int __uflow(void* f) {
	__builtin_trap();
}
