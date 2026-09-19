#Requires -Version 5.1
<#
.SYNOPSIS
  彻底卸载 DSH (DeepSeek Harness) 及其全部数据。

.DESCRIPTION
  按顺序完成：
    1. 结束正在运行的 dsh 进程（node.exe 中加载 @deepseek-ai/dsh 的那些）
    2. npm 全局卸载 @deepseek-ai/dsh，并清理残留的 dsh / dsh.cmd / dsh.ps1 命令垫片
    3. 删除 DSH_HOME 数据目录（%USERPROFILE%\.dsh）、dshhome、以及误建在用户主目录的 profiles
    4. 可选：清理 %TEMP% 下 dsh-* 临时文件、npm 缓存、pnpm 未引用包

  不会碰你自己的项目目录（例如 D:\ai\gongzuoqu\dsh-android），也不会卸载 pnpm。

.USAGE
  请在一个“外部”PowerShell 窗口里运行（不要在本 dsh 会话内部运行，否则会把自己杀掉）：
    powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall-dsh.ps1 -DryRun   # 只预览
    powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall-dsh.ps1           # 真正执行

  常用参数：
    -KeepData        保留 %USERPROFILE%\.dsh（会话/凭据/设置等）
    -KeepHomeDirs    保留 dshhome 和误建的 ~\profiles
    -CleanCache      额外清空 npm 缓存并执行 pnpm store prune（较慢）
    -Force           即使检测到是在 dsh 会话内运行也继续
    -DryRun          只打印将要执行的动作，不实际改动任何东西
#>
[CmdletBinding()]
param(
  [switch]$DryRun,
  [switch]$KeepData,
  [switch]$KeepHomeDirs,
  [switch]$CleanCache,
  [switch]$Force
)

$ErrorActionPreference = 'Continue'
$script:Failed  = @()
$script:Removed = @()

function Write-Step { param([string]$Text) Write-Host ""; Write-Host "== $Text" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Text) Write-Host "   [完成] $Text" -ForegroundColor Green }
function Write-Skip { param([string]$Text) Write-Host "   [跳过] $Text" -ForegroundColor DarkGray }
function Write-Warn2{ param([string]$Text) Write-Host "   [注意] $Text" -ForegroundColor Yellow }
function Write-Bad  { param([string]$Text) Write-Host "   [失败] $Text" -ForegroundColor Red }

function Remove-PathRecursive {
  param([string]$Path, [string]$Label)
  if ([string]::IsNullOrWhiteSpace($Label)) { $Label = $Path }
  if (-not (Test-Path -LiteralPath $Path)) { Write-Skip "不存在: $Label"; return }
  if ($DryRun) { Write-Host "   [试运行] 将删除 $Label" -ForegroundColor Magenta; return }
  for ($i = 1; $i -le 3; $i++) {
    try {
      Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
      Write-Ok "已删除 $Label"
      $script:Removed += $Label
      return
    } catch {
      if ($i -lt 3) { Start-Sleep -Seconds 1; continue }
      Write-Bad "$Label -> $($_.Exception.Message)"
      $script:Failed += $Label
    }
  }
}

Write-Host "DSH 彻底卸载脚本" -ForegroundColor White
if ($DryRun) { Write-Host "模式: 试运行（不会做任何改动）" -ForegroundColor Magenta }

if ($env:DSH_SESSION_ID -and -not $Force) {
  Write-Host ""
  Write-Warn2 "检测到 DSH_SESSION_ID，说明你正在 dsh 会话内部运行本脚本。"
  Write-Warn2 "继续执行会结束当前 dsh 会话（这个窗口/网页会断开）。"
  Write-Warn2 "请改到外部 PowerShell 运行；确实要在这里运行请加 -Force。"
  exit 2
}

# ---------------------------------------------------------------- 1. 结束进程
Write-Step "1/6 结束正在运行的 dsh 进程"
$dshProcs = @(Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
  Where-Object {
    $_.CommandLine -and (
      $_.CommandLine -match '@deepseek-ai[\\/]dsh' -or
      $_.CommandLine -match 'dsh[\\/]lib[\\/]bin\.js' -or
      $_.CommandLine -match 'dsh-subprocess-local'
    )
  })

if ($dshProcs.Count -eq 0) {
  Write-Skip "没有发现运行中的 dsh 进程"
} else {
  foreach ($p in $dshProcs) {
    if ($DryRun) { Write-Host "   [试运行] 将结束 PID $($p.ProcessId)" -ForegroundColor Magenta; continue }
    try {
      Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
      Write-Ok "已结束 PID $($p.ProcessId)"
    } catch {
      Write-Warn2 "PID $($p.ProcessId) 结束失败: $($_.Exception.Message)"
    }
  }
  if (-not $DryRun) { Start-Sleep -Seconds 2 }
}

# ------------------------------------------------------------- 2. npm 卸载
Write-Step "2/6 npm 全局卸载 @deepseek-ai/dsh"
$npmCmd = (Get-Command npm.cmd -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $npmCmd) {
  $guess = Join-Path (Split-Path (Get-Command node.exe -ErrorAction SilentlyContinue).Source -Parent) 'npm.cmd'
  if (Test-Path -LiteralPath $guess) { $npmCmd = $guess }
}
if (-not $npmCmd) {
  Write-Warn2 "找不到 npm.cmd，跳过 npm 卸载，直接删除目录"
} elseif ($DryRun) {
  Write-Host "   [试运行] 将执行: npm uninstall -g @deepseek-ai/dsh" -ForegroundColor Magenta
} else {
  & $npmCmd uninstall -g '@deepseek-ai/dsh' 2>&1 | ForEach-Object { Write-Host "   $_" }
}

