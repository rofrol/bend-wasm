// Vendored from Robokill's spike/serve.mjs at commit 63031ab, unchanged but
// for these two lines and the edits marked "bend-wasm:"
// (bench/robokill/README.md).
// Serves spike/ on 127.0.0.1 and waits for the page to POST its results.
// Usage: node spike/serve.mjs <port> <results.json> [<chrome profile dir> <query>]
// With a profile dir it starts a separate Chrome on the page once the server
// listens (V8 GC tracing to <results.json>.chrome.log) and closes it after.
// Exits 0 once the results are written (the page's POST is the event the
// caller waits for), 1 if the page reported an error.
import { createServer } from "node:http";
import { spawn } from "node:child_process";
import { openSync } from "node:fs";
import { readFile, writeFile, rename } from "node:fs/promises";
import { extname, join, normalize } from "node:path";
import { rendererMemory } from "./procs.mjs"; // bend-wasm

const root = new URL(".", import.meta.url).pathname;
const [port = "8642", outPath = join(root, "dist", "results.json"), profile, query = ""] = process.argv.slice(2);
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
let chrome = null;
const types = { ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".json": "application/json" };

createServer(async (req, res) => {
  // bend-wasm: a memory mark the page posts (after init, after the replay)
  // and waits for: the reply is the page's renderer and its memory, read
  // while the page waits (procs.mjs); null fields without a Chrome.
  if (req.method === "POST" && req.url === "/mark") {
    for await (const _ of req);
    const os = chrome === null ? { error: "no Chrome started" }
      : await rendererMemory(chrome.pid, outPath);
    res.writeHead(200, { "content-type": "application/json" })
      .end(JSON.stringify(os));
    return;
  }
  if (req.method === "POST" && req.url === "/results") {
    let body = "";
    for await (const chunk of req) body += chunk;
    await writeFile(outPath + ".tmp", body);
    await rename(outPath + ".tmp", outPath);
    res.end("ok");
    console.log("results written to " + outPath);
    chrome?.kill();
    process.exit(JSON.parse(body).error ? 1 : 0);
  }
  const path = normalize(join(root, decodeURIComponent(new URL(req.url, "http://x").pathname)));
  if (!path.startsWith(root)) { res.writeHead(403).end(); return; }
  try {
    const file = path.endsWith("/") ? join(path, "index.html") : path;
    const data = await readFile(file);
    // Cross-origin isolation lifts performance.now() to 5 us resolution.
    res.writeHead(200, {
      "content-type": types[extname(file)] ?? "application/octet-stream",
      "cross-origin-opener-policy": "same-origin",
      "cross-origin-embedder-policy": "require-corp",
    }).end(data);
  } catch {
    res.writeHead(404).end();
  }
}).listen(Number(port), "127.0.0.1", () => {
  const url = `http://127.0.0.1:${port}/index.html?${query}`;
  console.log(url);
  if (!profile) return;
  const log = openSync(outPath + ".chrome.log", "w");
  chrome = spawn(CHROME, [
    `--user-data-dir=${profile}`, "--no-first-run", "--no-default-browser-check",
    "--enable-precise-memory-info", "--js-flags=--trace-gc", "--enable-logging=stderr",
    // bend-wasm: measureUserAgentSpecificMemory() resolves at once instead of
    // after Chrome's next scheduled garbage collection.
    "--enable-blink-features=ForceEagerMeasureMemory",
    "--window-size=1320,900", url,
  ], { stdio: ["ignore", log, log] });
  chrome.on("exit", (code) => { console.log("chrome exited " + code); process.exit(2); });
});
