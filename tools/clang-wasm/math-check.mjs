// Compares the plain-clang build's musl code with emcc's, bit for bit
// (TODO t-fwjpak4c, step C; tools/clang-wasm/math-check.sh builds both):
//
//   node math-check.mjs PLAIN.wasm EMCC.mjs
//
// It calls every function the plain build takes from tools/clang-wasm/libc.sh's
// archive through math-check.c in both modules, over edge vectors and a
// seeded random sample, and compares the bits of each result (strtof and
// strtod: also the bytes taken; %e and %f: the bytes of the text). It
// prints per function the calls and how many differ, the first 40
// differences in full, and exits 1 if there is one.
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const [plainFile, emccFile] = process.argv.slice(2);
if (emccFile === undefined) {
  console.error("usage: math-check.mjs PLAIN.wasm EMCC.mjs");
  process.exit(2);
}

// The two builds behind one interface.
function wrap(x, heap) {
  const buf = x.mc_buf();
  const enc = new TextEncoder();
  const dec = new TextDecoder();
  const u64 = (r) => BigInt.asUintN(64, r);
  return {
    f1: (op, a) => u64(x.mc_f1(op, a)),
    f2: (op, a, b) => u64(x.mc_f2(op, a, b)),
    fmodf: (a, b) => x.mc_fmodf(a, b) >>> 0,
    strto: (f, s) => {
      const b = enc.encode(s);
      heap().set(b, buf);
      heap()[buf + b.length] = 0;
      const r = f === "f" ? x.mc_strtof() >>> 0 : u64(x.mc_strtod());
      const n = new DataView(heap().buffer).getInt32(buf + 8188, true);
      return `${r.toString(16)} +${n}`;
    },
    fmt: (v, prec, conv) => {
      const n = x.mc_fmt(v, prec, conv.charCodeAt(0));
      return n < 0 ? `error ${n}` : dec.decode(heap().subarray(buf, buf + n));
    },
  };
}

const plainInst = (await WebAssembly.instantiate(readFileSync(plainFile), {}))
  .instance.exports;
const plain = wrap(plainInst, () => new Uint8Array(plainInst.memory.buffer));
const M = await (await import(pathToFileURL(emccFile).href)).default();
const emcc = wrap({
  mc_buf: M._mc_buf, mc_f1: M._mc_f1, mc_f2: M._mc_f2, mc_fmodf: M._mc_fmodf,
  mc_strtof: M._mc_strtof, mc_strtod: M._mc_strtod, mc_fmt: M._mc_fmt,
}, () => M.HEAPU8);

// Bits.
const f64 = new Float64Array(1);
const u64v = new BigUint64Array(f64.buffer);
const f32 = new Float32Array(1);
const u32v = new Uint32Array(f32.buffer);
const bitsOf = (x) => { f64[0] = x; return u64v[0]; };
const valOf = (b) => { u64v[0] = b; return f64[0]; };
const fbitsOf = (x) => { f32[0] = x; return u32v[0]; };
const fvalOf = (b) => { u32v[0] = b; return f32[0]; };

// xorshift64*, seeded: the sample is the same on every run.
let seed = 0x9e3779b97f4a7c15n;
function rnd64() {
  seed ^= seed >> 12n;
  seed ^= (seed << 25n) & 0xffffffffffffffffn;
  seed ^= seed >> 27n;
  return (seed * 0x2545f4914f6cdd1dn) & 0xffffffffffffffffn;
}
const rnd = () => Number(rnd64() >> 11n) / 2 ** 53;
const range = (a, b) => a + (b - a) * rnd();

