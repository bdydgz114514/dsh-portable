#Requires -Version 5.1
<#
.SYNOPSIS
  把 dsh-portable 完整包还原到本机（DSH 程序本体 + ~/.dsh 全部数据 + 插件 + 技能）。

.DESCRIPTION
  本脚本把包内快照原样还原到 DSH 的标准位置，使其行为与原机完全一致：
    1. %APPDATA%\npm\                   <- npm-global\        （dsh 命令垫片 + pnpm 垫片）
    2. %APPDATA%\npm\node_modules\      <- npm-global\node_modules\ （DSH 程序本体 226 MB）
    3. %USERPROFILE%\.dsh\              <- dsh-home\          （个人数据与设置 约 2.99 GB）
    4. %APPDATA%\uv\python\             <- uv-python\         （video-understand 的 Python 基础解释器）
  然后：
    5. 依据 links.json 重建 677 个目录联接（junction）
    6. 补齐 3 个指向原机 D:\ 的 link: 插件（用包内 workspace-tools 副本）
    7. 修正 .venv\pyvenv.cfg 的 home 路径
    8. 把 %APPDATA%\npm 与包内 uv\ 加进用户 PATH，最后自检

  已存在的同名目录会先被重命名成 *.bak-<时间戳>，不会直接删除。

.PARAMETER DryRun
  只打印将要执行的操作，不改动任何文件。

.PARAMETER Force
  不备份，直接覆盖已存在的目标目录（危险）。

.PARAMETER SkipUvPython
  不还原 uv 的 Python 基础解释器（video-understand 首次使用时会自行重建 .venv）。

.PARAMETER SkipLinks
  不重建 junction（只有在目标已经是同一台机器、路径未变时才可跳过）。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
#>
[CmdletBinding()]
param(
  [switch]$DryRun,
  [switch]$Force,
  [switch]$SkipUvPython,
  [switch]$SkipLinks
)

$ErrorActionPreference = 'Stop'
$script:Pkg      = $PSScriptRoot
$script:Stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:Failures = @()

function Say  { param([string]$t) Write-Host $t }
function Head { param([string]$t) Write-Host ''; Write-Host ('== ' + $t) -ForegroundColor Cyan }
function Ok   { param([string]$t) Write-Host ('   [OK]   ' + $t) -ForegroundColor Green }
function Info { param([string]$t) Write-Host ('   [..]   ' + $t) -ForegroundColor Gray }
function Warn { param([string]$t) Write-Host ('   [警告] ' + $t) -ForegroundColor Yellow }
function Bad  { param([string]$t) Write-Host ('   [失败] ' + $t) -ForegroundColor Red; $script:Failures += $t }
function Plan { param([string]$t) Write-Host ('   [试运行] ' + $t) -ForegroundColor Magenta }

