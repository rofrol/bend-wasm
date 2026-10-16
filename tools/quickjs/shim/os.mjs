// node:os, the members read at load time (homedir for BEND_LIB) and tmpdir.
import * as std from "std";

export function homedir() {
  return std.getenv("HOME") ?? "/";
}

export function tmpdir() {
  return (std.getenv("TMPDIR") ?? "/tmp").replace(/\/+$/, "");
}
