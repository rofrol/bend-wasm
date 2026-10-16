# Probe program 5: IO.random_u32. Its effect runs only on the helper
# pthread (io_work), which wasm32 without -pthread does not have, so
# patch 0002 stops it with the helper-effect error after the first line.
# Natively it prints both lines (two draws differ: True).
# probe-expect: bend: blocking effects (files, processes, random numbers) are not supported on this target (wasm)
import Base

def main() -> IO(Unit):
  do IO<Unit>:
    x : Unit <- IO.print("drawing")
    a : U32 <- IO.try(U32, IO.random_u32())
    b : U32 <- IO.try(U32, IO.random_u32())
    IO.print(Bool.show(U32.is_ne(a, b)))
