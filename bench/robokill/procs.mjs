// The OS side of the memory marks of serve.mjs (bench/robokill/README.md,
// "Memory"): finds the renderer process of the page in `ps` output and reads
// its footprint with macOS's `footprint`. Kept apart from serve.mjs, which
// starts its server on import, so check.mjs can test the parsing.
import { execFile } from "node:child_process";
import { readFile, rm } from "node:fs/promises";
import { promisify } from "node:util";

const run = promisify(execFile);

// "[dd-][hh:]mm:ss.cc", ps's cumulative CPU time, in seconds.
export function cpuSeconds(text) {
  const [days, rest] = text.includes("-") ? text.split("-") : ["0", text];
  return rest.split(":").reduce((s, part) => s * 60 + Number(part), 0)
    + Number(days) * 86400;
}

// Lines of `ps -A -ww -o pid=,ppid=,rss=,time=,command=`.
export function parsePs(text) {
  return text.split("\n").flatMap((line) => {
    const m = /^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\S+)\s+(.*)$/.exec(line);
    return m === null ? [] : [{ pid: Number(m[1]), ppid: Number(m[2]),
      rssKiB: Number(m[3]), cpuS: cpuSeconds(m[4]), command: m[5] }];
  });
}

// The renderers among the descendants of the browser process `root`: Chrome
// on macOS starts its helpers from the browser process, so the page's
// renderer is in that tree whatever else runs on the machine. A fresh
// profile on one URL has the page's renderer and at most a spare one; the
// page's is the one with the most CPU time (the spare has run nothing).
// Returns { renderer, candidates }, renderer null when there is none.
export function pageRenderer(procs, root) {
  const tree = new Set([root]);
  let grew = true;
  while (grew) {
    grew = false;
    for (const p of procs) {
      if (tree.has(p.ppid) && !tree.has(p.pid)) {
        tree.add(p.pid);
        grew = true;
      }
    }
  }
  const candidates = procs.filter((p) => p.pid !== root && tree.has(p.pid)
    && /(^|\s)--type=renderer(\s|$)/.test(p.command)
    && !/(^|\s)--extension-process(\s|$)/.test(p.command))
    .map(({ pid, rssKiB, cpuS }) => ({ pid, rssKiB, cpuS }));
  const renderer = candidates.reduce((a, b) => (a === null || b.cpuS > a.cpuS
    ? b : a), null);
  return { renderer, candidates };
}

// `footprint` of pid: physFootprint is the kernel's phys_footprint, the
// number Activity Monitor shows as Memory; footprint is the tool's own sum
// of the regions, 0 when it may not read them. Written through a JSON file
// next to `scratch`, which is removed after.
export async function footprintOf(pid, scratch) {
  const file = `${scratch}.footprint-${pid}.json`;
  try {
    await run("/usr/bin/footprint", ["-p", String(pid), "-j", file,
      "-f", "bytes", "--noCategories"]);
    const p = JSON.parse(await readFile(file, "utf8")).processes
      ?.find((x) => x.pid === pid);
    if (p === undefined) return { error: "footprint: no entry for the pid" };
    return { physFootprint: p.auxiliary?.phys_footprint ?? null,
      physFootprintPeak: p.auxiliary?.phys_footprint_peak ?? null,
      footprint: p.footprint ?? null };
  } catch (e) {
    return { error: `footprint: ${e.message}` };
  } finally {
    await rm(file, { force: true });
  }
}

// The page's renderer under the browser process root and its memory:
// { renderer: {pid, rssKiB, cpuS}, candidates, footprint } or { error }.
export async function rendererMemory(root, scratch) {
  let procs;
  try {
    const { stdout } = await run("/bin/ps",
      ["-A", "-ww", "-o", "pid=,ppid=,rss=,time=,command="],
      { maxBuffer: 64 * 2 ** 20 });
    procs = parsePs(stdout);
  } catch (e) {
    return { error: `ps: ${e.message}` };
  }
  const { renderer, candidates } = pageRenderer(procs, root);
  if (renderer === null) {
    return { error: `no renderer below pid ${root}`, candidates };
  }
  return { renderer, candidates,
    footprint: await footprintOf(renderer.pid, scratch) };
}