function Invoke-Robo {
  param([string]$Label, [string]$Src, [string]$Dst, [string[]]$Extra = @())
  if (-not (Test-Path -LiteralPath $Src)) { Warn ('源不存在，跳过: ' + $Src); return }
  if ($DryRun) { Plan ('robocopy ' + $Src + ' -> ' + $Dst); return }
  New-Item -ItemType Directory -Force -Path $Dst | Out-Null
  $a = @($Src, $Dst, '/E', '/XJ', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/MT:32') + $Extra
  & robocopy @a | Out-Null
  $code = $LASTEXITCODE
  $global:LASTEXITCODE = 0
  if ($code -ge 8) { Bad ($Label + ' : robocopy 退出码 ' + $code) } else { Ok ($Label + ' 完成') }
}

function Backup-Existing {
  param([string]$Path, [string]$Label)
  if (-not (Test-Path -LiteralPath $Path)) { return }
  if ($Force) {
    if ($DryRun) { Plan ('删除已存在: ' + $Path) }
    else { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue; Info ('已移除旧 ' + $Path) }
    return
  }
  $bak = $Path + '.bak-' + $script:Stamp
  if ($DryRun) { Plan ('备份 ' + $Path + ' -> ' + $bak); return }
  try {
    Move-Item -LiteralPath $Path -Destination $bak -Force -ErrorAction Stop
    Ok ('已备份 ' + $Label + ' -> ' + $bak)
  } catch {
    Bad ('备份 ' + $Label + ' 失败: ' + $_.Exception.Message)
  }
}

# ---------------------------------------------------------------- 0. 环境检查
Head '0/8 环境检查'
if (-not (Test-Path -LiteralPath $script:Pkg)) { Bad ('找不到脚本目录: ' + $script:Pkg); exit 1 }
Say ('包目录        : ' + $script:Pkg)

$node = Get-Command node.exe -ErrorAction SilentlyContinue
if (-not $node) {
  Bad '找不到 node.exe。请先安装 Node.js 18+（https://nodejs.org/ 或 winget install OpenJS.NodeJS.LTS），再运行本脚本。'
  exit 1
}
Say ('node          : ' + (& node -v))

$DshHome   = Join-Path $env:USERPROFILE '.dsh'
$NpmPrefix = Join-Path $env:APPDATA 'npm'
$UvPython  = Join-Path $env:APPDATA 'uv\python'
$PkgDsh    = Join-Path $NpmPrefix 'node_modules\@deepseek-ai\dsh'
Say ('DSH_HOME      : ' + $DshHome)
Say ('npm 全局目录  : ' + $NpmPrefix)
Say ('uv python 目录: ' + $UvPython)
if ($DryRun) { Write-Host '模式          : 试运行（不做任何改动）' -ForegroundColor Magenta }

foreach ($d in @('npm-global', 'dsh-home', 'scripts', 'links.json')) {
  if (-not (Test-Path -LiteralPath (Join-Path $script:Pkg $d))) {
    Bad ('包不完整：缺少 ' + $d + '。请确认已完整解压（分卷要把 .001/.002... 放同一目录解压）。')
  }
}
if ($script:Failures.Count -gt 0) { exit 1 }

# ---------------------------------------------------------------- 1. 备份
Head '1/8 备份已存在的目录'
Backup-Existing -Path $DshHome -Label 'DSH_HOME'
Backup-Existing -Path $PkgDsh  -Label 'DSH 程序本体'

# ---------------------------------------------------------------- 2. 程序本体
Head '2/8 还原 DSH 程序本体与命令垫片'
Invoke-Robo -Label 'npm 命令垫片'  -Src (Join-Path $script:Pkg 'npm-global') -Dst $NpmPrefix -Extra @('/XD', 'node_modules')
Invoke-Robo -Label 'DSH 程序本体'  -Src (Join-Path $script:Pkg 'npm-global\node_modules') -Dst (Join-Path $NpmPrefix 'node_modules')

# ---------------------------------------------------------------- 3. 个人数据
Head '3/8 还原 DSH 个人数据（~/.dsh，约 2.99 GB，请稍候）'
Invoke-Robo -Label 'dsh-home' -Src (Join-Path $script:Pkg 'dsh-home') -Dst $DshHome -Extra @('/XF', '.credentials.yaml')

# ---------------------------------------------------------------- 4. uv Python
Head '4/8 还原 uv 的 Python 基础解释器'
if ($SkipUvPython) {
  Info '按 -SkipUvPython 跳过'
} else {
  $srcUvPy = Join-Path $script:Pkg 'uv-python'
  if (Test-Path -LiteralPath $srcUvPy) {
    Invoke-Robo -Label 'uv python' -Src $srcUvPy -Dst $UvPython
  } else {
    Warn '包内没有 uv-python 目录，跳过（video-understand 首次使用时会自行重建 .venv）'
  }
}
$uvDir = Join-Path $script:Pkg 'uv'
if (Test-Path -LiteralPath $uvDir) {
  $userPath0 = [Environment]::GetEnvironmentVariable('PATH', 'User')
  if ($userPath0 -notlike ('*' + $uvDir + '*')) {
    if ($DryRun) { Plan ('把 ' + $uvDir + ' 加进用户 PATH') }
    else {
      [Environment]::SetEnvironmentVariable('PATH', ($userPath0.TrimEnd(';') + ';' + $uvDir), 'User')
      $env:PATH = $env:PATH + ';' + $uvDir
      Ok ('已把 uv 目录加进用户 PATH: ' + $uvDir)
    }
  }
}

# ---------------------------------------------------------------- 5. junction
Head '5/8 重建目录联接（junction）'
$linksFile = Join-Path $script:Pkg 'links.json'
if ($SkipLinks) {
  Info '按 -SkipLinks 跳过'
} elseif (Test-Path -LiteralPath $linksFile) {
  $parsed = Get-Content -LiteralPath $linksFile -Raw -Encoding UTF8 | ConvertFrom-Json; $links = @(); foreach ($one in $parsed) { $links += $one }
  Say ('   links.json 条目数: ' + $links.Count)
  $made = 0; $skipped = 0; $failed = 0
  foreach ($l in $links) {
    $p = Join-Path $DshHome ($l.path -replace '/', '\')
    $t = $l.target.Replace('{DSH_HOME}', $DshHome).Replace('{NPM_GLOBAL}', $NpmPrefix)
    if (-not (Test-Path -LiteralPath $t)) { $skipped++; continue }
    if ($DryRun) { $made++; continue }
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
    try {
      New-Item -ItemType Junction -Path $p -Target $t -ErrorAction Stop | Out-Null
      $made++
    } catch {
      $failed++
      if ($failed -le 5) { Warn ('创建联接失败: ' + $p + ' -> ' + $t + ' : ' + $_.Exception.Message) }
    }
  }
  if ($DryRun) { Plan ('将创建 ' + $made + ' 个 junction，跳过 ' + $skipped + ' 个') }
  else {
    Ok ('已创建 ' + $made + ' 个 junction（跳过 ' + $skipped + ' 个目标不存在的）')
    if ($failed -gt 0) { Warn ('有 ' + $failed + ' 个联接创建失败，插件可能找不到宿主依赖。') }
  }
} else {
  Warn '包内没有 links.json，跳过联接重建'
}

# ------------------------------------------------- 5b. link: 插件兜底补齐
Head '5b/8 补齐指向原机路径的 link: 插件'
$fallbacks = @(
  @{ Rel = 'profiles\web\node_modules\dsh-video-search';                Src = 'dsh-video-search' },
  @{ Rel = 'profiles\web\node_modules\@deepseek-ai\dsh-tool-knowledge'; Src = 'dsh-tool-knowledge' },
  @{ Rel = 'profiles\node_modules\@deepseek-ai\dsh-tool-knowledge';     Src = 'dsh-tool-knowledge' }
)
foreach ($fb in $fallbacks) {
  $dest = Join-Path $DshHome $fb.Rel
  if (Test-Path -LiteralPath $dest) { Info ('已存在，跳过: ' + $fb.Rel); continue }
  $source = Join-Path $script:Pkg ('workspace-tools\' + $fb.Src)
  if (-not (Test-Path -LiteralPath $source)) { Warn ('包内缺少副本: ' + $source); continue }
  Invoke-Robo -Label ('补齐 ' + $fb.Rel) -Src $source -Dst $dest
}

# ---------------------------------------------------------------- 6. venv
Head '6/8 修正 Python 虚拟环境路径'
$cfg = Join-Path $DshHome 'profiles\web\node_modules\dsh-video-understand\.venv\pyvenv.cfg'
if (Test-Path -LiteralPath $cfg) {
  $newHome = Join-Path $UvPython 'cpython-3.13-windows-x86_64-none'
  $txt = [System.IO.File]::ReadAllText($cfg)
  if ($txt -match '(?m)^home\s*=\s*(.+)$') {
    $oldHome = $Matches[1].Trim()
    if ($oldHome -ne $newHome) {
      if ($DryRun) { Plan ('pyvenv.cfg home: ' + $oldHome + ' -> ' + $newHome) }
      else {
        $txt = [regex]::Replace($txt, '(?m)^home\s*=.*$', ('home = ' + $newHome))
        [System.IO.File]::WriteAllText($cfg, $txt, (New-Object System.Text.UTF8Encoding($false)))
        Ok ('pyvenv.cfg home 已更新为 ' + $newHome)
      }
    } else { Ok 'pyvenv.cfg home 无需修改' }
  }
  if (-not (Test-Path -LiteralPath $newHome)) {
    Warn ('找不到基础解释器目录: ' + $newHome)
    Warn 'video-understand 首次调用时会用 uv 自动重建 .venv（需要联网），或运行 .\repair-venv.ps1'
  }
} else {
  Info '未找到 dsh-video-understand/.venv/pyvenv.cfg，跳过'
}

# ---------------------------------------------------------------- 7. PATH
Head '7/8 检查用户 PATH'
$userPath2 = [Environment]::GetEnvironmentVariable('PATH', 'User')
if ($userPath2 -notlike ('*' + $NpmPrefix + '*')) {
  if ($DryRun) { Plan ('把 ' + $NpmPrefix + ' 加进用户 PATH') }
  else {
    [Environment]::SetEnvironmentVariable('PATH', ($userPath2.TrimEnd(';') + ';' + $NpmPrefix), 'User')
    $env:PATH = $env:PATH + ';' + $NpmPrefix
    Ok ('已把 ' + $NpmPrefix + ' 加进用户 PATH')
  }
} else { Ok 'npm 全局目录已在用户 PATH 中' }

# ---------------------------------------------------------------- 8. 自检
Head '8/8 自检'
if ($DryRun) { Write-Host '试运行结束，未做任何改动。' -ForegroundColor Magenta; exit 0 }

$binJs = Join-Path $PkgDsh 'lib\bin.js'
if (Test-Path -LiteralPath $binJs) {
  try {
    $v = (& node $binJs --version 2>&1 | Out-String).Trim()
    Ok ('dsh 版本: ' + $v)
  } catch { Warn ('dsh --version 执行失败: ' + $_.Exception.Message) }
} else { Bad ('找不到 ' + $binJs) }

foreach ($d in @($DshHome, $PkgDsh, (Join-Path $DshHome 'profiles\web\node_modules'))) {
  if (Test-Path -LiteralPath $d) { Ok ('存在: ' + $d) } else { Bad ('缺失: ' + $d) }
}
if (Test-Path -LiteralPath (Join-Path $DshHome '.credentials.yaml')) {
  Ok '检测到 .credentials.yaml'
} else {
  Warn '未检测到 ~/.dsh/.credentials.yaml —— 需要自行配置 DeepSeek API Key（见 README 第四节）'
}

Write-Host ''
Write-Host '安装完成。下一步：' -ForegroundColor White
Write-Host '  1) 配置 API Key:  setx DEEPSEEK_API_KEY "sk-你的key"   （或启动后在 Models 页面填写）'
Write-Host ('  2) 启动:          ' + (Join-Path $script:Pkg 'scripts\start-dsh-auto-update.bat'))
Write-Host '  3) 浏览器打开:    http://127.0.0.1:3080/'
Write-Host ''
if ($script:Failures.Count -gt 0) {
  Write-Host '以下步骤失败，请处理后重跑：' -ForegroundColor Yellow
  $script:Failures | ForEach-Object { Write-Host ('  - ' + $_) -ForegroundColor Yellow }
  exit 1
}
exit 0
