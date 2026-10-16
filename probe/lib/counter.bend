# Persistent-state spike (probe/lib/README.md): a state a host keeps
# across calls through library mode (patch 0003). `init`, `step` and
# `peek` are the exported defs; `main` computes what the drivers do in one
# run: init(5), 100,000 steps with x = 0, 1, ..., and a peek after every
# 10,000 steps.
import Base

type State is Data:
  State{n: U32, sum: U32, xs: +List<U32>}

# A list of `n` copies of `x`.
def fill(n: Nat, +x: U32) -> +List<U32>:
  match n:
    case 0n:
      []
    case 1n+m:
      x <> fill(m, x)

# Appends `x` after the last element: a new list of the same cells.
def snoc(xs: +List<U32>, x: U32) -> +List<U32>:
  match xs:
    case []:
      [x]
    case h <> t:
      h <> snoc(t, x)

# The sum of the elements plus `acc`; a tail loop, so it only reads `xs`
# (peek borrows its state).
def total(xs: +List<U32>, acc: U32) -> U32:
  match xs:
    case []:
      acc
    case h <> t:
      total(t, (acc + h : U32))

def init(+n: U32) -> State:
  State{n, 0, fill(8n, n)}

# One frame: drops the oldest element and appends a new one, so every call
# frees a list cell and allocates a new spine.
def step(s: State, +x: U32) -> State:
  match s:
    case State{+n, sum, xs}:
      match xs:
        case []:
          State{n, sum, [x]}
        case h <> t:
          State{(n + 1 : U32), U32.xor(sum, (h * 31 + x : U32)), snoc(t, U32.xor(x, n))}

def peek(+s: State) -> U32:
  match s:
    case State{n, sum, xs}:
      total(xs, (sum + n * 7 : U32))

def steps(k: Nat, s: State, +i: U32) -> State:
  match k:
    case 0n:
      s
    case 1n+m:
      steps(m, step(s, i), (i + 1 : U32))

def rounds(c: Nat, s: State, +i: U32) -> List<U32>:
  match c:
    case 0n:
      []
    case 1n+m:
      +t = steps(10000n, s, i)
      peek(t) <> rounds(m, t, (i + 10000 : U32))

def main() -> List<U32>:
  rounds(10n, init(5), 0)
