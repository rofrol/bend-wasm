# Vendored test input, not bend-wasm code: spike/step.bend of the Robokill repository at commit 63031ab (replay/robokill/fetch.sh re-copies it).
# Milestone 2 spike: a pure, deterministic simulation step for the browser.
#
# N bodies bounce in a 1280x720 room and collide with walls and each other
# (uniform grid, 16-unit cells); projectiles spawn from the input word and
# reverse the bodies they hit. Only U32 and F32 in the hot path; F32 uses
# + - * / and comparisons only, so the JS lane (Math.fround) and the native
# build agree bit for bit.
#
# Slots: bodies in [0, n), projectiles in [2048, 2304), 4096 slots in all.
# Render layout: 4 F32 per sprite (x, y, angle, atlas); atlas < 0 is hidden.

import Base

type Ent is Data:
  Ent{x: F32, y: F32, a: F32, k: F32, vx: F32, vy: F32, life: U32}

type W is Type:
  W{ents: Array<Ent>, head: Array<U32>, nxt: Array<U32>, cnt: Array<U32>}

type State is Type:
  State{n: U32, frame: U32, shot: U32, w: W}

# Generic counted loop: body(i, s) for i in [i0, i0 + f).
def each(~T: Type, ~body: @+i:U32 -> T -> T, f: Nat, +i: U32, s: T) -> T:
  match f:
    case 0n:
      s
    case 1n+p:
      each(~T, ~body, p, (i + 1 : U32), body(i, s))

def ent.empty() -> Ent:
  Ent{0.0, 0.0, 0.0, F32.neg(1.0), 0.0, 0.0, 0}

# Walls
# =====

# Mirror a position that crossed a wall back inside, so bodies pressed into
# a wall or corner never share one exact point.
def wall.p(+lo: F32, +hi: F32, +q: F32) -> F32:
  Bool.pick(F32, F32.is_lt(q, lo), (lo + lo - q : F32),
    Bool.pick(F32, F32.is_gt(q, hi), (hi + hi - q : F32), q))

def wall.v(+lo: F32, +hi: F32, +q: F32, +v: F32) -> F32:
  Bool.pick(F32, F32.is_lt(q, lo) || F32.is_gt(q, hi), F32.neg(v), v)

def out(+lo: F32, +hi: F32, +q: F32) -> Bool:
  F32.is_lt(q, lo) || F32.is_gt(q, hi)

# Integration
# ===========

def body.move(e: Ent) -> Ent:
  match e:
    case Ent{x, y, a, k, +vx, +vy, life}:
      +qx = (x + vx : F32)
      +qy = (y + vy : F32)
      Ent{wall.p(4.0, 1276.0, qx), wall.p(4.0, 716.0, qy), (a + 0.05 : F32), k,
        wall.v(4.0, 1276.0, qx, vx), wall.v(4.0, 716.0, qy, vy), life}

def proj.move(e: Ent) -> Ent:
  match e:
    case Ent{x, y, a, k, +vx, +vy, +life}:
      +qx = (x + vx : F32)
      +qy = (y + vy : F32)
      +dead = out(0.0, 1280.0, qx) || out(0.0, 720.0, qy) || U32.is_lt(life, 2)
      Ent{qx, qy, (a + 0.2 : F32), Bool.pick(F32, dead, F32.neg(1.0), 4.0),
        Bool.pick(F32, dead, 0.0, vx), Bool.pick(F32, dead, 0.0, vy),
        Bool.pick(U32, dead, 0, (life - 1 : U32))}

def move.set(~f: Ent -> Ent, +i: U32, r: Array<Ent> & Ent) -> Array<Ent>:
  (ents, e) = r
  Array.set(Ent, ents, i, f(e))

def move.body(+i: U32, w: W) -> W:
  match w:
    case W{ents, head, nxt, cnt}:
      W{move.set(~body.move, i, Array.get(Ent, ents, i)), head, nxt, cnt}

def move.proj(+i: U32, w: W) -> W:
  match w:
    case W{ents, head, nxt, cnt}:
      W{move.set(~proj.move, i, Array.get(Ent, ents, i)), head, nxt, cnt}

