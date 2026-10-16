# Probe program 2: pure, deterministic arithmetic; its only effect is
# printing the result. Shape taken from vendor/bend/demos/pure_par_sum/main.bend
# (the same Nat match and Nat.show), without its `!` so no GPU lane is asked.
# Prints the sum of the squares of 0 .. 99, which is 328350.
import Base

def squares(n: Nat) -> Nat:
  match n:
    case 0n:
      0n
    case 1n++m:
      Nat.add(squares(m), Nat.mul(m, m))

def main() -> IO(Unit):
  IO.print(Nat.show(squares(100n)))
