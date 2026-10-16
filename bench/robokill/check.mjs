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
//   on the POST of results writes them and exits 0.
//
// `node check.mjs PORT`. Exit status: 0 when every check holds.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { registerHooks } from "node:module";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

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
await serveCheck();
