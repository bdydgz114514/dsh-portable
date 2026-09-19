# DSH 便携完整包（dsh-portable）

> 这是一份 **DeepSeek Harness（DSH）的完整快照**：程序本体 + 全部已装插件 + 全部个人设置 + 技能 + 工具链，解压安装后即可直接使用，无需再联网安装任何依赖。

- 对应版本：`@deepseek-ai/dsh@0.1.6-alpha.2`
- 包内容量：**约 3.4 GB / 约 10.5 万个文件**（解压后）
- 打包自：`C:\Users\Administrator`（原机 Windows）
- 唯一被剔除的文件：`~\.dsh\.credentials.yaml`（**里面是你的 API Key，不能公开**）

---

## 一、快速开始（3 步）

1. 下载 `dsh-portable.7z`（或分卷 `dsh-portable.7z.001`, `.002` …），用 **7-Zip / WinRAR / Bandizip** 解压到任意目录。
   > 建议解压到短路径，例如 `C:\dsh`（Windows 路径上限 260 字符，虽然本包最长路径只有 233 字符，短一点更保险）。
   > 分卷解压：把 `.001` `.002` … 放在同一目录，右键 `.001` → 解压即可。

2. 以**管理员身份**或普通身份打开 PowerShell，运行安装脚本：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
   ```

   想先看看它会做什么（不改动任何文件）：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
   ```

3. 双击 `scripts\start-dsh-auto-update.bat`（也可以把 `scripts` 里的文件复制到桌面再双击）。
   浏览器会自动打开 <http://127.0.0.1:3080/>。

> **第一次启动前请准备 DeepSeek API Key**（见下面第四节），否则模型页面会提示未配置。

---

## 二、安装脚本做了什么

`install.ps1` 把包内内容**原样还原回 DSH 的标准位置**，所以行为和原机完全一致：

| 包内路径 | 还原到 | 说明 |
|---|---|---|
| `npm-global\` | `%APPDATA%\npm\` | `dsh` / `dsh.cmd` / `dsh.ps1` 命令垫片，以及 pnpm 垫片 |
| `npm-global\node_modules\` | `%APPDATA%\npm\node_modules\` | DSH 程序本体（`@deepseek-ai/dsh`，226 MB，含全部依赖）|
| `dsh-home\` | `%USERPROFILE%\.dsh\` | 你的全部个人数据与设置（≈2.99 GB）|
| `uv-python\` | `%APPDATA%\uv\python\` | `dsh-video-understand` 的 Python 3.13 基础解释器 |
| `uv\uv.exe` | 保留在包内 | 插件自愈用的 uv（会被加进用户 PATH）|
| `scripts\` | 保留在包内 | 启动 / 卸载脚本 |
| `workspace-tools\` | 保留在包内 | 本地 `link:` 插件源码备份（运行时已内联进 `node_modules`）|

另外脚本还会：

- **自动备份**：如果本机已有 `~\.dsh` 或旧的 dsh 包，会先重命名成 `*.bak-<时间戳>`，不会直接删。
- **重建目录联接（junction）**：包里记录了 **677 个 junction**（`links.json`），它们原本指向原机的绝对路径，安装时按新机器的路径重新创建，插件才找得到宿主依赖。
- **修正 Python 虚拟环境**：重写 `.venv\pyvenv.cfg` 里的 `home` 路径，让 `dsh-video-understand` 的 Python 环境在新机器上继续可用。
- **把 `%APPDATA%\npm` 和包内 `uv\` 目录加进用户 PATH**（如果还没有）。

---

## 三、包内目录结构

```
dsh-portable/
├── README.md                 本文档
├── install.ps1               一键安装 / 还原
├── links.json                677 个 junction 的清单（安装时据此重建）
├── repair-venv.ps1           重建 video-understand 的 Python 虚拟环境（备用）
├── npm-global/               npm 全局目录快照（垫片 + DSH 程序本体）
│   ├── dsh / dsh.cmd / dsh.ps1 / pn* / pnpm* / pnpx* / pnx*
│   └── node_modules/@deepseek-ai/dsh/      ← DSH 程序本体 226 MB
├── dsh-home/                 ~/.dsh 的完整快照（除 .credentials.yaml）
│   ├── settings.yaml         你的设置（默认模型 deepseek-flash、danger-full-access 等）
│   ├── boot-check.mjs        启动前预检
│   ├── preflight.mjs         预检实现
│   ├── profiles/web/         web profile：插件配置 + 插件本体（含 dsh-video-understand/.venv）
│   ├── skills/               5 个技能：gongzuoqu-workspace-map / unisoc-brom-unlock /
│   │                         dsh-video-understand-ops / video-research-first / video-understand
│   ├── knowledge/            知识库（kb.sqlite 396 MB + entries/）
│   ├── sessions/             历史会话
│   ├── attachments/          历史附件
│   ├── storages/ skins/ skin-center/ task-board/ cache/ … 其余全部状态
│   └── links.json 里指向的 677 个 junction 在安装时重建
├── uv-python/                uv 管理的 CPython 3.13（video-understand 的基础解释器）
├── uv/                       uv.exe / uvx.exe
├── scripts/                  启动与卸载脚本
│   ├── start-dsh-auto-update.bat   启动器（自动检查更新 + 插件版本）
│   ├── dsh-start-helper.mjs        启动器的 node 助手
│   ├── uninstall-dsh.cmd           卸载入口
│   └── uninstall-dsh.ps1           卸载实现（-DryRun 可预览）
└── workspace-tools/          本地 link: 插件源码备份
    ├── dsh-tool-knowledge/   本地知识库插件源码
    ├── dsh-video-search/     B 站视频搜索插件源码
    ├── video-work/           视频理解插件补丁集
    └── kb-seed/              知识库种子
