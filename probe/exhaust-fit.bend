# Probe program 10: probe/exhaust.bend one list cell shorter, 77,824 U32
# live at once, the longest list the wasm default corpus holds: it must
# run and print 77824, as natively. If the default heap (1,280 pages) or
# a cell's size changes, this and probe/exhaust.bend move together
# (docs/probe.md, "After step 2").
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
  IO.print(U32.show(sum(build(77824n, []), 0)))