# Grid
# ====
# head[c] is the first body in cell c, nxt[i] the next one, cnt[c] the count.
# Cell 4095 is never filled: lookups outside the room land there.

def cell(+x: F32, +y: F32) -> U32:
  +cx = F32.to_u32((F32.max(x, 0.0) * 0.0625 : F32))
  +cy = F32.to_u32((F32.max(y, 0.0) * 0.0625 : F32))
  Bool.pick(U32, U32.is_lt(cx, 80) && U32.is_lt(cy, 45), (cy * 80 + cx : U32), 4095)

def cell.of(e: Ent) -> U32:
  match e:
    case Ent{+x, +y, a, k, vx, vy, life}:
      cell(x, y)

# Neighbour k in [0, 9) of cell (cx, cy); 4095 when outside the room.
def cell.near(+cx: U32, +cy: U32, +k: U32) -> U32:
  +nx = (cx + U32.mod(k, 3) - 1 : U32)
  +ny = (cy + U32.div(k, 3) - 1 : U32)
  Bool.pick(U32, U32.is_lt(nx, 80) && U32.is_lt(ny, 45), (ny * 80 + nx : U32), 4095)

def grid.clear(+c: U32, w: W) -> W:
  match w:
    case W{ents, head, nxt, cnt}:
      W{ents, head, nxt, Array.set(U32, cnt, c, 0)}

def ins.d(+i: U32, ents: Array<Ent>, head: Array<U32>, nxt: Array<U32>, +c: U32,
  r: Array<U32> & U32) -> W:
  (cnt, m) = r
  W{ents, head, nxt, Array.set(U32, cnt, c, (m + 1 : U32))}

def ins.c(+i: U32, ents: Array<Ent>, nxt: Array<U32>, cnt: Array<U32>, +c: U32,
  r: Array<U32> & U32) -> W:
  (head, old) = r
  ins.d(i, ents, Array.set(U32, head, c, i), Array.set(U32, nxt, i, old), c,
    Array.get(U32, cnt, c))

def ins.e(+i: U32, head: Array<U32>, nxt: Array<U32>, cnt: Array<U32>,
  r: Array<Ent> & Ent) -> W:
  (ents, e) = r
  +c = cell.of(e)
  ins.c(i, ents, nxt, cnt, c, Array.get(U32, head, c))

def grid.ins(+i: U32, w: W) -> W:
  match w:
    case W{ents, head, nxt, cnt}:
      ins.e(i, head, nxt, cnt, Array.get(Ent, ents, i))


# Scanning neighbour cells
# ========================
# A scan carries the world (less nxt, which the walk holds), the probe
# (x, y, vx, vy) and whether it has hit something.

type Scan is Type:
  Scan{me: U32, ents: Array<Ent>, head: Array<U32>, cnt: Array<U32>, x: F32, y: F32, vx: F32, vy: F32, hit: Bool}

type Near is Type:
  Near{nxt: Array<U32>, s: Scan}

def hit.ex(e: Ent) -> F32:
  match e:
    case Ent{x, y, a, k, vx, vy, l}:
      x

def hit.ey(e: Ent) -> F32:
  match e:
    case Ent{x, y, a, k, vx, vy, l}:
      y

def hit.evx(e: Ent) -> F32:
  match e:
    case Ent{x, y, a, k, vx, vy, l}:
      vx

def hit.evy(e: Ent) -> F32:
  match e:
    case Ent{x, y, a, k, vx, vy, l}:
      vy

# Body probe `me` meets body j > me (each pair once): an elastic exchange
# along the normal when they approach (equal masses), and a push apart
# that grows with the overlap, both applied to the two bodies.
def hit.body.set(on: Bool, +j: U32, +c: F32, +q: F32, +dx: F32, +dy: F32,
  ents: Array<Ent>, e: Ent) -> Array<Ent>:
  match on:
    case False{}:
      ents
    case True{}:
      Ent{xj, yj, aj, kj, vxj, vyj, lj} = e
      Array.set(Ent, ents, j, Ent{(xj - c * dx : F32), (yj - c * dy : F32), aj, kj,
        (vxj + q * dx : F32), (vyj + q * dy : F32), lj})

