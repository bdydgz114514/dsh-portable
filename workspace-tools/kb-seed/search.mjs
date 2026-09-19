/**
 * 用知识库插件自己的 kb_search 检索（验证库可读、检索可用）。
 * 前置：把 <插件包>/lib/index.js 复制成同目录的 __kbseed.mjs（让它的 import 能解析依赖）。
 * 用法：KB_PLUGIN_JS=<插件包>/lib/__kbseed.mjs node search.mjs <KB目录> <关键词...>
 */
import { pathToFileURL } from "node:url";
const kbDir = process.argv[2];
const queries = process.argv.slice(3);
if (!kbDir || queries.length === 0) {
  console.error("用法: KB_PLUGIN_JS=<插件包>/lib/__kbseed.mjs node search.mjs <KB目录> <关键词...>");
  process.exit(1);
}
process.env.DSH_KNOWLEDGE_DIR = kbDir;
const tools = new Map();
const ctx = { tools: { register: (t) => tools.set(t.name, t) }, inject: () => {}, on: () => {}, effect: () => {}, logger: {} };
const mod = await import(pathToFileURL(process.env.KB_PLUGIN_JS).href);
mod.apply(ctx, {});
await new Promise((r) => setTimeout(r, 300));
const search = tools.get("kb_search");
const stats = tools.get("kb_stats");
console.log("[kb_stats] " + JSON.stringify(await stats.execute({})));
for (const q of queries) {
  const out = await search.execute({ query: q, limit: 3 });
  console.log("");
  console.log("查询 [" + q + "]");
  console.log((out.text || JSON.stringify(out)).split("\n").slice(0, 6).join("\n"));
}
