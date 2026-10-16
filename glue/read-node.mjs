// The reader of the Node-capable build (glue/build.sh --node appends it to
// bend-glue.mjs): Node's fetch does not read file: URLs.
import { readFile } from "node:fs/promises";

async function wasmBytes(url) {
  return readFile(url);
}
