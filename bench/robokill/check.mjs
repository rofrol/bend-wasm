// What of bench/robokill/ can be checked without a browser (README.md),
// after build.sh:
//
// - main.js, for each lane: imported with stand-ins for the DOM it reads,
//   ?lane=L loads that lane's module (the wasm one compiles and
//   instantiates) and, as Node has no WebGPU, posts {lane: L, error} to
//   ./results; an unknown lane posts its error too;
// - serve.mjs (it needs a local port, which the herdr worker sandbox
//   refuses with EPERM): started as run.sh starts it but without a Chrome profile,
//   it serves index.html, main.js and every file of dist/ byte for byte
//   with the COOP/COEP headers, refuses a path outside its directory, and
//   on the POST of results writes them and exits 0; a memory mark without
//   a Chrome gets {error};
// - procs.mjs: the renderer lookup on fabricated ps output, and live on a
//   child this check starts (skipped where ps is refused, as in the herdr
//   worker sandbox);
// - summary.mjs on fabricated results: the memory medians, baseline.json,
//   and a failure without a renderer.
//
// `node check.mjs PORT`. Exit status: 0 when every check holds.
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync,
  writeFileSync } from "node:fs";
import { registerHooks } from "node:module";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { cpuSeconds, pageRenderer, parsePs, rendererMemory } from "./procs.mjs";

const here = new URL(".", import.meta.url).pathname;
const mainUrl = new URL("main.js", import.meta.url).href;
// The page loads main.js as a module (<script type="module">); Node would
// take it for CommonJS, as it has no static import, and cache it once.
registerHooks({
  load(url, context, next) {
    if (url.split("?")[0] !== mainUrl) {
      return next(url, context);
    }
    return { format: "module", shortCircuit: true,
      source: readFileSync(fileURLToPath(url.split("?")[0]), "utf8") };
  },
});
const [port = "8642"] = process.argv.slice(2);
const ok = (what) => console.log(`ok: ${what}`);
const realFetch = globalThis.fetch;

async function serveCheck() {
  const dir = mkdtempSync(join(process.env.TMPDIR ?? tmpdir(), "serve-"));
  const results = join(dir, "results.json");
  const child = spawn(process.execPath, [join(here, "serve.mjs"), port, results],
    { stdio: ["ignore", "pipe", "inherit"] });
  const exited = new Promise((resolve) => child.on("exit", resolve));
  let text = "";
  // the URL line is serve.mjs's event that it listens
  const base = await new Promise((resolve, reject) => {
    child.stdout.on("data", (d) => {
      text += d;
      const m = /^(http:\/\/127\.0\.0\.1:\d+\/)index\.html\?/m.exec(text);
      if (m !== null) {
        resolve(m[1]);
      }
    });
    exited.then((code) => reject(new Error(`serve.mjs exited ${code}: ${text}`)));
  });
  try {
    const files = ["index.html", "main.js",
      ...readdirSync(join(here, "dist")).map((f) => `dist/${f}`)];
    for (const f of files) {
      const res = await realFetch(base + f);
      assert.equal(res.status, 200, f);
      assert.equal(res.headers.get("cross-origin-opener-policy"), "same-origin");
      assert.equal(res.headers.get("cross-origin-embedder-policy"), "require-corp");
      const got = Buffer.from(await res.arrayBuffer());
      assert.ok(got.equals(readFileSync(join(here, f))), `${f} differs`);
    }
    assert.equal((await realFetch(base)).status, 200);
    // What matters is that the file outside the served directory is not
    // served. serve.mjs (vendored, unchanged) answers 403 to a path that
    // resolves outside its root, but its WHATWG URL parsing already folds
    // `%2e%2e` segments at the root, so this request lands on a missing
    // file inside it and gets 404; either refusal is fine.
    const outside = await realFetch(base + "%2e%2e/%2e%2e/AGENTS.md");
    assert.notEqual(outside.status, 200);
    const outsideBody = Buffer.from(await outside.arrayBuffer());
    assert.ok(!outsideBody.equals(readFileSync(join(here, "../../AGENTS.md"))),
      "a path outside the served directory returned its file");
    ok(`serve.mjs serves ${files.length} files byte for byte, cross-origin`
      + " isolated, and refuses a path outside its directory");
    const mark = await realFetch(base + "mark", { method: "POST", body: "init" });
    assert.deepEqual(await mark.json(), { error: "no Chrome started" });
    ok("serve.mjs answers a memory mark without a Chrome");
    const body = JSON.stringify({ lane: "check", runs: [] });
    const res = await realFetch(base + "results", { method: "POST", body });
    assert.equal(await res.text(), "ok");
    assert.equal(await exited, 0);
    assert.equal(readFileSync(results, "utf8"), body);
    ok("serve.mjs writes the posted results and exits 0");
  } finally {
    child.kill();
    rmSync(dir, { recursive: true, force: true });
  }
}

