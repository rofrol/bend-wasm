// Summarizes the page's results of bench/robokill/run.sh: one JSON per
// block and lane, named <block>-<lane>.json, as main.js posts them to
// serve.mjs. Prints a Markdown report: per run step+upload p50, p95, p99,
// max and frames over 4 ms; per n and lane the median of the blocks; the
// paired ratio wasm / JS of each block's p50 and p95; load times and the
// tab's memory. Checks that every run finished, that both lanes recorded
// the same checkpoint hashes and that the final ones are RESULTS.md's.
// `node summary.mjs <dir>`; exit status 1 when a check fails.
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const [dir] = process.argv.slice(2);
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
lines.push("", "Load (ms) and the tab's memory after the runs:", "");
for (const { block, lane, r } of ok) {
  const l = Object.entries(r.load ?? {}).map(([k, v]) => `${k} ${f3(v)}`)
    .join(", ");
  const mem = r.memory === undefined ? "not measured"
    : `${(r.memory.bytes / 2 ** 20).toFixed(1)} MiB`;
  lines.push(`- block ${block} ${lane}: ${l}; memory ${mem}`);
}
if (bad.length > 0) {
  lines.push("", ...bad.map((b) => `FAILED: ${b}`));
}
console.log(lines.join("\n"));
process.exit(bad.length > 0 || runs.length === 0 ? 1 : 0);
