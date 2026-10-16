# Vendored test input, not bend-wasm code: spike/replay.bend of the Robokill repository at commit 63031ab (replay/robokill/fetch.sh re-copies it).
# Native replay of the spike: runs the recorded input script through step
# and prints the state hash every 1,000 frames, for comparison with the JS
# lane (spike/main.js and spike/replay.mjs print the same lines).

import Base
import ./step.bend as G

def run(f: Nat, +fr: U32, s: G.State) -> G.State:
  match f:
    case 0n:
      s
    case 1n+p:
      run(p, (fr + 1 : U32), G.step(s, G.input_at(fr)))

# Prints k checkpoints; r is the state at frame fr and its hash.
def report(k: Nat, +n: U32, +fr: U32, r: G.State & U32) -> IO(Unit):
  match k:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+p:
      (s, h) = r
      do IO<Unit>:
        IO.print("n=" ++ U32.show(n) ++ " frame=" ++ U32.show(fr) ++ " hash=" ++ U32.show(h))
        report(p, n, (fr + 1000 : U32), G.hash(run(1000n, fr, s)))

def main() -> IO(Unit):
  do IO<Unit>:
    report(11n, 500, 0, G.hash(G.init(500, 12345)))
    report(11n, 2000, 0, G.hash(G.init(2000, 12345)))
