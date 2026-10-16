# Probe program 4: allocates past the wasm default corpus (512 MiB, patch
# 0002): a list of 40,000,000 U32 is live at once before it is summed.
# The native corpus (8 GiB, grown in place) holds it. Prints the sum
# modulo 2^32 of 40,000,000 ones, 40000000.
# probe-expect: bend: out of memory: run again with a bigger span, as in --gpu 8GB
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
  IO.print(U32.show(sum(build(40000000n, []), 0)))
