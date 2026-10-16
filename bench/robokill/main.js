// Vendored from Robokill's spike/main.js at commit 63031ab, with the edits
// listed in bench/robokill/README.md (marked "bend-wasm:"): ?lane=js|wasm
// picks the lane module, the results carry the lane, its load times and
// the tab's memory.
//
// JS host for the milestone 2 spike: on each requestAnimationFrame callback
// it calls the Bend `step`, has `render` write the sprite data into a
// Float32Array, uploads it with one writeBuffer and draws every sprite with
// one instanced draw from a procedurally generated atlas. It measures step
// plus upload per frame and posts the results to the serving script.
//
// Query: ?n=500,2000&frames=10000

// bend-wasm: the lane module, imported in main() so a failure is posted.
let G, laneModule, importMs;

const STRIDE = 4; // x, y, angle, atlas index
const PROJ = 256; // projectile slots after the n bodies
const TILE = 32;
const TILES = 8;
const BUDGET_MS = 8;

const params = new URLSearchParams(location.search);
const sizes = (params.get("n") ?? "500,2000").split(",").map(Number);
const frames = Number(params.get("frames") ?? 10000);
const lane = params.get("lane") ?? "js"; // bend-wasm
const statusEl = document.getElementById("status");
const resultsEl = document.getElementById("results");

// Atlas: tile 0..3 body kinds, tile 4 projectile.
function makeAtlas() {
  const w = TILE * TILES, px = new Uint8Array(w * TILE * 4);
  const colors = [[230, 80, 70], [80, 200, 90], [80, 140, 240], [230, 200, 60], [255, 255, 255]];
  for (let t = 0; t < 5; t++) {
    for (let y = 0; y < TILE; y++) {
      for (let x = 0; x < TILE; x++) {
        const u = (x + 0.5) / TILE * 2 - 1, v = (y + 0.5) / TILE * 2 - 1;
        const inside = [
          u * u + v * v < 0.9,                    // disc
          Math.max(Math.abs(u), Math.abs(v)) < 0.8, // square
          v > -0.8 && Math.abs(u) < (v + 0.8) / 2, // triangle
          Math.abs(u) + Math.abs(v) < 0.95,        // diamond
          u * u + v * v < 0.5,                    // projectile
        ][t];
        const shade = 0.6 + 0.4 * (1 - v) / 2;   // a light from the top
        const o = (y * w + t * TILE + x) * 4;
        if (inside) {
          px[o] = colors[t][0] * shade; px[o + 1] = colors[t][1] * shade;
          px[o + 2] = colors[t][2] * shade; px[o + 3] = 255;
        }
      }
    }
  }
  return { w, h: TILE, px };
}

const shader = /* wgsl */ `
struct VOut {
  @builtin(position) pos: vec4f,
  @location(0) uv: vec2f,
};

@group(0) @binding(0) var atlas: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;

const corners = array<vec2f, 6>(
  vec2f(-1, -1), vec2f(1, -1), vec2f(-1, 1),
  vec2f(-1, 1), vec2f(1, -1), vec2f(1, 1));

@vertex
fn vs(@builtin(vertex_index) vi: u32, @location(0) inst: vec4f) -> VOut {
  var out: VOut;
  let c = corners[vi];
  let kind = inst.w;
  let half = select(5.0, 3.0, kind > 3.5);
  let s = sin(inst.z);
  let k = cos(inst.z);
  let p = inst.xy + vec2f(c.x * k - c.y * s, c.x * s + c.y * k) * half;
  out.pos = select(vec4f(p.x / 640.0 - 1.0, 1.0 - p.y / 360.0, 0.0, 1.0),
                   vec4f(2.0, 2.0, 2.0, 1.0), kind < 0.0);
  out.uv = vec2f((c.x * 0.5 + 0.5 + max(kind, 0.0)) / ${TILES}.0, 0.5 - c.y * 0.5);
  return out;
}

@fragment
fn fs(in: VOut) -> @location(0) vec4f {
  let t = textureSample(atlas, samp, in.uv);
  if (t.a < 0.5) { discard; }
  return t;
}
`;

async function initGpu() {
  if (!navigator.gpu) throw new Error("WebGPU is not available (no fallback by design)");
  const adapter = await navigator.gpu.requestAdapter();
  if (!adapter) throw new Error("no WebGPU adapter");
  const device = await adapter.requestDevice();
  const canvas = document.getElementById("view");
  const ctx = canvas.getContext("webgpu");
  const format = navigator.gpu.getPreferredCanvasFormat();
  ctx.configure({ device, format, alphaMode: "opaque" });

  const a = makeAtlas();
  const tex = device.createTexture({
    size: [a.w, a.h], format: "rgba8unorm",
    usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
  });
  device.queue.writeTexture({ texture: tex }, a.px, { bytesPerRow: a.w * 4 }, [a.w, a.h]);

  const module = device.createShaderModule({ code: shader });
  const pipeline = device.createRenderPipeline({
    layout: "auto",
    vertex: {
      module, entryPoint: "vs",
      buffers: [{
        arrayStride: STRIDE * 4, stepMode: "instance",
        attributes: [{ shaderLocation: 0, offset: 0, format: "float32x4" }],
      }],
    },
    fragment: { module, entryPoint: "fs", targets: [{ format }] },
    primitive: { topology: "triangle-list" },
  });
  const bind = device.createBindGroup({
    layout: pipeline.getBindGroupLayout(0),
    entries: [
      { binding: 0, resource: tex.createView() },
      { binding: 1, resource: device.createSampler({ magFilter: "linear", minFilter: "linear" }) },
    ],
  });
  return { device, ctx, pipeline, bind, adapterInfo: adapter.info };
}

