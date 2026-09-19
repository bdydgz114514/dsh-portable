# dsh-video-search

给 DeepSeek Harness 装一个 `video_search` 工具：**联网调研时主动去找视频**，
而不是只看文字结果。

## 它解决什么

模型默认只在文字里找答案。但中文技术场景（刷机/root/解锁/模块/工具用法）的实操经验
**大量只存在于B站视频里**，纯文字搜索找不到。本插件提供：

- `video_search(query, limit)` —— B站搜索，返回标题/链接/UP主/时长/播放/发布时间/简介
- 一段**行为准则提示词**（`tool:video_search`，order 2050）：文字结果稀薄、主题偏操作/演示、
  或中文内容时，**主动找视频**；有希望的再交给 `video_understand` 读懂内容
- 明确的"**绝不编造视频链接**"约束

## 安装（本机已完成）

```powershell
dsh plugin --profile web add D:\ai\gongzuoqu\tools\dsh-video-search
```

会以 pnpm `link:` 方式挂进 `~/.dsh/profiles/web`，改源码即时生效；
`dsh/index.js` 改动需重启 `dsh web`。

## 自检

```powershell
node D:\ai\gongzuoqu\tools\dsh-video-search\selftest.mjs "展锐 刷机 解锁"
```

## 搭配

`video_search` 只给元数据（快、便宜）；要"看懂"内容用
`video_understand(target="<BV 号>")`（来自 `dsh-video-understand` 插件）。
两边合计一次完整"找 + 看懂"约 ¥0.008。

细节与排障见技能 `video-research-first` 的
[`references/video-search-notes.md`](../../../../Users/Administrator/.dsh/skills/video-research-first/references/video-search-notes.md)。
