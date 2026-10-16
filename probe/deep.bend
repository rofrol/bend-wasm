# Probe program 3: recursion deep enough to overflow the Term stack of the
# wasm default (8 MiB, patch 0002): each of the 20,000,000 pending
# additions keeps a frame on the stack. A native binary's stack (2 GiB)
# holds it and prints 20000000; `scripts/bend probe/deep.bend` (the JS
# lane) fails with the same error as wasm (docs/probe.md).
# probe-expect: bend: memory fault (machine stack overflow?)
import Base

def deep(n: Nat) -> U32:
  match n:
    case 0n:
      0
    case 1n++m:
      (1 + deep(m) : U32)

def main() -> IO(Unit):
  IO.print(U32.show(deep(20000000n)))
