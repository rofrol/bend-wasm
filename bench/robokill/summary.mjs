// Summarizes the page's results of bench/robokill/run.sh: one JSON per
// block and lane, named <block>-<lane>.json, as main.js posts them to
// serve.mjs. Prints a Markdown report: per run step+upload p50, p95, p99,
// max and frames over 4 ms; per n and lane the median of the blocks; the
// paired ratio wasm / JS of each block's p50 and p95; per n, lane and
// memory mark (after init, after the replay) the median of the blocks'
// wasm linear memory, tab memory (measureUserAgentSpecificMemory), renderer
// RSS and renderer footprint; load times. Checks that every run finished,
// that both lanes recorded the same checkpoint hashes and that the final
// ones are RESULTS.md's, and that every mark has its memory numbers but the
// optional footprint.
//
// When every check holds it also writes <dir>/baseline.json (atomically),
// the frozen emcc baseline of the clang cutover criteria (DECISIONS.md,
// "When plain clang replaces emcc"): the shipped sizes of both lanes from
// <dist> (each file raw and `gzip -9 -n`), the wasm lane's linear memory,
// the memory medians and Chrome's step+upload p50/p95 medians per n.
// `node summary.mjs <dir> [<dist>]`, <dist> defaulting to ./dist beside
// this script; exit status 1 when a check fails.
import { execFileSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, renameSync, statSync,
  writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const [dir, dist = fileURLToPath(new URL("dist", import.meta.url))] =
  process.argv.slice(2);
// What the page loads per lane (main.js, the lane's imports).
const SHIPPED = { js: ["step.mjs"],
  wasm: ["step.wasm.mjs", "bend-glue.mjs", "step.lib.mjs", "step.lib.wasm"] };
const FINAL = { 500: 603820250, 2000: 819172968 };
const runs = readdirSync(dir).flatMap((f) => {
  const m = /^(\d+)-(js|wasm)\.json$/.exec(f);
  return m === null ? [] : [{ block: Number(m[1]), lane: m[2],
    r: JSON.parse(readFileSync(join(dir, f), "utf8")) }];
}).sort((a, b) => a.block - b.block || a.lane.localeCompare(b.lane));
const bad = [];
const f3 = (x) => x.toFixed(3);
const median = (xs) => [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)];

for (const { block, lane, r } of runs) {
  if (r.error !== undefined || r.lane !== lane) {
    bad.push(`block ${block} ${lane}: ${r.error ?? `lane ${r.lane}`}`);
  }
}
const ok = runs.filter(({ r }) => r.error === undefined);
const one = (block, lane, n) => ok.find((x) => x.block === block
  && x.lane === lane)?.r.runs.find((x) => x.n === n);
const sizes = [...new Set(ok.flatMap(({ r }) => r.runs.map((x) => x.n)))];
const blocks = [...new Set(runs.map((x) => x.block))];

const lines = [];
const first = ok[0]?.r;
if (first !== undefined) {
  lines.push(`${first.userAgent}; adapter ${JSON.stringify(first.adapter)};`
    + ` crossOriginIsolated ${first.crossOriginIsolated}.`, "");
}
lines.push("| block | lane | n | p50 | p95 | p99 | max | over 4 ms |",
  "| --- | --- | --- | --- | --- | --- | --- | --- |");
for (const { block, lane, r } of ok) {
  for (const x of r.runs) {
    const s = x.stepUploadMs;
    lines.push(`| ${block} | ${lane} | ${x.n} | ${f3(s.p50)} | ${f3(s.p95)} |`
      + ` ${f3(s.p99)} | ${f3(s.max)} | ${s.over4ms} |`);
    const h = x.hashes.at(-1);
    if (h?.frame !== x.frames || (x.frames === 10000 && h.hash !== FINAL[x.n])) {
      bad.push(`block ${block} ${lane} n=${x.n}: final hash ${JSON.stringify(h)}`);
    }
    const js = one(block, "js", x.n);
    if (js !== undefined && JSON.stringify(js.hashes) !== JSON.stringify(x.hashes)) {
      bad.push(`block ${block} n=${x.n}: the lanes' checkpoint hashes differ`);
    }
  }
}
lines.push("", "Median over blocks, step+upload ms:", "",
  "| n | lane | p50 | p95 | p99 | max |", "| --- | --- | --- | --- | --- | --- |");