function heap() {
  return performance.memory ? performance.memory.usedJSHeapSize : null;
}

function quantile(sorted, p) {
  return sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))];
}

// Runs `frames` frames for n bodies, one per animation frame callback.
function runOne(gpu, n) {
  const count = n + PROJ;
  const out = new Float32Array(16384); // render writes in place (JS lane)
  const buf = gpu.device.createBuffer({
    size: count * STRIDE * 4, usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
  });
  let state = G.init(n, 12345);
  const stepMs = new Float64Array(frames);
  const drawMs = new Float64Array(frames);
  const rafGap = [];
  const hashes = [];
  const heapSamples = [];
  let frame = 0, lastRaf = null;

  return new Promise((resolve) => {
    function checkpoint() {
      const r = G.hash(state);
      state = r.fst;
      hashes.push({ frame, hash: r.snd });
      heapSamples.push({ frame, heap: heap() });
    }

    function tick(now) {
      if (lastRaf !== null) rafGap.push(now - lastRaf);
      lastRaf = now;
      if (frame % 1000 === 0) checkpoint();

      const t0 = performance.now();
      state = G.step(state, G.input_at(frame));
      const r = G.render(state, out);
      state = r.fst;
      gpu.device.queue.writeBuffer(buf, 0, out, 0, count * STRIDE);
      const t1 = performance.now();

      const enc = gpu.device.createCommandEncoder();
      const pass = enc.beginRenderPass({
        colorAttachments: [{
          view: gpu.ctx.getCurrentTexture().createView(),
          clearValue: { r: 0.05, g: 0.05, b: 0.07, a: 1 }, loadOp: "clear", storeOp: "store",
        }],
      });
      pass.setPipeline(gpu.pipeline);
      pass.setBindGroup(0, gpu.bind);
      pass.setVertexBuffer(0, buf);
      pass.draw(6, count);
      pass.end();
      gpu.device.queue.submit([enc.finish()]);
      drawMs[frame] = performance.now() - t1;
      stepMs[frame] = t1 - t0;

      frame++;
      if (frame % 250 === 0) statusEl.textContent = `n=${n} frame ${frame}/${frames}`;
      if (frame < frames) {
        requestAnimationFrame(tick);
        return;
      }
      checkpoint();
      buf.destroy();
      const s = Array.from(stepMs).sort((a, b) => a - b);
      const d = Array.from(drawMs).sort((a, b) => a - b);
      const g = rafGap.sort((a, b) => a - b);
      const round = (x) => Math.round(x * 1000) / 1000;
      resolve({
        n, frames,
        stepUploadMs: {
          p50: round(quantile(s, 0.5)), p95: round(quantile(s, 0.95)),
          p99: round(quantile(s, 0.99)), max: round(s[s.length - 1]),
          mean: round(s.reduce((a, b) => a + b, 0) / s.length),
          overBudget: s.filter((x) => x > BUDGET_MS).length,
          over4ms: s.filter((x) => x > 4).length,
          worstFrames: Array.from(stepMs).map((v, i) => [i, round(v)])
            .sort((a, b) => b[1] - a[1]).slice(0, 10),
        },
        encodeSubmitMs: { p50: round(quantile(d, 0.5)), p95: round(quantile(d, 0.95)), max: round(d[d.length - 1]) },
        rafGapMs: { p50: round(quantile(g, 0.5)), p95: round(quantile(g, 0.95)), p99: round(quantile(g, 0.99)), max: round(g[g.length - 1]) },
        heap: heapSamples,
        hashes,
      });
    }
    requestAnimationFrame(tick);
  });
}

async function main() {
  // bend-wasm: the lane switch
  if (lane !== "js" && lane !== "wasm") throw new Error(`?lane=${lane}: js or wasm`);
  const t0 = performance.now();
  laneModule = await import(lane === "wasm" ? "./dist/step.wasm.mjs" : "./dist/step.mjs");
  importMs = performance.now() - t0;
  G = laneModule.default;
  const gpu = await initGpu();
  const results = {
    lane, // bend-wasm
    load: { importMs, ...laneModule.timings?.() }, // bend-wasm
    userAgent: navigator.userAgent,
    crossOriginIsolated: self.crossOriginIsolated,
    adapter: gpu.adapterInfo ? { vendor: gpu.adapterInfo.vendor, architecture: gpu.adapterInfo.architecture } : null,
    budgetMs: BUDGET_MS,
    runs: [],
  };
  for (const n of sizes) results.runs.push(await runOne(gpu, n));
  // bend-wasm: the tab's memory (JS and wasm, the 512 MiB corpus included;
  // not the GPU's), which needs cross-origin isolation (serve.mjs).
  if (self.crossOriginIsolated && performance.measureUserAgentSpecificMemory) {
    const m = await performance.measureUserAgentSpecificMemory();
    results.memory = {
      bytes: m.bytes,
      breakdown: m.breakdown.filter((b) => b.bytes > 0).map((b) => ({ bytes: b.bytes, types: b.types })),
    };
  }
  const text = JSON.stringify(results, null, 2);
  statusEl.textContent = "done";
  resultsEl.textContent = text;
  // The serving script (spike/serve.mjs) records the results; with any
  // other server the JSON stays on screen.
  fetch("./results", { method: "POST", body: text }).catch(() => {});
}

main().catch((e) => {
  statusEl.textContent = "error: " + e.message;
  fetch("./results", { method: "POST", body: JSON.stringify({ lane, error: String(e) }) }).catch(() => {}); // bend-wasm: lane
});
