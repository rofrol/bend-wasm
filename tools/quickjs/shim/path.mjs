// node:path, POSIX only, the members the compiler calls.
import * as os from "os";

export const sep = "/";
export const delimiter = ":";

export function normalize(p) {
  const abs = p.startsWith("/");
  const out = [];
  for (const s of p.split("/")) {
    if (s === "" || s === ".") {
      continue;
    }
    if (s === ".." && out.length > 0 && out[out.length - 1] !== "..") {
      out.pop();
    } else if (s !== ".." || !abs) {
      out.push(s);
    }
  }
  const r = (abs ? "/" : "") + out.join("/");
  return r === "" ? "." : r;
}

export function join(...ps) {
  return normalize(ps.filter((p) => p !== "").join("/"));
}

export function resolve(...ps) {
  let r = os.getcwd()[0];
  for (const p of ps) {
    r = p.startsWith("/") ? p : r + "/" + p;
  }
  return normalize(r);
}

export function dirname(p) {
  const i = p.replace(/\/+$/, "").lastIndexOf("/");
  return i < 0 ? "." : i === 0 ? "/" : p.slice(0, i);
}

export function basename(p, ext) {
  const b = p.replace(/\/+$/, "").split("/").pop();
  return ext !== undefined && b.endsWith(ext) ? b.slice(0, -ext.length) : b;
}

export function extname(p) {
  const b = basename(p);
  const i = b.lastIndexOf(".");
  return i <= 0 ? "" : b.slice(i);
}

export function isAbsolute(p) {
  return p.startsWith("/");
}

export const posix = { sep, delimiter, normalize, join, resolve, dirname, basename, extname, isAbsolute };
