// 离线自检：不启动 DSH，用桩 ctx 调 apply()，再真实执行一次搜索。
// 用法: node selftest.mjs ["搜索关键词"]
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import os from 'node:os';
import path from 'node:path';

const DSH_HOME = process.env.DSH_HOME || path.join(os.homedir(), '.dsh');
const PROFILE = process.env.DSH_PROFILE || 'web';
const require = createRequire(path.join(DSH_HOME, 'profiles', PROFILE, 'package.json'));
const entry = require.resolve('dsh-video-search');
// Windows 绝对路径必须转成 file:// URL 才能 import
const { apply, formatResults } = await import(pathToFileURL(entry).href);

let tool = null;
let section = null;
apply({
  systemPrompt: { section: (s) => { section = s; }, getSectionOrder: () => 2000 },
  tools: { register: (t) => { tool = t; }, get: (n) => (n === 'video_search' ? tool : undefined) },
});

console.log('resolved:', entry);
console.log('tool:', tool?.name, '| params:', Object.keys(tool?.parameters?.properties ?? {}).join(','),
  '| timeout:', tool?.timeoutMs, '| section order:', section?.order);
console.log('prompt gated on tool:', (section?.text({ scope: undefined }) ?? '').includes('video_search('));

const out = await tool.execute({ query: process.argv[2] || '展锐 刷机 解锁', limit: 3 }, {});
console.log('results:', out.results.length);
for (const r of out.results) console.log('  -', r.bvid, '|', (r.title ?? '').slice(0, 40), '| play', r.play);
console.log('--- rendered head ---');
console.log(formatResults(out).slice(0, 300));
