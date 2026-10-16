// Writes the wasm lane's module of a library-mode C (glue/README.md):
//
//   node glue/gen.mjs exports FILE.c        the -sEXPORTED_FUNCTIONS list
//   node glue/gen.mjs module FILE.c NAME [emcc|clang]
//                                           NAME.wasm.mjs on stdout
//
// The module opens NAME.lib.wasm; for the Emscripten build (emcc, the
// default) through its factory NAME.lib.mjs, for the plain-clang build
// (tools/clang-wasm/build.sh) directly (glue/load-clang.mjs).
//
// The defs and how each crosses come from the line patch 0003 writes above
// every exported def, e.g.
//
//   // render: consumes State, Array<F32> from the F32 region -> a handle
//   //   of State & Array<F32> into the F32 region   (one line in the C)
//   u64 bend_def_render(u64 a0) {
//
// An argument is U32, F32, Nat, "consumes T", "borrows T" or "Array<F32>
// from the F32 region"; a result part U32, F32, Nat, "a handle of T" or
// "Array<F32> into the F32 region", parts after the first written through
// "*rI = ". Anything else, or a C parameter list that does not follow from
// the line, stops the generator, so a change of the emitter shows here.
import { readFileSync } from "node:fs";

const [mode, file, name, build = "emcc"] = process.argv.slice(2);

function die(msg) {
  console.error(`glue/gen.mjs: ${file}: ${msg}`);
  process.exit(1);
}

const SCALAR = new Set(["U32", "F32", "Nat"]);
const CTY = { U32: "u32", F32: "float", Nat: "u64", handle: "u64" };

function arg(s) {
  if (SCALAR.has(s)) {
    return { k: s };
  }
  if (s === "Array<F32> from the F32 region") {
    return { k: "Array" };
  }
  const m = /^(consumes|borrows) (\S+)$/.exec(s);
  if (m !== null) {
    return { k: "handle", type: m[2] };
  }
  return die(`an argument the glue does not know: "${s}"`);
}

function part(s, i) {
  if (s === "Array<F32> into the F32 region") {
    return { k: "Array" };
  }
  const m = /^\*r(\d+) = (.*)$/.exec(s);
  if (i > 0 && (m === null || Number(m[1]) !== i)) {
    return die(`result part ${i} is not written through *r${i}: "${s}"`);
  }
  const t = i > 0 ? m[2] : s;
  if (SCALAR.has(t)) {
    return { k: t };
  }
  const h = /^a handle of (\S+)$/.exec(t);
  if (h !== null) {
    return { k: "handle", type: h[1] };
  }
  return die(`a result part the glue does not know: "${s}"`);
}

