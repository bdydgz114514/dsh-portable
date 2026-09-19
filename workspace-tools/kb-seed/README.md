# kb-seed —— 往手机 DSH 知识库批量写入条目

手机 App 的知识库是 `$DSH_KNOWLEDGE_DIR`（`/sdcard/DeepSeekHarness/knowledge`）下的
`kb.sqlite`（SQLite + FTS5 trigram 全文检索）+ `entries/<id>.md`。

这个目录里的 `entries.json` 是我整理的条目，`seed.mjs` 用**知识库插件自己的 `kb_add` 工具**写入
（不重复实现存储逻辑，schema/ID 规则/markdown 格式与插件完全一致）。

## 用法

```sh
# 1) 把插件模块就地复制一份（让它的 import 能解析到内核依赖）
K=<内核>/dshroot/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-tool-knowledge/lib
cp "$K/index.js" "$K/__kbseed.mjs"

# 2) 写入到一个临时 KB 目录（或直接指向要合并的目标库）
node seed.mjs <KB目录> ../kb-seed/entries.json

# 3) 把 kb.sqlite 和 entries/*.md 推到手机
adb push <KB目录>/kb.sqlite /sdcard/DeepSeekHarness/knowledge/kb.sqlite
for f in <KB目录>/entries/*.md; do adb push "$f" /sdcard/DeepSeekHarness/knowledge/entries/; done
adb shell rm -f /sdcard/DeepSeekHarness/knowledge/kb.sqlite-wal /sdcard/DeepSeekHarness/knowledge/kb.sqlite-shm

# 4) 验证：拉回来用插件自己的 kb_search 查
adb pull /sdcard/DeepSeekHarness/knowledge/kb.sqlite /tmp/kb.sqlite
node search.mjs /tmp <关键词>
```

## 电脑端（DSH on Windows）

电脑上已经装好同一套知识库插件，位置与接入方式：

| 项 | 值 |
|---|---|
| 插件源码 | `D:\ai\gongzuoqu\tools\dsh-tool-knowledge`（来自安卓定制项目，npm 上没有独立包） |
| 接入方式 | `~/.dsh/profiles/web/package.json` 里一条 `link:` 依赖 + `profiles/web/cordis.patch.yml` 里一条 `insert` |
| node_modules | `~/.dsh/profiles/node_modules/@deepseek-ai/dsh-tool-knowledge`（pnpm 建的 junction） |
| 知识库位置 | `~/.dsh/knowledge/kb.sqlite`（可用 `DSH_KNOWLEDGE_DIR` 覆盖） |
| 依赖 | 插件自身零依赖，只用 node 内建模块；但源码树内建了 `node_modules/@deepseek-ai/{dsh-tools,dsh-llm,dsh-session,schemastery}` 的 junction 供 ESM 解析 |

**千万不要**把插件写进 `package.json` 的 `dsh.profile.bundles`——那是给 `dsh.bundle` 型包用的，
该插件是 `dsh.plugin` 型，只能走 `insert`，否则报：

```
profile bundle "@deepseek-ai/dsh-tool-knowledge" declares no dsh.bundle in its package.json
```

重新安装（换机/换路径时）：

```sh
cd ~/.dsh/profiles/web
pnpm add "@deepseek-ai/dsh-tool-knowledge@link:D:/ai/gongzuoqu/tools/dsh-tool-knowledge" --prefer-offline --ignore-scripts
# 然后确认 profiles/web/cordis.patch.yml 里有：
#   - insert:
#       - id: tool-knowledge
#         name: '@deepseek-ai/dsh-tool-knowledge'
```

装完重启 DSH，会话里就会出现 `kb_search / kb_add / kb_list / kb_stats / kb_delete / kb_get / kb_digest`。

## 手机 ↔ 电脑 同步条目

两边是不同的库（手机 `/sdcard/DeepSeekHarness/knowledge`，电脑 `~/.dsh/knowledge`）。合并时以一边为准整体推送：

```sh
adb shell am force-stop com.deepseek.harness          # 先停应用，避免它占着 WAL
adb push ~/.dsh/knowledge/kb.sqlite /sdcard/DeepSeekHarness/knowledge/kb.sqlite
for f in ~/.dsh/knowledge/entries/*.md; do adb push "$f" /sdcard/DeepSeekHarness/knowledge/entries/; done
adb shell rm -f /sdcard/DeepSeekHarness/knowledge/kb.sqlite-wal /sdcard/DeepSeekHarness/knowledge/kb.sqlite-shm
adb shell am start -n com.deepseek.harness/.MainActivity
```

## 三个坑

1. **`adb push 目录 目标/` 会嵌套**：`adb push entries /sdcard/.../entries` 会变成 `entries/entries`。要逐个 push 文件，或用 `entries/.`。
2. **推完必须删掉设备上旧的 `kb.sqlite-wal` / `-shm`**，否则 WAL 里旧内容会盖住你推的主库。
3. **别把 `__kbseed.mjs` 之类临时文件留在内核树里**，打包会带上（记得用完删掉）。

## 检索行为

FTS5 trigram 是**按短语/子串**匹配，不是分词 AND。查 `flock`、`工作区` 命中很正常；
查 `工作区 弹回`（两个词）会查不到——这是预期，不是数据坏了。