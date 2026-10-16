// The reader of the shipped build (glue/build.sh appends it to
// bend-glue.mjs): the wasm's bytes by fetch, as a page loads them.
async function wasmBytes(url) {
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`bend-wasm: ${url}: ${res.status}`);
  }
  return res.arrayBuffer();
}