// procs.mjs's parsing on fabricated ps output: the renderers below the
// browser process, the busier one taken, others' processes ignored.
function procsCheck() {
  assert.equal(cpuSeconds("0:01.50"), 1.5);
  assert.equal(cpuSeconds("1:02:03.00"), 3723);
  assert.equal(cpuSeconds("2-00:00:01.00"), 172801);
  const ps = [
    "  100     1  90000   0:05.00 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome --user-data-dir=/p",
    "  101   100  40000   0:00.10 /x/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer) --type=renderer --renderer-client-id=5",
    "  102   100 300000   0:09.75 /x/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer) --type=renderer --renderer-client-id=7",
    "  103   100  50000   0:01.00 /x/Google Chrome Helper (GPU).app/Contents/MacOS/Google Chrome Helper (GPU) --type=gpu-process",
    "  104   103  10000   0:01.00 /x/helper --type=renderer --extension-process",
    "  200     1 500000  10:00.00 /other/Google Chrome Helper (Renderer) --type=renderer",
    "garbage line",
  ].join("\n");
  const procs = parsePs(ps);
  assert.equal(procs.length, 6);
  const { renderer, candidates } = pageRenderer(procs, 100);
  assert.deepEqual(candidates.map((c) => c.pid), [101, 102]);
  assert.deepEqual(renderer, { pid: 102, rssKiB: 300000, cpuS: 9.75 });
  assert.equal(pageRenderer(procs, 999).renderer, null);
  ok("procs.mjs finds the busiest renderer below the browser process in ps output");
}

