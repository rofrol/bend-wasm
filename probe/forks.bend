# Probe program 7: `!` forks, so the wasm corpus holds the rings (patch
# 0002's host layout puts them only in a program with BANGS != 0). A
# balanced fork tree of depth 22 counts its 4,194,304 leaves; its tasks
# go through task_deal, the grow and drain turns and ring_rewind on one
# worker. Natively (--threads 1) it prints the same line. The string
# literal is in the static image, right above the rings on wasm.
import Base

def tree(+d: Nat) -> U32:
  match d:
    case 0n:
      1
    case 1n+p:
      a b = tree(p) tree(p)
      (a + b : U32)

def main() -> IO(Unit):
  IO.print("leaves " ++ U32.show(tree!(22n)))