for (const n of sizes) {
  for (const lane of ["js", "wasm"]) {
    const xs = blocks.map((b) => one(b, lane, n)).filter(Boolean)
      .map((x) => x.stepUploadMs);
    if (xs.length > 0) {
      lines.push(`| ${n} | ${lane} | ${["p50", "p95", "p99", "max"].map((k) =>
        f3(median(xs.map((s) => s[k])))).join(" | ")} |`);
    }
  }
}
lines.push("", "Paired ratio wasm / JS per block, p50 / p95:", "");
for (const n of sizes) {
  const rs = blocks.flatMap((b) => {
    const j = one(b, "js", n);
    const w = one(b, "wasm", n);
    return j && w ? [[w.stepUploadMs.p50 / j.stepUploadMs.p50,
      w.stepUploadMs.p95 / j.stepUploadMs.p95]] : [];
  });
  lines.push(`- n = ${n}: ${rs.map(([a, b]) => `${f3(a)} / ${f3(b)}`).join(", ")}`
    + (rs.length > 0 ? `; median ${f3(median(rs.map((x) => x[0])))} /`
      + ` ${f3(median(rs.map((x) => x[1])))}` : ""));
}
// Memory: per mark the four numbers in bytes (null when not measured).
const EVENTS = ["init", "replay"];
const notes = [];
const numbers = (m) => ({
  wasmMemoryBytes: m.wasmMemoryBytes,
  uaMemoryBytes: m.uaMemory?.bytes ?? null,
  rendererRssBytes: m.os?.renderer ? m.os.renderer.rssKiB * 1024 : null,
  rendererFootprintBytes: m.os?.footprint?.physFootprint ?? null,
});
for (const { block, lane, r } of ok) {
  for (const x of r.runs) {
    for (const event of EVENTS) {
      const m = x.memory?.find((y) => y.event === event);
      const at = `block ${block} ${lane} n=${x.n} ${event}`;
      if (m === undefined) {
        bad.push(`${at}: no memory mark`);
        continue;
      }
      if (lane === "wasm" && m.wasmMemoryBytes === null) {
        bad.push(`${at}: no wasm linear memory`);
      }
      if (r.crossOriginIsolated && m.uaMemory === null) {
        bad.push(`${at}: no measureUserAgentSpecificMemory`);
      }
      if (!m.os?.renderer) {
        bad.push(`${at}: no renderer: ${m.os?.error ?? "no reply from serve.mjs"}`);
      } else {
        if (m.os.candidates.length > 1) {
          notes.push(`${at}: ${m.os.candidates.length} renderers, took pid`
            + ` ${m.os.renderer.pid} (most CPU): ${JSON.stringify(m.os.candidates)}`);
        }
        if (m.os.footprint?.physFootprint == null) {
          notes.push(`${at}: no footprint: ${m.os.footprint?.error}`);
        }
      }
    }
  }
}
const KEYS = ["wasmMemoryBytes", "uaMemoryBytes", "rendererRssBytes",
  "rendererFootprintBytes"];
const memMedian = (lane, n, event) => {
  const ms = blocks.map((b) => one(b, lane, n)?.memory
    ?.find((y) => y.event === event)).filter(Boolean).map(numbers);
  return Object.fromEntries(KEYS.map((k) => {
    const xs = ms.map((m) => m[k]).filter((v) => v !== null);
    return [k, xs.length > 0 ? median(xs) : null];
  }));
};
const mib = (b) => (b === null ? "-" : (b / 2 ** 20).toFixed(1));
lines.push("", "Memory, median over blocks, MiB: the wasm lane's linear memory,"
  + " the tab's (measureUserAgentSpecificMemory: JS and wasm, not the GPU's),"
  + " the renderer process's RSS and footprint (phys_footprint):", "",
  "| n | lane | mark | linear | tab | RSS | footprint |",
  "| --- | --- | --- | --- | --- | --- | --- |");
