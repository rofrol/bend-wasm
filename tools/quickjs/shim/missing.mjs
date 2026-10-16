// node:child_process, node:crypto, node:module and node:worker_threads:
// imported by the compiler but not called on the C emit path. Every member
// is undefined, so a path that does call one fails with a TypeError naming
// it (docs/quickjs.md lists which path needs which).
export {};
