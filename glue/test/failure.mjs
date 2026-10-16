// The glue's failure rule (glue/README.md), in Node:
//
// - a library misuse (a consumed handle passed again; a full handle table)
//   throws an Error with the library's message, and a forced wasm trap one
//   with the trap; process.exitCode stays unset;
// - after either the instance is poisoned: every call throws, naming the
//   first failure, until reset() (or a fresh import) re-instantiates it;
// - after reset() a handle of the old instance is refused without
//   poisoning, and the new instance computes what the first did;
// - argument errors found before entering wasm throw without poisoning.
//
// `node failure.mjs <step.wasm.mjs> <trap.wasm.mjs>`: the second is
// step.bend's C built with BEND_LIB_SLOTS 4 and glue/test/trap.c appended.
import assert from "node:assert/strict";

const [stepPath, trapPath] = process.argv.slice(2);
const url = (p) => new URL(p, `file://${process.cwd()}/`);
let initHash;
const ok = (what) => console.log(`ok: ${what}`);

const throwsWith = (f, re) => {
  let err = null;
  try {
    f();
  } catch (e) {
    err = e;
  }
  assert.ok(err instanceof Error, `no Error thrown, want ${re}`);
  assert.match(err.message, re);
  return err;
};

const poisoned = (G, first) => {
  for (const f of [() => G.init(500, 12345), () => G.input_at(0)]) {
    const e = throwsWith(f, /^bend-wasm: the instance is poisoned/);
    assert.equal(e.cause, first);
  }
};

{
  const lane = await import(url(stepPath));
  const G = lane.default;
  assert.deepEqual(Object.keys(G).sort(),
    ["hash", "init", "input_at", "render", "step"]);
  const h0 = G.hash(G.init(500, 12345));
  initHash = h0.snd.toString();
  const s0 = G.init(500, 12345);
  const s1 = G.step(s0, G.input_at(0));
  assert.equal(String(s1), "[bend handle State]");
  assert.deepEqual(Object.keys(s1), []);

  throwsWith(() => G.step({}, 0), /not a handle of this module/);
  throwsWith(() => G.render(s1, new Float32Array(10)),
    /Float32Array of 16384 floats/);
  assert.equal(G.input_at(3), G.input_at(3));
  ok("argument errors throw before wasm and do not poison");

  const first = throwsWith(() => G.step(s0, 0),
    /^bend: step: a handle that was consumed, disposed or never made \(handle 0x[0-9a-f]+\)$/);
  assert.equal(process.exitCode, undefined);
  poisoned(G, first);
  throwsWith(() => G.hash(s1), /^bend-wasm: the instance is poisoned/);
  ok(`misuse: "${first.message}", then poisoned`);

  await lane.reset();
  throwsWith(() => G.hash(s1), /^bend-wasm: hash: a State handle of an instance before reset\(\)$/);
  const h1 = G.hash(G.init(500, 12345));
  assert.equal(h1.snd, h0.snd);
  assert.deepEqual(lane.stats().handles, 1);
  ok("reset(): old handles refused, the new instance hashes as the first");
}

{
  const lane = await import(url(trapPath));
  const G = lane.default;
  const first = throwsWith(() => G.trap(),
    /^bend-wasm: trap: wasm trap: RuntimeError: unreachable/);
  assert.ok(first.cause instanceof WebAssembly.RuntimeError);
  poisoned(G, first);
  ok(`trap: "${first.message}", then poisoned`);

  await lane.reset();
  const hs = [1, 2, 3, 4].map((n) => G.init(n, 12345));
  const full = throwsWith(() => G.init(5, 12345),
    /^bend: every handle slot is in use \(BEND_LIB_SLOTS\)$/);
  poisoned(G, full);
  assert.equal(process.exitCode, undefined);
  ok(`full table after reset(): "${full.message}", then poisoned`);

  const fresh = await import(url(trapPath + "?fresh"));
  const s = fresh.default.init(500, 12345);
  assert.equal(fresh.default.hash(s).snd.toString(), initHash);
  throwsWith(() => fresh.default.step(hs[0], 0), /not a handle of this module/);
  poisoned(G, full);
  ok("a fresh import is a new instance; the old one stays poisoned");
}
assert.equal(process.exitCode, undefined);