// procs.mjs live, on a process this check starts and ends: a child of this
// process whose command line carries --type=renderer. `ps` is refused in
// the herdr worker sandbox; that one refusal is reported as skipped.
async function rendererCheck() {
  const child = spawn(process.execPath,
    ["-e", "process.stdin.resume()", "--", "--type=renderer"],
    { stdio: ["pipe", "ignore", "inherit"] });
  const exited = new Promise((resolve) => child.on("exit", resolve));
  try {
    await new Promise((resolve, reject) => {
      child.on("spawn", resolve);
      child.on("error", reject);
    });
    const dir = mkdtempSync(join(process.env.TMPDIR ?? tmpdir(), "procs-"));
    try {
      const m = await rendererMemory(process.pid, join(dir, "x"));
      if (/^ps: .*(Operation not permitted|EPERM)/.test(m.error ?? "")) {
        console.log(`skipped: the live renderer lookup (${m.error})`);
        return;
      }
      assert.equal(m.error, undefined, m.error);
      assert.equal(m.renderer.pid, child.pid);
      assert.ok(m.renderer.rssKiB > 0);
      assert.ok(m.footprint.physFootprint > 0, JSON.stringify(m.footprint));
      assert.deepEqual(readdirSync(dir), []);
      ok(`procs.mjs finds a started child (pid ${child.pid}) with ps and`
        + ` reads its footprint (${m.footprint.physFootprint} bytes)`);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  } finally {
    child.stdin.end(); // the child exits when its stdin closes
    await exited;
  }
}

// summary.mjs on fabricated results of two blocks: the memory table and
// baseline.json when every check holds; exit 1 and no baseline when a
// mark has no renderer.
function summaryCheck() {
  const dir = mkdtempSync(join(process.env.TMPDIR ?? tmpdir(), "summary-"));
  try {
    const dist = join(dir, "dist");
    const out = join(dir, "out");
    mkdirSync(dist);
    mkdirSync(out);
    for (const f of ["step.mjs", "step.wasm.mjs", "bend-glue.mjs",
      "step.lib.mjs", "step.lib.wasm"]) {
      writeFileSync(join(dist, f), `${f} `.repeat(100));
    }
    writeFileSync(join(out, "toolchain.txt"), "bend test\n");
    const FINAL = { 500: 603820250, 2000: 819172968 };
    const fake = (block, lane) => ({
      lane, load: { importMs: 1 }, userAgent: "UA", crossOriginIsolated: true,
      adapter: null, budgetMs: 8,
      runs: [500, 2000].map((n) => {
        const base = n / 1000 * (lane === "js" ? 1 : 0.4) + block / 100;
        return {
          n, frames: 10000,
          stepUploadMs: { p50: base, p95: base * 1.1, p99: base * 1.2,
            max: base * 2, mean: base, overBudget: 0, over4ms: 0 },
          hashes: [{ frame: 10000, hash: FINAL[n] }],
          memory: ["init", "replay"].map((event, i) => ({
            event,
            wasmMemoryBytes: lane === "wasm" ? 11534336 : null,
            uaMemory: { bytes: (block + i) * 2 ** 20, breakdown: [] },
            os: { renderer: { pid: 7, rssKiB: 1024 * (100 + block), cpuS: 1 },
              candidates: [{ pid: 7, rssKiB: 1, cpuS: 1 }],
              footprint: { physFootprint: (50 + block) * 2 ** 20 } },
          })),
        };
      }),
    });
    for (const block of [1, 2, 3]) {
      for (const lane of ["js", "wasm"]) {
        writeFileSync(join(out, `${block}-${lane}.json`),
          JSON.stringify(fake(block, lane)));
      }
    }
    const summary = join(here, "summary.mjs");
    const r = spawnSync(process.execPath, [summary, out, dist], { encoding: "utf8" });
    assert.equal(r.status, 0, r.stdout + r.stderr);
    assert.match(r.stdout, /\| 2000 \| wasm \| replay \| 11\.0 \| 3\.0 \| 102\.0 \| 52\.0 \|/);
    const b = JSON.parse(readFileSync(join(out, "baseline.json"), "utf8"));
    assert.equal(b.toolchain, "bend test");
    assert.equal(b.blocks, 3);
    assert.equal(b.linearMemoryBytes, 11534336);
    assert.equal(b.shipped.wasm.files["step.lib.wasm"].raw, 1400);
    assert.ok(b.shipped.wasm.files["step.lib.wasm"].gzip9 < 1400);
    assert.equal(b.shipped.wasm.total.raw,
      ["step.wasm.mjs", "bend-glue.mjs", "step.lib.mjs", "step.lib.wasm"]
        .reduce((s, f) => s + 100 * (f.length + 1), 0));
    assert.deepEqual(Object.keys(b.shipped.js.files), ["step.mjs"]);
    const mid = 2000 / 1000 * 0.4 + 2 / 100; // block 2's, the median
    assert.deepEqual(b.chromeStepUploadMs.wasm[2000], { p50: mid, p95: mid * 1.1 });
    assert.deepEqual(b.memory.js[500].init, { wasmMemoryBytes: null,
      uaMemoryBytes: 2 * 2 ** 20, rendererRssBytes: 102 * 2 ** 20,
      rendererFootprintBytes: 52 * 2 ** 20 });
    ok("summary.mjs reports memory medians and writes baseline.json");

    rmSync(join(out, "baseline.json"));
    const broken = fake(2, "wasm");
    broken.runs[1].memory[1].os = { error: "ps: refused" };
    writeFileSync(join(out, "2-wasm.json"), JSON.stringify(broken));
    const f = spawnSync(process.execPath, [summary, out, dist], { encoding: "utf8" });
    assert.equal(f.status, 1);
    assert.match(f.stdout, /FAILED: block 2 wasm n=2000 replay: no renderer: ps: refused/);
    assert.ok(!existsSync(join(out, "baseline.json")));
    ok("summary.mjs fails without a renderer and writes no baseline");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// main.js under ?lane=L with the DOM it reads stood in: its first post,
// which the stand-in fetch delivers, and the status line then.
async function pageCheck(lane) {
  const el = { textContent: "" };
  globalThis.location = { search: `?lane=${lane}&n=500&frames=10` };
  globalThis.document = { getElementById: () => el };
  const posted = new Promise((resolve) => {
    globalThis.fetch = async (url, init) => {
      resolve({ url, body: JSON.parse(init.body) });
      return new Response("ok");
    };
  });
  await import(new URL(`main.js?${lane}`, import.meta.url));
  const post = await posted;
  return { post, status: el.textContent };
}

for (const lane of ["js", "wasm"]) {
  const { post, status } = await pageCheck(lane);
  assert.equal(post.url, "./results");
  assert.deepEqual(post.body, { lane,
    error: "Error: WebGPU is not available (no fallback by design)" });
  assert.match(status, /^error: WebGPU is not available/);
  ok(`main.js ?lane=${lane} loads the lane and posts its error with the lane`);
}
{
  const { post } = await pageCheck("c");
  assert.deepEqual(post.body, { lane: "c", error: "Error: ?lane=c: js or wasm" });
  ok("main.js posts an unknown lane as an error");
}
globalThis.fetch = realFetch;
procsCheck();
await rendererCheck();
summaryCheck();
await serveCheck();