// Edge doubles, as bits.
const SPECIAL = [
  0n, 0x8000000000000000n, 0x7ff0000000000000n, 0xfff0000000000000n,
  0x7ff8000000000000n, 0xfff8000000000000n, 0x7ff8000000000001n,
  0x7ff0000000000001n, 0x7ff4000000000000n, 0x7fffffffffffffffn,
  0xffffffffffffffffn, 0x7ff0deadbeef0001n, 0xfff00000000000ffn,
  1n, 2n, 0x000fffffffffffffn, 0x0008000000000000n, 0x8000000000000001n,
  0x800fffffffffffffn, 0x0010000000000000n, 0x8010000000000000n,
  0x7fefffffffffffffn, 0xffefffffffffffffn,
];
const NUMBERS = [
  1, -1, 0.5, -0.5, 2, 3, 10, 0.1, 0.7071067811865476, 1e-8, 1e-300,
  1e-310, 1e300, 1e22, 2 ** 53, 2 ** 53 + 2, 2 ** 1023, 2 ** -1022,
  2 ** -1074, 709.782712893384, 709.79, 710, 710.4758600739439, -708,
  -745.1332191019411, -745.14, -746, 88.72283905206835, 89.4, 1e15,
  1e300, 3.4028234663852886e38, 1.1754943508222875e-38, 1.401298464324817e-45,
  Math.PI, Math.E, Math.LN2, Math.SQRT2, 0.99, 1.01, 20, 22, 40, 100,
];
for (let k = -12; k <= 12; k += 1) {
  NUMBERS.push(k * Math.PI / 2, k * Math.PI / 4);
}
for (const k of [1e3, 1e5, 1e6, 2 ** 20, 2 ** 30, 2 ** 52, 1e15, 1e22, 1e100]) {
  NUMBERS.push(k * Math.PI / 2, (k + 1) * Math.PI / 2, k);
}
for (let i = 0; i < 30; i += 1) {
  NUMBERS.push(Math.fround(range(-10, 10)));
}
const EDGE = [];
for (const b of [...SPECIAL, ...NUMBERS.flatMap((x) => [bitsOf(x), bitsOf(-x)])]) {
  EDGE.push(b);
  const e = (b >> 52n) & 0x7ffn;
  if (e !== 0x7ffn && (b & 0x7fffffffffffffffn) !== 0n) {
    for (const d of [-2n, -1n, 1n, 2n]) {
      const n = b + d;
      if (((n >> 52n) & 0x7ffn) !== 0x7ffn) {
        EDGE.push(BigInt.asUintN(64, n));
      }
    }
  }
}
const SMALL_EDGE = [...SPECIAL, ...[0.5, 1, 2, 3, 10, 0.1, 1e-300, 1e300,
  Math.PI / 2, 2 ** 53, 0.99, 1.01, 1023.5, -1074, 1e-310]
  .flatMap((x) => [bitsOf(x), bitsOf(-x)])];

function sample(n, gen) {
  const out = [];
  for (let i = 0; i < n; i += 1) {
    out.push(gen());
  }
  return out;
}
const RANDOM = [
  ...sample(4000, rnd64),
  ...sample(4000, () => bitsOf(range(-10, 10))),
  ...sample(2000, () => bitsOf(range(-1000, 1000))),
  ...sample(2000, () => bitsOf(range(-1, 1))),
  ...sample(2000, () => bitsOf((rnd() < 0.5 ? -1 : 1) * Math.exp(range(-745, 709)))),
];
const DOUBLES = [...EDGE, ...RANDOM];

// The comparison.
const counts = new Map();
const differ = new Map();
const diffs = [];
function same(fn, input, a, b) {
  counts.set(fn, (counts.get(fn) ?? 0) + 1);
  if (a !== b) {
    differ.set(fn, (differ.get(fn) ?? 0) + 1);
    diffs.push(`${fn}(${input}): plain ${a}, emcc ${b}`);
  }
}
const hex = (b) => `0x${b.toString(16)}`;

const UNARY = ["exp", "log", "log2", "log10", "sin", "cos", "tan", "asin",
  "acos", "atan", "sinh", "cosh", "tanh"];
for (let op = 0; op < UNARY.length; op += 1) {
  for (const x of DOUBLES) {
    same(UNARY[op], hex(x), hex(plain.f1(op, x)), hex(emcc.f1(op, x)));
  }
}

