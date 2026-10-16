// node:url, only fileURLToPath of a file:// URL.
export function fileURLToPath(u) {
  const s = String(u);
  if (!s.startsWith("file://")) {
    throw new Error("qjs shim: fileURLToPath(" + s + ") not implemented");
  }
  return decodeURIComponent(s.slice("file://".length));
}