# --------------------------------------------------------------- 3. 残留清理
Write-Step "3/6 清理残留的包目录与命令垫片"
$npmBinDir  = Join-Path $env:APPDATA 'npm'
$scopeDir   = Join-Path $npmBinDir 'node_modules\@deepseek-ai'
$pkgDir     = Join-Path $scopeDir 'dsh'

Remove-PathRecursive -Path $pkgDir -Label $pkgDir
foreach ($shim in @('dsh', 'dsh.cmd', 'dsh.ps1')) {
  Remove-PathRecursive -Path (Join-Path $npmBinDir $shim) -Label (Join-Path $npmBinDir $shim)
}
if ((Test-Path -LiteralPath $scopeDir) -and -not (Get-ChildItem -LiteralPath $scopeDir -Force -ErrorAction SilentlyContinue)) {
  Remove-PathRecursive -Path $scopeDir -Label $scopeDir
} else {
  Write-Skip "$scopeDir 非空或不存在，保留（里面可能还有别的 @deepseek-ai 包）"
}

# ------------------------------------------------------------------ 4. 数据目录
Write-Step "4/6 删除 DSH 数据目录"
if ($KeepData) {
  Write-Skip "按 -KeepData 要求保留 $env:USERPROFILE\.dsh"
} else {
  Remove-PathRecursive -Path (Join-Path $env:USERPROFILE '.dsh') -Label (Join-Path $env:USERPROFILE '.dsh')
}

if ($KeepHomeDirs) {
  Write-Skip "按 -KeepHomeDirs 要求保留 dshhome / ~\profiles"
} else {
  Remove-PathRecursive -Path (Join-Path $env:USERPROFILE 'dshhome') -Label (Join-Path $env:USERPROFILE 'dshhome')
  $stray = Join-Path $env:USERPROFILE 'profiles'
  if (Test-Path -LiteralPath (Join-Path $stray 'node_modules\@deepseek-ai')) {
    Remove-PathRecursive -Path $stray -Label "$stray (误建的 dsh profiles)"
  } else {
    Write-Skip "$stray 不是 dsh 生成的，保留"
  }
}

# 旧会话被删除后，若还有别的 DSH_HOME（例如项目里 devhome\.dsh），这里只做提示
Write-Skip "项目内的 DSH_HOME（如 D:\ai\gongzuoqu\dsh-android\devhome\.dsh）不会被删除，需要时请手动删"

# ------------------------------------------------------------------ 5. 缓存
Write-Step "5/6 清理临时文件与缓存"
$tempItems = @(Get-ChildItem -LiteralPath $env:TEMP -Force -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like 'dsh-*' })
if ($tempItems.Count -eq 0) {
  Write-Skip "没有 %TEMP%\dsh-* 临时文件"
} else {
  foreach ($item in $tempItems) { Remove-PathRecursive -Path $item.FullName -Label $item.FullName }
}

if ($CleanCache) {
  if (-not $npmCmd) { Write-Warn2 "找不到 npm.cmd，跳过 npm 缓存清理" }
  elseif ($DryRun) { Write-Host "   [试运行] 将执行: npm cache clean --force" -ForegroundColor Magenta }
  else {
    & $npmCmd cache clean --force 2>&1 | ForEach-Object { Write-Host "   $_" }
  }
  $pnpmCmd = (Get-Command pnpm.cmd -ErrorAction SilentlyContinue | Select-Object -First 1).Source
  if (-not $pnpmCmd) { Write-Skip "未安装 pnpm，跳过 pnpm store prune" }
  elseif ($DryRun) { Write-Host "   [试运行] 将执行: pnpm store prune" -ForegroundColor Magenta }
  else {
    & $pnpmCmd store prune 2>&1 | ForEach-Object { Write-Host "   $_" }
  }
} else {
  Write-Skip "如需连缓存一起清掉，请加 -CleanCache（npm cache clean --force + pnpm store prune）"
}

# ------------------------------------------------------------------ 6. 校验
Write-Step "6/6 校验结果"
if ($DryRun) {
  Write-Host "   试运行结束，未做任何改动。" -ForegroundColor Magenta
  exit 0
}

$leftCmd = @(Get-Command dsh -All -ErrorAction SilentlyContinue)
if ($leftCmd.Count -eq 0) { Write-Ok "命令 dsh 已不存在" } else { Write-Warn2 "命令 dsh 仍可被找到: $($leftCmd[0].Source)" }

foreach ($path in @((Join-Path $npmBinDir 'node_modules\@deepseek-ai\dsh'), (Join-Path $env:USERPROFILE '.dsh'), (Join-Path $env:USERPROFILE 'dshhome'))) {
  if (Test-Path -LiteralPath $path) { Write-Warn2 "仍存在: $path" } else { Write-Ok "已清除: $path" }
}

$leftProcs = @(Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -and $_.CommandLine -match '@deepseek-ai[\\/]dsh' })
if ($leftProcs.Count -eq 0) { Write-Ok "没有残留的 dsh 进程" } else { Write-Warn2 "仍有 $($leftProcs.Count) 个 dsh 进程，可重开一个 PowerShell 再跑一次本脚本" }

Write-Host ""
if ($script:Failed.Count -eq 0) {
  Write-Host "卸载完成：DSH 已从本机移除。" -ForegroundColor Green
  Write-Host "如果 PATH 里还留着命令，请打开一个新的终端窗口（PATH 缓存）后确认。" -ForegroundColor Green
  exit 0
} else {
  Write-Host "部分内容删除失败（多数是文件被占用）：" -ForegroundColor Yellow
  $script:Failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
  Write-Host "请关闭所有终端/编辑器，然后重新运行本脚本。" -ForegroundColor Yellow
  exit 1
}