const PAIRS = [];
for (const x of SMALL_EDGE) {
  for (const y of SMALL_EDGE) {
    PAIRS.push([x, y]);
  }
}
PAIRS.push(
  ...sample(5000, () => [rnd64(), rnd64()]),
  ...sample(5000, () => [bitsOf(range(-10, 10)), bitsOf(range(-10, 10))]),
);
const POW = [
  ...sample(5000, () => [bitsOf(range(0, 10)), bitsOf(range(-30, 30))]),
  ...sample(2000, () => [bitsOf(-range(0, 10)), bitsOf(Math.round(range(-40, 40)))]),
  ...sample(2000, () => [bitsOf(1 + range(-1e-9, 1e-9)), bitsOf(range(-1e12, 1e12))]),
  ...sample(1000, () => [bitsOf(range(0, 2)), bitsOf(range(-1100, 1100))]),
];
for (const [x, y] of PAIRS) {
  same("atan2", `${hex(x)}, ${hex(y)}`, hex(plain.f2(0, x, y)), hex(emcc.f2(0, x, y)));
}
for (const [x, y] of [...PAIRS, ...POW]) {
  same("pow", `${hex(x)}, ${hex(y)}`, hex(plain.f2(1, x, y)), hex(emcc.f2(1, x, y)));
}

const FSPECIAL = [0, 0x80000000, 0x7f800000, 0xff800000, 0x7fc00000,
  0xffc00000, 0x7fc00001, 0x7f800001, 0x7fa00000, 0x7fffffff, 1, 2, 0x007fffff,
  0x00400000, 0x80000001, 0x00800000, 0x80800000, 0x7f7fffff, 0xff7fffff];
const FEDGE = [...FSPECIAL, ...[1, 0.5, 2, 3, 10, 0.1, 1e-38, 1e38, Math.PI,
  7, 1.5, 2 ** 24, 2 ** -126, 1e-45].flatMap((x) => [fbitsOf(x), fbitsOf(-x)])];
const FPAIRS = [];
for (const x of FEDGE) {
  for (const y of FEDGE) {
    FPAIRS.push([x, y]);
  }
}
FPAIRS.push(
  ...sample(10000, () => [Number(rnd64() >> 32n), Number(rnd64() >> 32n)]),
  ...sample(5000, () => [fbitsOf(range(-1000, 1000)), fbitsOf(range(-10, 10))]),
  ...sample(2000, () => [fbitsOf(range(-3e38, 3e38)), fbitsOf(range(-1e-3, 1e-3))]),
);
for (const [x, y] of FPAIRS) {
  same("fmodf", `0x${x.toString(16)}, 0x${y.toString(16)}`,
    plain.fmodf(x, y).toString(16), emcc.fmodf(x, y).toString(16));
}

// Exact decimal text of m * 2^e (m, e BigInt, m >= 0).
function decimal(m, e) {
  if (e >= 0n) {
    return (m << e).toString();
  }
  const s = (m * 5n ** -e).toString().padStart(Number(-e) + 1, "0");
  const k = s.length - Number(-e);
  return `${s.slice(0, k)}.${s.slice(k)}`;
}
// Halfway between a finite positive value and the next one up, exactly.
function halfway(b, mant, bias) {
  const fbits = BigInt(mant);
  const ex = b >> fbits;
  const fr = b & ((1n << fbits) - 1n);
  const m = ex === 0n ? fr : fr | (1n << fbits);
  const e = (ex === 0n ? 1n : ex) - BigInt(bias) - fbits;
  return decimal(2n * m + 1n, e - 1n);
}

const STRINGS = ["0", "-0", "+0", "0.0", "inf", "-INF", "infinity",
  "-Infinity", "infinit", "nan", "NAN", "-nan", "nan(123)", "nan(0x7ff)",
  "nan(", "1e309", "-1e309", "1e-400", "4.9406564584124654e-324",
  "2.4703282292062327e-324", "2.4703282292062328e-324",
  "2.47032822920623272088e-324", "0x1p-1074", "0x1p-1075", "0x1.8p-1075",
  "0x1.fffffffffffffp1023", "0x1.fffffffffffff8p1023", "0x1.fffffffffffff7p1023",
  "1.7976931348623157e308", "1.7976931348623158e308", "1.7976931348623159e308",
  "9007199254740993", "9007199254740995", "9007199254740993.0000000001",
  "1.00000005960464477539062500", "1.000000059604644775390625000001",
  "1.0000000596046447753906249999", "3.4028235677973366e38",
  "3.4028235677973362e38", "3.4028236e38", "16777217", "16777219",
  "1.17549435e-38", "1.4e-45", "7e-46", "7.006492321624085e-46",
  "0.1", "1e23", "8.98846567431158e307", " 12abc", "\t\n 3.5x", "+.5", ".",
  "", "e5", "1e", "1e+", "1e+x", "0x", "0x.8p1", "0X1P4", "0x1p", "0x1.p0",
  "1.5E-5", "7.038531e-26", "2.2250738585072011e-308",
  "2.2250738585072012e-308", "2.2250738585072014e-308", "123456789012345678901234567890",
  `0.${"0".repeat(330)}1`, `${"9".repeat(400)}`, `1${"0".repeat(308)}`,
  `0.${"3".repeat(800)}`, "4GB", "4", "-12.5e-3", "1_000", "١"];
