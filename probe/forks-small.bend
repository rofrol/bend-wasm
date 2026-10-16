# Probe program 8: probe/forks.bend built with a corpus that cannot hold
# its rings (128.25 MiB): a -DBEND_CORPUS_BYTES too small for the layout
# stops at start with corpus_lay's error, before any Bend code runs, not
# with a wrong result or a trap. The default corpus is sized from the
# layout, rings included, so it never meets this. Natively the knob is
# ignored by the probe (no probe-cflags there) and it prints the leaves.
# probe-cflags: -DBEND_CORPUS_BYTES=4194304
# probe-expect: bend: the corpus (-DBEND_CORPUS_BYTES) is under its header, rings and static image plus two heap pages
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