const memory = { js: {}, wasm: {} };
for (const n of sizes) {
  for (const lane of ["js", "wasm"]) {
    for (const event of EVENTS) {
      const m = memMedian(lane, n, event);
      (memory[lane][n] ??= {})[event] = m;
      lines.push(`| ${n} | ${lane} | ${event} | ${KEYS.map((k) => mib(m[k]))
        .join(" | ")} |`);
    }
  }
}
const linear = [...new Set(ok.filter((x) => x.lane === "wasm")
  .flatMap(({ r }) => r.runs.flatMap((x) => x.memory ?? []))
  .map((m) => m.wasmMemoryBytes).filter((v) => v !== null))];
if (linear.length > 1) {
  bad.push(`the wasm lane's linear memory changed: ${linear.join(", ")} bytes`);
}

lines.push("", "Load (ms):", "");
for (const { block, lane, r } of ok) {
  const l = Object.entries(r.load ?? {}).map(([k, v]) => `${k} ${f3(v)}`)
    .join(", ");
  lines.push(`- block ${block} ${lane}: ${l}`);
}

// Shipped sizes: each file as the page fetches it, raw and gzip -9.
const shipped = {};
for (const [lane, files] of Object.entries(SHIPPED)) {
  shipped[lane] = { files: {}, total: { raw: 0, gzip9: 0 } };
  for (const f of files) {
    const p = join(dist, f);
    if (!existsSync(p)) {
      bad.push(`shipped file ${p} is missing`);
      continue;
    }
    const raw = statSync(p).size;
    const gzip9 = execFileSync("gzip", ["-9", "-n", "-c"],
      { input: readFileSync(p), maxBuffer: 2 ** 30 }).length;
    shipped[lane].files[f] = { raw, gzip9 };
    shipped[lane].total.raw += raw;
    shipped[lane].total.gzip9 += gzip9;
  }
}
lines.push("", "Shipped files, bytes raw / gzip -9:", "");
for (const [lane, s] of Object.entries(shipped)) {
  lines.push(`- ${lane}: ${Object.entries(s.files).map(([f, x]) =>
    `${f} ${x.raw} / ${x.gzip9}`).join(", ")}; total ${s.total.raw} /`
    + ` ${s.total.gzip9}`);
}
if (notes.length > 0) {
  lines.push("", ...notes.map((x) => `Note: ${x}`));
}
if (bad.length > 0) {
  lines.push("", ...bad.map((b) => `FAILED: ${b}`));
}
if (bad.length === 0 && runs.length > 0) {
  const chrome = { js: {}, wasm: {} };
  for (const n of sizes) {
    for (const lane of ["js", "wasm"]) {
      const xs = blocks.map((b) => one(b, lane, n)).filter(Boolean)
        .map((x) => x.stepUploadMs);
      chrome[lane][n] = { p50: median(xs.map((s) => s.p50)),
        p95: median(xs.map((s) => s.p95)) };
    }
  }
  const toolchain = join(dir, "toolchain.txt");
  const baseline = {
    what: "Frozen emcc baseline of the clang cutover criteria"
      + " (bench/robokill/README.md); medians over blocks",
    toolchain: existsSync(toolchain) ? readFileSync(toolchain, "utf8").trim() : null,
    userAgent: first.userAgent,
    adapter: first.adapter,
    blocks: blocks.length,
    frames: first.runs[0]?.frames,
    shipped,
    linearMemoryBytes: linear[0] ?? null,
    memory,
    chromeStepUploadMs: chrome,
  };
  const path = join(dir, "baseline.json");
  writeFileSync(path + ".tmp", JSON.stringify(baseline, null, 2) + "\n");
  renameSync(path + ".tmp", path);
  lines.push("", `Baseline written to ${path}.`);
}
console.log(lines.join("\n"));
process.exit(bad.length > 0 || runs.length === 0 ? 1 : 0);
