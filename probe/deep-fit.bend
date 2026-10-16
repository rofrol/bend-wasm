# Probe program 9: probe/deep.bend one frame shorter, 1,048,571 pending
# additions, the deepest recursion the wasm default Term stack (8 MiB,
# patch 0002) holds: it must run and print 1048571, as natively. If the
# stack size or a frame's layout changes, this and probe/deep.bend move
# together (docs/probe.md, "After step 2").
import Base

def deep(n: Nat) -> U32:
  match n:
    case 0n:
      0
    case 1n++m:
      (1 + deep(m) : U32)

def main() -> IO(Unit):
  IO.print(U32.show(deep(1048571n)))