for (let i = 0; i < 2500; i += 1) {
  // A random finite double, positive, in all its forms.
  let b;
  do {
    b = rnd64() & 0x7fffffffffffffffn;
  } while ((b >> 52n) === 0x7ffn);
  const x = valOf(b);
  const h = halfway(b, 52, 1023);
  STRINGS.push(String(x), x.toExponential(16), x.toPrecision(17), h, `-${h}`,
    `${h}1`, h.length > 20 ? h.slice(0, -1) : h);
}
for (let i = 0; i < 2500; i += 1) {
  let b;
  do {
    b = Number(rnd64() >> 33n);
  } while ((b >>> 23) === 0xff);
  const x = fvalOf(b);
  const h = halfway(BigInt(b), 23, 127);
  STRINGS.push(String(x), x.toPrecision(9), h, `-${h}`, `${h}1`,
    h.length > 12 ? h.slice(0, -1) : h);
}
for (let i = 0; i < 2000; i += 1) {
  const x = range(-1e6, 1e6);
  STRINGS.push(String(x), x.toFixed(3), x.toExponential(8));
}
for (const s of STRINGS) {
  same("strtof", JSON.stringify(s), plain.strto("f", s), emcc.strto("f", s));
  same("strtod", JSON.stringify(s), plain.strto("d", s), emcc.strto("d", s));
}

// Formatting: every double above at a range of precisions, and ties.
const FMT = [...EDGE, ...sample(2000, rnd64),
  ...sample(2000, () => bitsOf(range(-1e6, 1e6))),
  ...sample(1000, () => bitsOf(Math.fround(range(-100, 100))))];
const TIES = [];
for (let k = 1; k <= 14; k += 1) {
  for (let m = 1; m < 64; m += 2) {
    TIES.push([bitsOf(m / 2 ** k), k - 1, "f"], [bitsOf(-m / 2 ** k), k - 1, "f"]);
  }
}
for (const x of [125, 135, 2.5, 3.5, 1.25, 1.35, 2 ** 60, 2 ** 70, 5e-324,
  0.5, 1.5, 9.5, 99.5, 999.5, 1e22, 1e23]) {
  for (let p = 0; p <= 20; p += 1) {
    TIES.push([bitsOf(x), p, "e"], [bitsOf(-x), p, "e"]);
  }
}
const PRECS = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15, 16, 17, 20, 30, 60];
for (const v of FMT) {
  for (const p of PRECS) {
    for (const c of ["e", "f"]) {
      TIES.push([v, p, c]);
    }
  }
}
for (const [v, p, c] of TIES) {
  same(`%.${p}${c}`.replace(/\d+/, "*"), `${hex(v)}, ${p}`,
    JSON.stringify(plain.fmt(v, p, c)), JSON.stringify(emcc.fmt(v, p, c)));
}

for (const [fn, n] of counts) {
  console.log(`${fn}: ${n} calls, ${differ.get(fn) ?? 0} differ`);
}
if (diffs.length > 0) {
  console.log(`DIFFERENCES: ${diffs.length}`);
  for (const d of diffs.slice(0, 40)) {
    console.log(d);
  }
  process.exit(1);
}
console.log(`all ${[...counts.values()].reduce((a, b) => a + b, 0)} calls`
  + " give the same bits");