def hit.body(j0: U32, x0: F32, y0: F32, vx0: F32, vy0: F32, hit: Bool,
  me0: U32, head: Array<U32>, cnt: Array<U32>, r: Array<Ent> & Ent) -> Scan:
  (ents, +ej) = r
  +j = j0
  +me = me0
  +x = x0
  +y = y0
  +vx = vx0
  +vy = vy0
  +dx = (x - hit.ex(ej) : F32)
  +dy = (y - hit.ey(ej) : F32)
  +d2 = (dx * dx + dy * dy : F32)
  +rv = ((vx - hit.evx(ej)) * dx + (vy - hit.evy(ej)) * dy : F32)
  +on = U32.is_gt(j, me) && F32.is_lt(d2, 64.0) && F32.is_gt(d2, 0.0)
  +q = Bool.pick(F32, on && F32.is_lt(rv, 0.0), (rv / d2 : F32), 0.0)
  +c = Bool.pick(F32, on, ((64.0 - d2) / (d2 + 64.0) * 0.25 : F32), 0.0)
  Scan{me, hit.body.set(on, j, c, q, dx, dy, ents, ej), head, cnt, (x + c * dx : F32),
    (y + c * dy : F32), (vx - q * dx : F32), (vy - q * dy : F32), hit}

def hit.proj.set(+on: Bool, +j: U32, ents: Array<Ent>, e: Ent) -> Array<Ent>:
  match e:
    case Ent{xj, yj, aj, kj, +vxj, +vyj, lj}:
      Array.set(Ent, ents, j, Ent{xj, yj, aj, kj,
        Bool.pick(F32, on, F32.neg(vxj), vxj), Bool.pick(F32, on, F32.neg(vyj), vyj), lj})

def hit.proj.d2(+x: F32, +y: F32, e: Ent) -> F32:
  match e:
    case Ent{+xj, +yj, aj, kj, vxj, vyj, lj}:
      ((x - xj) * (x - xj) + (y - yj) * (y - yj) : F32)

# Projectile probe meets body j: on its first contact the projectile is
# spent and body j reverses.
def hit.proj(j: U32, x0: F32, y0: F32, vx: F32, vy: F32, hit0: Bool,
  me: U32, head: Array<U32>, cnt: Array<U32>, r: Array<Ent> & Ent) -> Scan:
  (ents, +ej) = r
  +x = x0
  +y = y0
  +hit = hit0
  +on = F32.is_lt(hit.proj.d2(x, y, ej), 36.0) && Bool.not(hit)
  Scan{me, hit.proj.set(on, j, ents, ej), head, cnt, x, y, vx, vy, hit || on}

# Walk the f bodies of one cell; rn holds nxt and the current body.
def walk(
  ~meet: U32 -> F32 -> F32 -> F32 -> F32 -> Bool -> U32 -> Array<U32> -> Array<U32> -> (Array<Ent> & Ent) -> Scan,
  f: Nat, rn: Array<U32> & U32, s: Scan
) -> Near:
  match f:
    case 0n:
      (nxt, j) = rn
      Near{nxt, s}
    case 1n+p:
      (nxt, +j) = rn
      Scan{me, ents, head, cnt, x, y, vx, vy, hit} = s
      walk(~meet, p, Array.get(U32, nxt, j),
        meet(j, x, y, vx, vy, hit, me, head, cnt, Array.get(Ent, ents, j)))

def near.c(
  ~meet: U32 -> F32 -> F32 -> F32 -> F32 -> Bool -> U32 -> Array<U32> -> Array<U32> -> (Array<Ent> & Ent) -> Scan,
  me: U32, nxt: Array<U32>, ents: Array<Ent>, head: Array<U32>, x: F32, y: F32,
  vx: F32, vy: F32, hit: Bool, j0: U32, r: Array<U32> & U32
) -> Near:
  (cnt, m) = r
  walk(~meet, U32.to_nat(m), (nxt, j0), Scan{me, ents, head, cnt, x, y, vx, vy, hit})

