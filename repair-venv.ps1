#Requires -Version 5.1
<#
.SYNOPSIS
  重建 dsh-video-understand 的 Python 虚拟环境（.venv）。
.DESCRIPTION
  当 .venv 因为换机器 / 换用户名 / 路径变动而失效时使用。
  优先用包内自带的 uv.exe，其次用 PATH 里的 uv，最后回退 python -m venv + pip。
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\repair-venv.ps1
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\repair-venv.ps1 -DryRun
#>
[CmdletBinding()]
param([switch]$DryRun)

$ErrorActionPreference = 'Continue'
$Pkg    = $PSScriptRoot
$Venv   = Join-Path $env:USERPROFILE '.dsh\profiles\web\node_modules\dsh-video-understand\.venv'
$Plugin = Split-Path -Parent $Venv
$Req    = Join-Path $Plugin 'engine\requirements.txt'
$Mirror = 'https://pypi.tuna.tsinghua.edu.cn/simple'

Write-Host ''
Write-Host '== 重建 video-understand 的 Python 环境' -ForegroundColor Cyan
Write-Host ('插件目录 : ' + $Plugin)
Write-Host ('虚拟环境 : ' + $Venv)
Write-Host ('依赖清单 : ' + $Req)

if (-not (Test-Path -LiteralPath $Req)) {
  Write-Host '找不到 engine\requirements.txt，无法重建。' -ForegroundColor Red
  exit 1
}

$uvExe = Join-Path $Pkg 'uv\uv.exe'
if (-not (Test-Path -LiteralPath $uvExe)) {
  $c = Get-Command uv.exe -ErrorAction SilentlyContinue
  if ($c) { $uvExe = $c.Source } else { $uvExe = $null }
}

if ($DryRun) {
  Write-Host '[试运行] 将删除并重建 .venv，然后安装 engine\requirements.txt' -ForegroundColor Magenta
  exit 0
}

if (Test-Path -LiteralPath $Venv) {
  Write-Host '删除旧的 .venv ...' -ForegroundColor Yellow
  Remove-Item -LiteralPath $Venv -Recurse -Force -ErrorAction SilentlyContinue
}

if ($uvExe) {
  Write-Host ('使用 uv: ' + $uvExe)
  & $uvExe venv $Venv
  if ($LASTEXITCODE -ne 0) {
    Write-Host 'uv venv 失败，回退到 python -m venv' -ForegroundColor Yellow
    $uvExe = $null
  }
} else {
  Write-Host '未找到 uv，使用系统 python -m venv' -ForegroundColor Yellow
}

$py = Join-Path $Venv 'Scripts\python.exe'
if (-not (Test-Path -LiteralPath $py)) {
  $base = (Get-Command python.exe -ErrorAction SilentlyContinue).Source
  if (-not $base) {
    Write-Host '系统里也没有 python，请先安装 Python 3.12/3.13 或 uv。' -ForegroundColor Red
    exit 1
  }
  & $base -m venv $Venv
}

if (-not (Test-Path -LiteralPath $py)) {
  Write-Host '虚拟环境创建失败。' -ForegroundColor Red
  exit 1
}

Write-Host '安装依赖（可能需要几分钟）...' -ForegroundColor Yellow
& $py -m pip install --upgrade pip --index-url $Mirror
& $py -m pip install -r $Req --index-url $Mirror
if ($LASTEXITCODE -ne 0) {
  Write-Host '清华镜像失败，回退官方源 ...' -ForegroundColor Yellow
  & $py -m pip install -r $Req
}

Write-Host ''
Write-Host '验证核心依赖 ...' -ForegroundColor Cyan
& $py -c "import torch, cv2, numpy, ctranslate2; print('OK', torch.__version__)"
Write-Host '完成。' -ForegroundColor Green
