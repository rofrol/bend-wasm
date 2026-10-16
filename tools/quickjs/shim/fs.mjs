// node:fs, the synchronous members the C emit path calls, over QuickJS's
// std and os modules. Strings only: no Buffer, no encodings but UTF-8.
import * as std from "std";
import * as os from "os";

function fail(op, p, errno) {
  const e = new Error(op + " " + p + ": " + std.strerror(errno));
  e.code = errno === std.Error.ENOENT ? "ENOENT" : "E" + errno;
  throw e;
}

export function existsSync(p) {
  return os.stat(p)[1] === 0;
}

export function statSync(p) {
  const [st, err] = os.stat(p);
  if (err !== 0) {
    fail("stat", p, err);
  }
  const type = st.mode & os.S_IFMT;
  return { ...st, isDirectory: () => type === os.S_IFDIR, isFile: () => type === os.S_IFREG };
}

export function realpathSync(p) {
  const [r, err] = os.realpath(p);
  if (err !== 0) {
    fail("realpath", p, err);
  }
  return r;
}

export function readFileSync(p, enc) {
  if (enc !== "utf8" && enc !== "utf-8") {
    throw new Error("qjs shim: readFileSync without utf8 not implemented");
  }
  const s = std.loadFile(p);
  if (s === null) {
    fail("open", p, std.Error.ENOENT);
  }
  return s;
}

export function writeFileSync(p, data) {
  const errObj = {};
  const f = std.open(p, "w", errObj);
  if (f === null) {
    fail("open", p, errObj.errno);
  }
  f.puts(String(data));
  f.close();
}

export function writeSync(fd, text) {
  const f = fd === 1 ? std.out : fd === 2 ? std.err : null;
  if (f === null) {
    throw new Error("qjs shim: writeSync to fd " + fd + " not implemented");
  }
  f.puts(text);
  return text.length;
}

export function readdirSync(p) {
  const [es, err] = os.readdir(p);
  if (err !== 0) {
    fail("readdir", p, err);
  }
  return es.filter((e) => e !== "." && e !== "..").sort();
}

export function mkdirSync(p, opts) {
  if (opts?.recursive && existsSync(p)) {
    return;
  }
  if (opts?.recursive) {
    const up = p.replace(/\/+$/, "").replace(/\/[^/]*$/, "");
    if (up !== "" && up !== p) {
      mkdirSync(up, opts);
    }
  }
  const err = os.mkdir(p);
  if (err !== 0) {
    fail("mkdir", p, -err);
  }
}