def near.h(
  ~meet: U32 -> F32 -> F32 -> F32 -> F32 -> Bool -> U32 -> Array<U32> -> Array<U32> -> (Array<Ent> & Ent) -> Scan,
  +c: U32, me: U32, nxt: Array<U32>, ents: Array<Ent>, cnt: Array<U32>, x: F32,
  y: F32, vx: F32, vy: F32, hit: Bool, r: Array<U32> & U32
) -> Near:
  (head, j0) = r
  near.c(~meet, me, nxt, ents, head, x, y, vx, vy, hit, j0, Array.get(U32, cnt, c))

def near.one(
  ~meet: U32 -> F32 -> F32 -> F32 -> F32 -> Bool -> U32 -> Array<U32> -> Array<U32> -> (Array<Ent> & Ent) -> Scan,
  +c: U32, ns: Near
) -> Near:
  match ns:
    case Near{nxt, Scan{me, ents, head, cnt, x, y, vx, vy, hit}}:
      near.h(~meet, c, me, nxt, ents, cnt, x, y, vx, vy, hit, Array.get(U32, head, c))

# The 3x3 cells around (cx, cy).
def near.loop(
  ~meet: U32 -> F32 -> F32 -> F32 -> F32 -> Bool -> U32 -> Array<U32> -> Array<U32> -> (Array<Ent> & Ent) -> Scan,
  f: Nat, +k: U32, +cx: U32, +cy: U32, ns: Near
) -> Near:
  match f:
    case 0n:
      ns
    case 1n+p:
      near.loop(~meet, p, (k + 1 : U32), cx, cy, near.one(~meet, cell.near(cx, cy, k), ns))

# Collisions
# ==========

def ent.with_pv(e: Ent, x: F32, y: F32, vx: F32, vy: F32) -> Ent:
  match e:
    case Ent{ox, oy, a, k, ovx, ovy, l}:
      Ent{x, y, a, k, vx, vy, l}

def coll.fin(+i: U32, e: Ent, ns: Near) -> W:
  match ns:
    case Near{nxt, Scan{me, ents, head, cnt, x, y, vx, vy, hit}}:
      W{Array.set(Ent, ents, i, ent.with_pv(e, x, y, vx, vy)), head, nxt, cnt}

def coll.e(+i: U32, head: Array<U32>, nxt: Array<U32>, cnt: Array<U32>,
  r: Array<Ent> & Ent) -> W:
  (ents, +e) = r
  Ent{+x, +y, a, k, vx, vy, l} = e
  coll.fin(i, e, near.loop(~hit.body, 9n, 0, F32.to_u32((F32.max(x, 0.0) * 0.0625 : F32)),
    F32.to_u32((F32.max(y, 0.0) * 0.0625 : F32)),
    Near{nxt, Scan{i, ents, head, cnt, x, y, vx, vy, False{}}}))

def coll.body(+i: U32, w: W) -> W:
  match w:
    case W{ents, head, nxt, cnt}:
      coll.e(i, head, nxt, cnt, Array.get(Ent, ents, i))

def proj.kill(+i: U32, r: Array<Ent> & Ent) -> Array<Ent>:
  (ents, e) = r
  Array.set(Ent, ents, i, ent.empty())

def proj.fin(+i: U32, ns: Near) -> W:
  match ns:
    case Near{nxt, Scan{me, ents, head, cnt, x, y, vx, vy, hit}}:
      match hit:
        case True{}:
          W{proj.kill(i, Array.get(Ent, ents, i)), head, nxt, cnt}
        case False{}:
          W{ents, head, nxt, cnt}

def proj.go(alive: Bool, +i: U32, e: Ent, ents: Array<Ent>, head: Array<U32>,
  nxt: Array<U32>, cnt: Array<U32>) -> W:
  match alive:
    case False{}:
      W{ents, head, nxt, cnt}
    case True{}:
      Ent{+x, +y, a, k, vx, vy, l} = e
      proj.fin(i, near.loop(~hit.proj, 9n, 0, F32.to_u32((x * 0.0625 : F32)),
        F32.to_u32((y * 0.0625 : F32)),
        Near{nxt, Scan{i, ents, head, cnt, x, y, vx, vy, False{}}}))

