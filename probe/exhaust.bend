# Probe program 4: allocates one list cell past the wasm default corpus
# (patch 0002: the layout plus 1,280 heap pages): a list of 77,825 U32 is
# live at once before it is summed, and the runtime stops with its
# out-of-memory error (ERR_HEAP), not a trap or a wrong sum.
# probe/exhaust-fit.bend is one cell shorter, the longest that fits. The
# native corpus (8 GiB, grown in place) holds it and prints 77825.
# probe-expect: bend: out of memory: the corpus of 1425408 bytes is full; build with a bigger -DBEND_CORPUS_BYTES=...
import Base

def build(n: Nat, acc: List<U32>) -> List<U32>:
  match n:
    case 0n:
      acc
    case 1n++m:
      build(m, 1 <> acc)

def sum(l: List<U32>, a: U32) -> U32:
  match l:
    case []:
      a
    case h <> t:
      sum(t, (a + h : U32))

def main() -> IO(Unit):
  IO.print(U32.show(sum(build(77825n, []), 0)))
