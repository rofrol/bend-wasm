// Runtime of the wasm lane's glue (glue/README.md). A module that
// glue/gen.mjs writes (NAME.wasm.mjs) imports this file as ./bend-glue.mjs,
// opens one Lane on the Emscripten build of a library-mode C (patch 0003)
// and wraps each exported def so the host sees the JS lane's shape: the
// same calls, `{$: "Tuple", fst, snd}` tuples, numbers, BigInt Nats, and
// opaque Handle objects where the JS lane has Bend values.
//
// Failure rule: a library misuse (the library prints "bend: ..." and calls
// _exit) or a wasm trap inside a call throws an Error with the library's
// message, and the lane is poisoned: every later call throws until
// reset() re-instantiates it from the compiled module. Handles of an
// earlier instance are refused. Errors the glue finds before entering
// wasm (a wrong argument type, a stale handle) throw without poisoning.
//
// glue/build.sh appends the reader of the build's environment to this
// file, wasmBytes(url): glue/read-web.mjs (fetch) in the shipped build,
// glue/read-node.mjs in the Node-capable one, so the shipped glue has no
// Node code at all.

const now = () => performance.now();

// Thrown by the proc_exit import, in place of Emscripten's own, which in
// Node also sets the exit code of the whole program.
class Exit extends Error {
  constructor(status) {
    super(`the library exited with status ${status}`);
    this.status = status;
  }
}

// An opaque reference to a value the library holds: the host can pass it
// back, never read it. The private fields keep the u64 handle (slot and
// generation) and the instance it belongs to out of the host's reach.
export class Handle {
  #h;
  #lane;
  #epoch;

  constructor(h, lane, type) {
    this.#h = h;
    this.#lane = lane;
    this.#epoch = lane.epoch;
    Object.defineProperty(this, "type", { value: type });
    Object.freeze(this);
  }

  // The u64 of x for lane, after the checks that need no call into wasm.
  static open(x, lane, def) {
    if (!(x instanceof Handle) || x.#lane !== lane) {
      throw new TypeError(`bend-wasm: ${def}: not a handle of this module`);
    }
    if (x.#epoch !== lane.epoch) {
      throw new Error(`bend-wasm: ${def}: a ${x.type} handle of an instance`
        + " before reset()");
    }
    return x.#h;
  }

  toString() {
    return `[bend handle ${this.type}]`;
  }
}

class Lane {
  constructor(load, mod, slots) {
    this.load = load;
    this.mod = mod;
    this.slots = slots;
    this.epoch = 0;
    this.ex = null;
    this.poison = null;
    this.errs = [];
    this.owner = null;
    this.timings = {};
  }

  // A fresh instance of the compiled module, bend_init() called, views
  // made once (memory growth is off, so they stay valid).
  async start() {
    this.ex = null;
    this.poison = null;
    this.owner = null;
    this.errs.length = 0;
    this.epoch += 1;
    const t0 = now();
    let fail;
    const failed = new Promise((_, reject) => {
      fail = reject;
    });
    let ex;
    await Promise.race([failed, this.load({
      printErr: (line) => this.errs.push(line),
      instantiateWasm: (imports, done) => {
        imports.env.proc_exit = (code) => {
          throw new Exit(code);
        };
        if (imports.wasi_snapshot_preview1 !== undefined) {
          imports.wasi_snapshot_preview1.proc_exit = imports.env.proc_exit;
        }
        WebAssembly.instantiate(this.mod, imports).then((inst) => {
          ex = inst.exports;
          done(inst, this.mod);
        }, fail);
        return {};
      },
    })]);
    const t1 = now();
    this.ex = ex;
    try {
      this.ex.bend_init();
    } catch (e) {
      throw this.fail("bend_init", e);
    }
    const t2 = now();
    const buf = this.ex.memory.buffer;
    this.region = new Float32Array(buf, this.ex.bend_f32() >>> 0,
      this.ex.bend_f32_len() >>> 0);
    this.scratch = this.ex.malloc(8 * Math.max(1, this.slots)) >>> 0;
    this.u32v = new Uint32Array(buf);
    this.f32v = new Float32Array(buf);
    this.u64v = new BigUint64Array(buf);
    this.timings.instantiateMs = t1 - t0;
    this.timings.initMs = t2 - t1;
  }

  enter() {
    if (this.poison !== null) {
      throw new Error("bend-wasm: the instance is poisoned by an earlier"
        + ` failure (${this.poison.message}); call reset()`,
        { cause: this.poison });
    }
    return this.ex;
  }

  // After a call that returned: stderr lines of a call that did not fail
  // go to the console.
  leave() {
    if (this.errs.length > 0) {
      console.error(this.errs.splice(0).join("\n"));
    }
  }

  // The Error of a failed call; it poisons the lane.
  fail(def, e) {
    const lines = this.errs.splice(0);
    const msg = e instanceof Exit
      ? (lines.length > 0 ? lines.join("\n")
        : `bend-wasm: ${def}: ${e.message}`)
      : [...lines, `bend-wasm: ${def}: wasm trap: ${e}`].join("\n");
    const err = new Error(msg, { cause: e });
    this.poison = err;
    return err;
  }

  take(x, def) {
    return Handle.open(x, this, def);
  }

  handle(h, type) {
    return new Handle(h, this, type);
  }

  // An Array<F32> argument: the region already holds the array the last
  // call returned into `a`; any other array is copied in.
  arrIn(a, def) {
    if (!(a instanceof Float32Array) || a.length !== this.region.length) {
      throw new TypeError(`bend-wasm: ${def}: an Array<F32> crosses as a`
        + ` Float32Array of ${this.region.length} floats`);
    }
    if (a !== this.owner) {
      this.region.set(a);
    }
    this.owner = null;
  }

  // An Array<F32> result: one copy of the region into `a`, or into a new
  // array when the def took none.
  arrOut(a) {
    const out = a ?? new Float32Array(this.region.length);
    out.set(this.region);
    this.owner = a ?? null;
    return out;
  }

  // Scratch word i, where the def wrote its result part i + 1.
  ptr(i) {
    return this.scratch + 8 * i;
  }

  u32(i) {
    return this.u32v[(this.scratch >>> 2) + 2 * i];
  }

  f32(i) {
    return this.f32v[(this.scratch >>> 2) + 2 * i];
  }

  u64(i) {
    return this.u64v[(this.scratch >>> 3) + i];
  }

  dispose(x) {
    const h = this.take(x, "dispose");
    const ex = this.enter();
    try {
      ex.bend_dispose(h);
    } catch (e) {
      throw this.fail("dispose", e);
    }
    this.leave();
  }

  stats() {
    const ex = this.enter();
    return { heapWords: ex.bend_heap_words(), handles: ex.bend_handles() };
  }
}

// open(load, url, slots): compiles the wasm at url once and starts a lane
// on it through the Emscripten factory load; slots is the number of
// result parts any def writes through a pointer.
export async function open(load, url, slots) {
  const t0 = now();
  const bytes = await wasmBytes(url);
  const t1 = now();
  const mod = await WebAssembly.compile(bytes);
  const t2 = now();
  const lane = new Lane(load, mod, slots);
  lane.timings.readMs = t1 - t0;
  lane.timings.compileMs = t2 - t1;
  await lane.start();
  return lane;
}