def proj.life(e: Ent) -> U32:
  match e:
    case Ent{x, y, a, k, vx, vy, l}:
      l

def proj.e(+i: U32, head: Array<U32>, nxt: Array<U32>, cnt: Array<U32>,
  r: Array<Ent> & Ent) -> W:
  (ents, +e) = r
  proj.go(U32.is_ne(proj.life(e), 0), i, e, ents, head, nxt, cnt)

def proj.hits(+i: U32, w: W) -> W:
  match w:
    case W{ents, head, nxt, cnt}:
      proj.e(i, head, nxt, cnt, Array.get(Ent, ents, i))

# Input and step
# ==============
# Input word: bit 0 fires; bits 8..11 pick one of 16 aim directions.

def aim.v(+a: U32) -> F32:
  ((U32.to_f32(a) - 1.5) * 3.0 : F32)

def spawn(fire: Bool, +slot: U32, +aim: U32, w: W) -> W:
  match fire w:
    case False{} w:
      w
    case True{} W{ents, head, nxt, cnt}:
      W{Array.set(Ent, ents, slot, Ent{640.0, 360.0, 0.0, 4.0,
        aim.v(U32.and(aim, 3)), aim.v(U32.div(aim, 4)), 240}), head, nxt, cnt}

# The recorded input script: bursts of fire every other frame, the aim
# turning every 7 frames.
def input_at(+frame: U32) -> U32:
  +fire = U32.is_zero(U32.and(frame, 1)) && U32.is_ne(U32.mod(U32.div(frame, 60), 3), 2)
  +aim = U32.and(U32.div(frame, 7), 15)
  (Bool.to_u32(fire) + aim * 256 : U32)

def step(s: State, +inp: U32) -> State:
  match s:
    case State{+n, frame, +shot, w}:
      +fire = U32.is_eq(U32.and(inp, 1), 1)
      +nn = U32.to_nat(n)
      w1 = spawn(fire, (2048 + U32.and(shot, 255) : U32), U32.and(U32.div(inp, 256), 15), w)
      w2 = each(~W, ~move.body, nn, 0, w1)
      w3 = each(~W, ~move.proj, 256n, 2048, w2)
      w4 = each(~W, ~grid.clear, 3600n, 0, w3)
      w5 = each(~W, ~grid.ins, nn, 0, w4)
      w6 = each(~W, ~coll.body, nn, 0, w5)
      w7 = each(~W, ~proj.hits, 256n, 2048, w6)
      State{n, (frame + 1 : U32), (shot + Bool.to_u32(fire) : U32), w7}

# Initial state
# =============

def xs(+x: U32) -> U32:
  +a = U32.xor(x, U32.shln(x, 13n))
  +b = U32.xor(a, U32.shrn(a, 17n))
  U32.xor(b, U32.shln(b, 5n))

# A U32 to [0, 1) from its top 24 bits; exact in F32.
def unit(+r: U32) -> F32:
  (U32.to_f32(U32.div(r, 256)) / 16777216.0 : F32)

type Seed is Type:
  Seed{rng: U32, ents: Array<Ent>}

def init.one(+i: U32, s: Seed) -> Seed:
  match s:
    case Seed{rng, ents}:
      +r1 = xs(rng)
      +r2 = xs(r1)
      +r3 = xs(r2)
      +r4 = xs(r3)
      +r5 = xs(r4)
      Seed{r5, Array.set(Ent, ents, i, Ent{(4.0 + unit(r1) * 1272.0 : F32),
        (4.0 + unit(r2) * 712.0 : F32), 0.0, U32.to_f32(U32.and(r5, 3)),
        ((unit(r3) - 0.5) * 4.0 : F32), ((unit(r4) - 0.5) * 4.0 : F32), 0})}

