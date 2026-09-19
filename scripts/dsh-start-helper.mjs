#!/usr/bin/env node
// dsh launcher helper: (1) check/update @deepseek-ai/dsh, (2) verify plugin<->dsh
// version correspondence before the bat starts dsh web.
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
const nodeRequire = createRequire(import.meta.url);

const PROFILE = process.env.DSH_PROFILE || 'web';
const DSH_HOME = process.env.DSH_HOME || path.join(os.homedir(), '.dsh');
const PLUGINS = (process.env.DSH_PLUGINS || 'dshmarket dsh-better-sidebar dsh-context @linxin666/dsh-web-all').split(/\s+/).filter(Boolean);
const MODE = (process.env.DSH_UPDATE_MODE || 'auto').toLowerCase();
const DRYRUN = process.env.DSH_DRYRUN === '1';
const AUTO_FIX = process.env.DSH_PLUGIN_AUTOFIX !== '0';
const PKG = '@deepseek-ai/dsh';
const LF = String.fromCharCode(10);
const CR = String.fromCharCode(13);

function sh(cmd, live) {
  return execSync(cmd, { encoding: 'utf8', windowsHide: true, stdio: live ? 'inherit' : ['ignore', 'pipe', 'ignore'] }).trim();
}
function firstLine(t) {
  if (!t) return '';
  return t.split(CR).join('').split(LF)[0] || '';
}

let semver = null;
try {
  const npmCmd = firstLine(sh('where npm.cmd'));
  if (npmCmd) {
    const semverPath = path.join(path.dirname(npmCmd), 'node_modules', 'npm', 'node_modules', 'semver');
    semver = nodeRequire(semverPath);
  }
} catch (e) { semver = null; }

function sat(v, range) {
  if (!range) return true;
  if (semver && semver.satisfies) { try { return semver.satisfies(v, range, { includePrerelease: true }); } catch (e) { return null; } }
  return null;
}
function gt(a, b) {
  if (semver && semver.gt) { try { return semver.gt(a, b); } catch (e) { return a > b; } }
  return a > b;
}

const PROFILES = path.join(DSH_HOME, 'profiles');
const HOST_ROOTS = [path.join(PROFILES, PROFILE, 'node_modules'), path.join(PROFILES, 'node_modules')];
function readJson(p) { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (e) { return null; } }

function hostDshVersion() {
  for (const root of HOST_ROOTS) {
    const j = readJson(path.join(root, '@deepseek-ai', 'dsh-web-app', 'package.json'));
    if (j && j.version) return j.version;
  }
  return '';
}
function resolveHostVersion(peer) {
  const rel = peer.split('/').join(path.sep);
  for (const root of HOST_ROOTS) {
    const j = readJson(path.join(root, rel, 'package.json'));
    if (j && j.version) return j.version;
  }
  for (const root of HOST_ROOTS) {
    let tops = [];
    try { tops = fs.readdirSync(root, { withFileTypes: true }); } catch (e) { continue; }
    for (const en of tops) {
      if (!en.isDirectory()) continue;
      const j = readJson(path.join(root, en.name, 'node_modules', rel, 'package.json'));
      if (j && j.version) return j.version;
    }
    const g = path.join(root, '@deepseek-ai');
    let sc = [];
    try { sc = fs.readdirSync(g, { withFileTypes: true }); } catch (e) { continue; }
    for (const en of sc) {
      if (!en.isDirectory()) continue;
      const j = readJson(path.join(g, en.name, 'node_modules', rel, 'package.json'));
      if (j && j.version) return j.version;
    }
  }
  return '';
}
function locatePlugin(name) {
  const rel = name.split('/').join(path.sep);
  for (const root of HOST_ROOTS) {
    const p = path.join(root, rel, 'package.json');
    if (fs.existsSync(p)) return p;
  }
  return '';
}
function pluginCmd(name, latest) {
  const spec = latest ? name + '@latest' : name;
  return 'cmd.exe /c dsh plugin --profile ' + PROFILE + ' add ' + spec;
}

