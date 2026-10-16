// Reads and validates a module of tools/clang-wasm/build.sh (TODO
// t-fwjpak4c, steps B and C; docs/clang-wasm.md):
//
//   node check.mjs imports FILE.wasm            module.name of each import
//   node check.mjs validate FILE.wasm EXPORTS   instantiate with stubs
//
// validate compiles the module, instantiates it with a stub for every
// import (each throws if called; nothing runs here, running is step D's
// loader) and fails on an import outside patch 0004's list, on a missing
// export of EXPORTS (one name per line) or on a missing memory. It prints
// one line: the imports, all served by the host (write, exit, now).
import { readFileSync } from "node:fs";

const [mode, file, exportsFile] = process.argv.slice(2);

// Patch 0004's imports, all of module "bend". Math, strtof, strtod and
// %e/%f come from the module's own musl code (step C), never the host.
const HOST = new Set(["write", "exit", "now"]);

function die(msg) {
  console.error(`tools/clang-wasm/check.mjs: ${file}: ${msg}`);
  process.exit(1);
}

const mod = await WebAssembly.compile(readFileSync(file)).catch((e) =>
  die(`does not compile: ${e.message}`));
const imports = WebAssembly.Module.imports(mod);

if (mode === "imports") {
  for (const i of imports) {
    console.log(`${i.module}.${i.name} ${i.kind}`);
  }
} else if (mode === "validate" && exportsFile !== undefined) {
  const stubs = {};
  const served = [];
  for (const i of imports) {
    if (i.module !== "bend" || i.kind !== "function" || !HOST.has(i.name)) {
      die(`an import outside patch 0004's list: ${i.module}.${i.name}`
        + ` (${i.kind})`);
    }
    served.push(i.name);
    stubs[i.module] ??= {};
    stubs[i.module][i.name] = () => {
      throw new Error(`stub import ${i.module}.${i.name} called`);
    };
  }
  const inst = await WebAssembly.instantiate(mod, stubs).catch((e) =>
    die(`does not instantiate: ${e.message}`));
  const want = readFileSync(exportsFile, "utf8").split("\n")
    .filter((x) => x !== "");
  const missing = [...want, "memory"].filter((x) =>
    inst.exports[x] === undefined);
  if (missing.length > 0) {
    die(`missing exports: ${missing.join(" ")}`);
  }
  if (!(inst.exports.memory instanceof WebAssembly.Memory)) {
    die("the memory export is not a memory");
  }
  console.log(`imports: ${served.join(" ") || "none"}; memory`
    + ` ${inst.exports.memory.buffer.byteLength} bytes`);
} else {
  console.error("usage: check.mjs imports FILE.wasm"
    + " | check.mjs validate FILE.wasm EXPORTS");
  process.exit(2);
}