```

---

## 四、配置 DeepSeek API Key（必做）

出于安全原因，**包内不含 `.credentials.yaml`**（原文件里是你的 `DEEPSEEK_API_KEY`）。
密钥的解析优先级是：**启动环境变量 > `~\.dsh\.credentials.yaml` > 当前目录 `.env` > `~\.dsh\.env`**。

任选一种：

**方式 A（推荐，图形界面）**：启动 DSH 后，在 Web 界面里打开 **Models / 模型** 页面，填入 API Key 并保存。它会自动写进 `~\.dsh\.credentials.yaml`。

**方式 B（环境变量，永久生效）**：

```powershell
setx DEEPSEEK_API_KEY "sk-你的key"
```
（执行后需要重开终端 / 重新双击 bat 才生效。）

**方式 C（直接写文件）**：新建 `%USERPROFILE%\.dsh\.credentials.yaml`：

```yaml
refs:
  DEEPSEEK_API_KEY: sk-你的key
```

---

## 五、启动与停止

- **启动**：双击 `scripts\start-dsh-auto-update.bat`，或命令行 `dsh web`。
- **端口**：默认 3080。已被占用时会自动复用已在跑的实例并打开浏览器；要强制重启用
  `set DSH_FORCE_RESTART=1` 后再运行；换端口用 `set DSH_PORT=3099`。
- **不检查更新直接启动**：`set DSH_UPDATE_MODE=off` 后再运行（本包是完整离线快照，建议离线用）。
- **只检查不启动**：`set DSH_DRYRUN=1`。
- **停止**：关掉运行 bat 的控制台窗口即可；或 `taskkill /F /IM node.exe`（会杀掉所有 node 进程，慎用）。

---

## 六、卸载

```powershell
# 先预览
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\uninstall-dsh.ps1 -DryRun
# 真正卸载（会结束 dsh 进程、npm 卸载、删 ~/.dsh）
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\uninstall-dsh.ps1
```

或直接双击 `scripts\uninstall-dsh.cmd`。
常用参数：`-KeepData`（保留 `~\.dsh`）、`-CleanCache`（顺带清 npm/pnpm 缓存）、`-Force`。

> ⚠️ 卸载脚本会删掉 `%USERPROFILE%\.dsh`，也就是本包还原出来的全部数据。想留档请先备份。

---

## 七、视频理解插件的 Python 环境

`dsh-home/profiles/web/node_modules/dsh-video-understand/.venv` 里是一个 **1.63 GB 的 Python 虚拟环境**
（torch / opencv / ctranslate2 / funasr / yt-dlp …），基础解释器来自 uv 管理的 CPython 3.13，
已一并打包在 `uv-python/` 下。

- 如果安装机器的用户名也是 `Administrator`，`install.ps1` 修完 `pyvenv.cfg` 后**开箱即用**。
- 如果用户名不同或路径被破坏，插件会**自愈**：首次调用 `video_understand` 时检测到依赖缺失，
  会自动用 uv（已随包提供）重建 `.venv` 并安装依赖（需要联网，约 1–3 分钟）。
- 也可以手动修：

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File .\repair-venv.ps1
  ```

---

## 八、这个包适合谁 / 注意事项

- **适合**：想在一台新 Windows 机器上还原出一模一样的 DSH 环境；或想把整套配置分享给别人。
- **注意 1**：包含**历史会话、附件、知识库**等个人数据，公开仓库里这些东西是可见的，介意的话请自行删除后再分发。
- **注意 2**：`profiles\web\package.json` 里有两个 `link:` 依赖指向原机的
  `D:\ai\gongzuoqu\tools\...`。本包已把它们的**实际内容内联**到
  `node_modules` 里（不是软链），所以不依赖那个盘符。但如果你之后执行
  `dsh plugin ...` 重装插件，pnpm 会重新去那个路径找源码 —— 需要时把
  `workspace-tools\*` 复制回 `D:\ai\gongzuoqu\tools\` 即可。
- **注意 3**：DSH 在 `~\.dsh\settings.yaml` 里把权限预设设成了 `danger-full-access`，
  也就是 AI 可以不受沙箱限制地读写文件、执行命令。这是原机设置，**请自行判断是否保留**。

---

## 九、打包时的两处安全处理（必读）

1. **剔除了密钥文件**：包内**没有** `~\.dsh\.credentials.yaml`（原文件里是 `DEEPSEEK_API_KEY`）。安装后请自行配置，见第四节。
2. **擦除了历史会话里泄露过的 Token**：`~\.dsh\storages\session_projcache\sessions\` 下有两个历史会话缓存 JSON，内容里曾经粘贴过一个 GitHub Personal Access Token（`ghp_...`）。打包时已把这些字符串替换成 `REDACTED_BY_PACKER`，其余内容保持原样。

> ⚠️ **请到 GitHub 设置里吊销那个 Token 并重新生成** —— 它已经出现在公开场合。

除以上两点外，包内文件与打包瞬间的原机状态一致。唯一的结构性差异见第八节「注意 2」：3 个指向 `D:\ai\gongzuoqu\tools\` 的 `link:` 软链被替换成了真实目录副本。

## 十、来源与致谢


- DSH 本体：`@deepseek-ai/dsh`（npm 包，MIT），官方仓库
  <https://github.com/deepseek-ai/deepseek-harness>
- 视频理解插件：`dsh-video-understand` <https://github.com/ilps2/dsh-video-understand>
- 其余第三方插件（dshmarket / dsh-better-sidebar / dsh-context / @linxin666/dsh-web-all）
  版权归各自作者所有。
- 本仓库只是**一份个人环境的快照备份**，不是 DSH 官方发行版。