function updateDsh() {
  let npmRoot = '';
  try { npmRoot = sh('npm.cmd root -g'); } catch (e) { console.log('[dsh] npm 不可用，跳过更新。'); return 'skip'; }
  const readVer = function () {
    try { const j = JSON.parse(fs.readFileSync(path.join(npmRoot, PKG, 'package.json'), 'utf8')); return j.version || ''; } catch (e) { return ''; }
  };
  const installed = readVer();
  console.log('[dsh] 当前 dsh 全局版本: ' + (installed || '(未安装)'));
  if (MODE === 'off') return 'off';
  const tagV = function (t) { try { return sh('npm.cmd view ' + PKG + '@' + t + ' version --no-fund --no-audit') || ''; } catch (e) { return ''; } };
  let cands = [];
  if (MODE === 'latest' || MODE === 'alpha' || MODE === 'next') { const v = tagV(MODE); if (v) cands = [v]; }
  else { for (const t of ['latest', 'alpha', 'next']) { const v = tagV(t); if (v && cands.indexOf(v) < 0) cands.push(v); } }
  if (cands.length === 0) { console.log('[dsh] 获取 npm 版本失败（离线?），跳过更新。'); return 'none'; }
  let best = cands[0];
  for (const v of cands) { if (gt(v, best)) best = v; }
  console.log('[dsh] npm 最新发布: ' + best);
  if (installed && !gt(best, installed)) { console.log('[dsh] 已是最新，无需更新。'); return 'fresh'; }
  console.log('[dsh] 发现新版本 ' + best + '，开始自动更新 ...');
  if (DRYRUN) { console.log('[dsh] dry-run：跳过安装。'); return 'would-update'; }
  try {
    sh('npm.cmd install -g ' + PKG + '@' + best + ' --no-fund --no-audit --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,fs-ext', true);
  } catch (e) { /* npm 非零退出不直接判失败，按安装后实际版本判断 */ }
  const afterVer = readVer();
  if (afterVer === best) {
    console.log('[dsh] 更新完成，当前版本: ' + afterVer);
    return 'updated';
  }
  console.log('[dsh] 自动更新未生效：安装后版本仍为 ' + (afterVer || '(未知)') + '。');
  // 回滚：把全局安装恢复到升级前的版本，避免"更新到一半"导致 dsh 起不来
  if (installed && installed !== afterVer) {
    console.log('[dsh] 尝试回滚到更新前的版本 ' + installed + ' ...');
    try {
      sh('npm.cmd install -g ' + PKG + '@' + installed + ' --no-fund --no-audit --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,fs-ext', true);
    } catch (e) { /* 继续看实际版本 */ }
    const rolled = readVer();
    if (rolled === installed) {
      console.log('[dsh] 已回滚到 ' + rolled + '，本次用回滚后的版本启动。');
      return 'rolled';
    }
    console.log('[dsh] 回滚也失败，当前版本 ' + (rolled || '(未知)') + '，仍按现状启动。');
  }
  console.log('[dsh]   常见原因：npm 镜像(registry.npmmirror.com)尚未同步该版本的全部依赖子包(ETARGET)，稍后重跑本脚本即可自动补上。');
  console.log('[dsh]   本次继续用当前版本启动。');
  return 'fail';
}

function checkPlugins() {
  const host = hostDshVersion();
  console.log('[dsh] 宿主(web profile) dsh 框架: ' + (host || '(未找到)') + '  开始核对插件版本 ...');
  let problems = 0;
  for (const name of PLUGINS) {
    let p = locatePlugin(name);
    if (!p) {
      console.log('[dsh] 插件未安装: ' + name);
      if (DRYRUN) { console.log('  -> dry-run：跳过安装'); problems++; continue; }
      if (!AUTO_FIX) { problems++; continue; }
      try { sh(pluginCmd(name, false), true); } catch (e) { console.log('  -> 自动安装失败'); problems++; continue; }
      p = locatePlugin(name);
      if (!p) { console.log('  -> 安装后仍未找到'); problems++; continue; }
    }
    const m = readJson(p);
    const ver = (m && m.version) || '?';
    const label = name + '@' + ver;
    const failures = [];
    const checked = [];
    const engDsh = (m && m.dsh && m.dsh.engines && m.dsh.engines.dsh) || (m && m.engines && m.engines.dsh) || '';
    if (engDsh && host) {
      checked.push('engines.dsh ' + engDsh);
      const r = sat(host, engDsh);
      if (r === false) failures.push('宿主 dsh ' + host + ' 不满足 engines.dsh ' + engDsh);
    }
    const peers = (m && m.peerDependencies) || {};
    for (const peer of Object.keys(peers)) {
      if (peer.indexOf('@deepseek-ai/') !== 0) continue;
      const range = peers[peer];
      const hv = resolveHostVersion(peer);
      if (!hv) continue;
      checked.push(peer.slice(1) + ' ' + range);
      const r = sat(hv, range);
      if (r === false) failures.push('宿主 ' + peer + '@' + hv + ' 不满足插件要求的 ' + range);
    }
    if (failures.length === 0) {
      console.log('[dsh] 通过: ' + label + ' 与宿主 dsh ' + host + ' 对应' + (checked.length ? '（' + checked.join('; ') + '）' : ''));
    } else {
      console.log('[dsh] 不匹配: ' + label + ' 与宿主 dsh ' + host);
      for (const f of failures) console.log('    - ' + f);
      if (!DRYRUN && AUTO_FIX) {
        console.log('    -> 尝试把插件升级到最新版 ...');
        try {
          sh(pluginCmd(name, true), true);
          const p2 = locatePlugin(name);
          const m2 = p2 ? readJson(p2) : null;
          console.log('    -> ' + name + ' 已更新为 ' + ((m2 && m2.version) || '?') + '，下次启动复核');
        } catch (e2) { console.log('    -> 自动升级失败'); }
      }
      problems++;
    }
  }
  if (problems === 0) console.log('[dsh] 全部插件与宿主 dsh 版本对应。');
  else console.log('[dsh] ' + problems + ' 个插件存在版本对应问题（见上）。');
  return problems;
}

try {
  const state = updateDsh();
  if (!DRYRUN) {
    if (state === 'updated' || state === 'would-update' || state === 'fail') console.log('[dsh] dsh 版本有变化，同步核对插件 ...');
    checkPlugins();
  } else {
    console.log('[dsh] dry-run：只检查 dsh，不核对插件（DRYRUN=0 时核对）。');
  }
  process.exit(0);
} catch (e) {
  console.log('[dsh] helper 异常: ' + firstLine(String((e && e.message) || e)));
  process.exit(1);
}
