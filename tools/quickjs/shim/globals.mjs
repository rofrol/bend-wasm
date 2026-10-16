// Globals the bundled compiler reads before it emits C: process, URL and
// the `typeof Bun` guard in main.ts. Imported first, so it runs before the
// bundle's own top-level code. Probe shims only (docs/quickjs.md): each one
// covers what the C emit path calls, nothing more.
import * as std from "std";
import * as os from "os";

globalThis.process = {
  argv: ["qjs", ...scriptArgs],
  env: std.getenviron(),
  platform: os.platform,
  arch: "unknown",
  execPath: "qjs",
  exitCode: undefined,
  cwd: () => os.getcwd()[0],
  exit(code) {
    std.out.flush();
    std.err.flush();
    std.exit(code ?? process.exitCode ?? 0);
  },
};

// main.ts stops with "bend runs on Bun" when Bun is undefined; the emit path
// uses no Bun.* member, so an empty object passes the guard.
globalThis.Bun = {};

// Only `new URL(".", "file:///dir/file")`, which bend.ts uses for BEND_DIR.
globalThis.URL = class URL {
  constructor(rel, base) {
    if (rel !== "." || !String(base).startsWith("file://")) {
      throw new Error("qjs shim: URL(" + rel + ", " + base + ") not implemented");
    }
    this.href = String(base).replace(/[^/]*$/, "");
  }
  toString() {
    return this.href;
  }
};