function defs(c) {
  const lines = c.split("\n");
  const out = [];
  for (let i = 0; i + 1 < lines.length; i += 1) {
    const f = /^(\w+) (bend_def_\w+)\((.*)\) \{$/.exec(lines[i + 1]);
    if (f === null) {
      continue;
    }
    const d = /^\/\/ (\S+): (.*) -> (.*)$/.exec(lines[i]);
    if (d === null) {
      die(`no signature line above ${f[2]}`);
    }
    const ins = d[2] === "no arguments" ? [] : d[2].split(", ").map(arg);
    const parts = d[3].split(" & ").map(part);
    // the C parameters that follow from the line
    const want = [...ins.flatMap((a, j) => a.k === "Array" ? []
      : [`${CTY[a.k]} a${j}`]), ...parts.slice(1).flatMap((p, j) =>
      p.k === "Array" ? [] : [`${CTY[p.k]}* r${j + 1}`])].join(", ")
      || "void";
    const ret = parts[0].k === "Array" ? "void" : CTY[parts[0].k];
    if (want !== f[3] || ret !== f[1]) {
      die(`${f[2]} is "${f[1]} (${f[3]})", its line says "${ret}`
        + ` (${want})"`);
    }
    out.push({ key: d[1], c: f[2], ins, parts });
  }
  if (out.length === 0) {
    die("no bend_def_ functions: not a --lib build");
  }
  return out;
}

// The wrapper of one def: checks that need no wasm call, the call, the
// result in the JS lane's shape.
function wrap(d) {
  const ps = d.ins.map((_, j) => `a${j}`);
  const key = JSON.stringify(d.key);
  const pre = [];
  const cargs = [];
  const arr = d.ins.findIndex((a) => a.k === "Array");
  d.ins.forEach((a, j) => {
    if (a.k === "handle") {
      pre.push(`const h${j} = L.take(a${j}, ${key});`);
      cargs.push(`h${j}`);
    } else if (a.k === "Nat") {
      pre.push(`if (typeof a${j} !== "bigint") throw new TypeError(`
        + `"bend-wasm: " + ${key} + ": a Nat crosses as a BigInt");`);
      cargs.push(`a${j}`);
    } else if (a.k === "Array") {
      pre.push(`L.arrIn(a${j}, ${key});`);
    } else {
      cargs.push(`a${j}`);
    }
  });
  d.parts.slice(1).forEach((p, j) => {
    if (p.k !== "Array") {
      cargs.push(`L.ptr(${j})`);
    }
  });
  const read = (p, j) => {
    const v = j === 0 ? "r" : p.k === "U32" ? `L.u32(${j - 1})`
      : p.k === "F32" ? `L.f32(${j - 1})` : `L.u64(${j - 1})`;
    if (p.k === "Array") {
      return `L.arrOut(${arr >= 0 ? `a${arr}` : "null"})`;
    }
    if (p.k === "handle") {
      return `L.handle(${v}, ${JSON.stringify(p.type)})`;
    }
    if (p.k === "U32" && j === 0) {
      return "r >>> 0";
    }
    return v;
  };
  // A & B & C is {fst: A, snd: {fst: B, snd: C}}, as the JS lane nests it
  const tuple = (j) => j === d.parts.length - 1 ? read(d.parts[j], j)
    : `{ $: "Tuple", fst: ${read(d.parts[j], j)}, snd: ${tuple(j + 1)} }`;
  return `  ${key}: (${ps.join(", ")}) => {
    ${[...pre, "const ex = L.enter();"].join("\n    ")}
    let r;
    try {
      r = ex.${d.c}(${cargs.join(", ")});
    } catch (e) {
      throw L.fail(${key}, e);
    }
    L.leave();
    return ${tuple(0)};
  },`;
}

const ds = defs(readFileSync(file, "utf8"));
if (mode === "exports") {
  console.log(["_bend_init", "_bend_dispose", "_bend_heap_words",
    "_bend_handles", "_bend_f32", "_bend_f32_len", "_malloc",
    ...ds.map((d) => "_" + d.c)].join(","));
} else if (mode === "module" && name !== undefined
  && (build === "emcc" || build === "clang")) {
  const slots = Math.max(0, ...ds.map((d) => d.parts.length - 1));
  const load = build === "emcc"
    ? { line: `\nimport load from "./${name}.lib.mjs";`, arg: "load" }
    : { line: "", arg: "null" };
  console.log(`// Generated by glue/gen.mjs from ${file.split("/").pop()}: the wasm
// lane of ${name} with the JS lane's shape (glue/README.md). The default
// export has the exported defs; reset() re-instantiates a poisoned
// instance, dispose(h) drops a handle the host will not pass on,
// timings() and stats() are for measurements.
import { open } from "./bend-glue.mjs";${load.line}

const L = await open(${load.arg}, new URL("./${name}.lib.wasm", import.meta.url),
  ${slots});

export default {
${ds.map(wrap).join("\n")}
};

export const reset = () => L.start();
export const dispose = (h) => L.dispose(h);
export const timings = () => ({ ...L.timings });
export const stats = () => L.stats();`);
} else {
  die("usage: gen.mjs exports FILE.c"
    + " | gen.mjs module FILE.c NAME [emcc|clang]");
}
