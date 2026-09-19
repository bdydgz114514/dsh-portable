/**
 * 用知识库插件自己的 kb_add 写入条目。
 * 前置：把 <插件目录>/index.js 就地复制成 __kbseed.mjs（让它的 import 能解析内核依赖）。
 * 用法：node seed.mjs <KB目录> <entries.json>
 */
import { readFileSync } from "node:fs";
import { pathToFileURL, fileURLToPath } from "node:url";
import { join, dirname } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const [kbDir, entriesFile] = process.argv.slice(2);
if (!kbDir || !entriesFile) {
  console.error("用法: node seed.mjs <KB目录> <entries.json>");
  process.exit(1);
}
process.env.DSH_KNOWLEDGE_DIR = kbDir;

/* 插件模块：优先找同目录的 __kbseed.mjs，其次按参数给的插件目录 */
const pluginUrl = process.env.KB_PLUGIN_JS
  ? pathToFileURL(process.env.KB_PLUGIN_JS).href
  : pathToFileURL(join(here, "__kbseed.mjs")).href;

const tools = new Map();
const ctx = {
  tools: { register: (t) => { tools.set(t.name, t); } },
  inject: () => {},
  on: () => {},
  effect: () => {},
  logger: { info() {}, warn() {}, error() {} }
};
const mod = await import(pluginUrl);
mod.apply(ctx, {});
await new Promise((r) => setTimeout(r, 300));

const add = tools.get("kb_add");
if (!add) { console.error("kb_add 未注册；已注册: " + [...tools.keys()].join(",")); process.exit(1); }
console.log("已注册工具: " + [...tools.keys()].join(", "));

const entries = JSON.parse(readFileSync(entriesFile, "utf8"));
let ok = 0;
for (const e of entries) {
  const res = await add.execute({ title: e.title, problem: e.problem, solution: e.solution, tags: e.tags, source: e.source });
  if (res && res.ok) { ok++; console.log("  + " + res.id + "  " + e.title); }
  else console.log("  ! 失败: " + JSON.stringify(res));
}
console.log("写入 " + ok + "/" + entries.length);
const stats = tools.get("kb_stats");
if (stats) console.log("[kb_stats] " + JSON.stringify(await stats.execute({})));
