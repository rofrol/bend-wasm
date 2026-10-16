// Negative check (tests/negative/README.md): what consumed.c does, on the
// wasm build of probe/lib's counter.bend. `node consumed.mjs <counter.mjs>`.
const [path] = process.argv.slice(2);
const { default: load } = await import(new URL(path, `file://${process.cwd()}/`));
const m = await load();
m._bend_init();
const s = m._bend_def_init(5);
m._bend_def_step(s, 0);
m._bend_def_peek(s);
console.log("misuse not caught");
