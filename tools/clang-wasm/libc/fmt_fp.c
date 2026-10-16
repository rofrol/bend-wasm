// printf's %e and %f of a double for patch 0004's printf, from musl's own
// formatter: fmt_fp of the SDK's vfprintf.c (Emscripten's variant, which
// formats long double at double precision, as emcc's printf does), included
// unmodified. fmt_fp is static there, so this file includes it and adds:
//
//   int bend_fmt_fp(char* out, int cap, double v, int prec, int conv)
//
// the text of v with conv 'e' or 'f' and precision prec (no flags, no
// width) into out, at most cap bytes and no NUL; it returns the length of
// the whole text, which is more than cap when it did not fit, or -1.
//
// fmt_fp writes through out() into a FILE: here one that only collects
// bytes, with __fwritex its single writer. The rest of vfprintf.c (printf
// itself) is never called and the linker drops it.

#include "vfprintf.c"

size_t __fwritex(const unsigned char* restrict s, size_t l, FILE* restrict f) {
	size_t room = (size_t)(f->wend - f->wpos);
	if (l > room) {
		l = room;
	}
	memcpy(f->wpos, s, l);
	f->wpos += l;
	return l;
}

int bend_fmt_fp(char* out, int cap, double v, int prec, int conv) {
	FILE f = { 0 };
	f.wpos = (unsigned char*)out;
	f.wend = (unsigned char*)out + cap;
	return fmt_fp(&f, v, 0, prec, 0, conv, 0);
}