def init.fin(+n: U32, s: Seed) -> State:
  match s:
    case Seed{rng, ents}:
      State{n, 0, 0, W{ents, [0 : U32*4096n], [0 : U32*4096n], [0 : U32*4096n]}}

# n bodies (at most 2048) from a nonzero seed.
def init(+n: U32, seed: U32) -> State:
  init.fin(n, each(~Seed, ~init.one, U32.to_nat(n), 0,
    Seed{seed, Array.new(Ent, 12n, ent.empty())}))

# State hash (FNV-1a over the bits of every live slot)
# ====================================================

type Hs is Type:
  Hs{ents: Array<Ent>, h: U32}

def fnv(+h: U32, +v: U32) -> U32:
  U32.mul(U32.xor(h, v), 16777619)

def hash.ent(+h: U32, e: Ent) -> U32:
  match e:
    case Ent{x, y, a, k, vx, vy, l}:
      fnv(fnv(fnv(fnv(fnv(fnv(fnv(h, F32.bits(x)), F32.bits(y)), F32.bits(a)),
        F32.bits(k)), F32.bits(vx)), F32.bits(vy)), l)

def hash.k(+h: U32, r: Array<Ent> & Ent) -> Hs:
  (ents, e) = r
  Hs{ents, hash.ent(h, e)}

def hash.one(+i: U32, s: Hs) -> Hs:
  match s:
    case Hs{ents, +h}:
      hash.k(h, Array.get(Ent, ents, i))

def hash.fin(+n: U32, +frame: U32, +shot: U32, head: Array<U32>, nxt: Array<U32>,
  cnt: Array<U32>, hs: Hs) -> State & U32:
  match hs:
    case Hs{ents, h}:
      (State{n, frame, shot, W{ents, head, nxt, cnt}}, h)

def hash(s: State) -> State & U32:
  match s:
    case State{+n, +frame, +shot, W{ents, head, nxt, cnt}}:
      hash.fin(n, frame, shot, head, nxt, cnt, each(~Hs, ~hash.one, 256n, 2048,
        each(~Hs, ~hash.one, U32.to_nat(n), 0, Hs{ents, fnv(fnv(2166136261, n), frame)})))

# Render data
# ===========
# Writes the n bodies, then the 256 projectile slots, into out (stride 4).

type Rd is Type:
  Rd{ents: Array<Ent>, out: Array<F32>, off: U32}

def render.put(+o: U32, e: Ent, out: Array<F32>) -> Array<F32>:
  match e:
    case Ent{x, y, a, k, vx, vy, l}:
      +b = (o * 4 : U32)
      Array.set(F32, Array.set(F32, Array.set(F32, Array.set(F32, out, b, x),
        (b + 1 : U32), y), (b + 2 : U32), a), (b + 3 : U32), k)

def render.k(+o: U32, out: Array<F32>, +off: U32, r: Array<Ent> & Ent) -> Rd:
  (ents, e) = r
  Rd{ents, render.put(o, e, out), off}

def render.one(+i: U32, r: Rd) -> Rd:
  match r:
    case Rd{ents, out, +off}:
      render.k((i - off : U32), out, off, Array.get(Ent, ents, i))

def render.re(+n: U32, r: Rd) -> Rd:
  match r:
    case Rd{ents, out, off}:
      Rd{ents, out, (2048 - n : U32)}

def render.fin(+n: U32, +frame: U32, +shot: U32, head: Array<U32>, nxt: Array<U32>,
  cnt: Array<U32>, r: Rd) -> State & Array<F32>:
  match r:
    case Rd{ents, out, off}:
      (State{n, frame, shot, W{ents, head, nxt, cnt}}, out)

def render(s: State, out: Array<F32>) -> State & Array<F32>:
  match s:
    case State{+n, +frame, +shot, W{ents, head, nxt, cnt}}:
      render.fin(n, frame, shot, head, nxt, cnt, each(~Rd, ~render.one, 256n, 2048,
        render.re(n, each(~Rd, ~render.one, U32.to_nat(n), 0, Rd{ents, out, 0}))))
