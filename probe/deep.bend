# Probe program 3: recursion one frame past the Term stack of the wasm
# default (8 MiB, patch 0002): each pending addition keeps a one-word
# frame, and 1,048,572 of them do not fit the 2^20 words with the entry
# frames below them, so WL_ROOM stops it with ERR_DEEP. probe/deep-fit.bend
# is the same recursion one frame shorter, the deepest that runs. Natively
# the 2 GiB stack holds it and prints 1048572; `scripts/bend probe/deep.bend`
# (the JS lane) fails with the same error as wasm (docs/probe.md).
# probe-expect: bend: memory fault (machine stack overflow?)
import Base

def deep(n: Nat) -> U32:
  match n:
    case 0n:
      0
    case 1n++m:
      (1 + deep(m) : U32)

def main() -> IO(Unit):
  IO.print(U32.show(deep(1048572n)))
