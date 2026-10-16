# Probe program 6: Process.run. Its effect runs only on the helper
# pthread (io_work), so patch 0002 stops it with the helper-effect error
# after the first line. Natively it prints "running", then /bin/echo's
# exit code 0.
# probe-expect: bend: blocking effects (files, processes, random numbers) are not supported on this target (wasm)
import Base

def code(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> String:
  match r:
    case Done{(c, out)}:
      U32.show(c)
    case Fail{(c, message)}:
      "failed " ++ U32.show(c)

def main() -> IO(Unit):
  do IO<Unit>:
    x : Unit <- IO.print("running")
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <-
      Process.run("/bin/echo", ["hi"], "", 128, 1000)
    IO.print(code(r))
