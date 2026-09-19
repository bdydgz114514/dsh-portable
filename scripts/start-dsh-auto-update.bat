@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
title dsh web launcher (auto update + plugin check)
cd /d "%~dp0"

rem ======================== 配置 ========================
rem UPDATE_MODE 可选值：auto=latest/alpha/next 中最�?| latest | alpha | next | off
set "UPDATE_MODE=auto"
rem DRYRUN=1 只打印结果，不更新不启动
set "DRYRUN=0"
rem SKIP_PORTCHECK=1 跳过 3080 占用检�?
set "SKIP_PORTCHECK=0"
rem NO_PAUSE=1 结束后不暂停
set "NO_PAUSE=0"
rem 启动参数（默�?web�?
set "DSH_ARGS=web"
rem 需要核对版本对应的插件（空格分隔，含作用域包名�?
set "DSH_PLUGINS=dshmarket dsh-better-sidebar dsh-context @linxin666/dsh-web-all"
rem 插件缺失或版本不对应时自动尝试安�?升级最新版�? 关闭�?
set "PLUGIN_AUTOFIX=1"
rem profile �?
set "DSH_PROFILE=web"
rem 本脚本配套的检�?更新脚本
set "HELPER=%~dp0dsh-start-helper.mjs"
rem ======================================================
rem 同名环境变量可覆盖默认�?
if defined DSH_UPDATE_MODE set "UPDATE_MODE=%DSH_UPDATE_MODE%"
if defined DSH_DRYRUN set "DRYRUN=%DSH_DRYRUN%"
if defined DSH_SKIP_PORTCHECK set "SKIP_PORTCHECK=%DSH_SKIP_PORTCHECK%"
if defined DSH_NO_PAUSE set "NO_PAUSE=%DSH_NO_PAUSE%"

rem ===== video-understand plugin runtime env =====
rem PYTHONIOENCODING/PYTHONUTF8: engine prints emoji to stdout; CN Windows console is GBK,
rem without utf-8 the pipeline dies with UnicodeEncodeError (observed AVIS_FAILED).
set "PYTHONIOENCODING=utf-8"
set "PYTHONUTF8=1"
rem ===== video-understand: ASR model + HF mirror =====
rem ASR_MODEL: tiny is poor for Chinese speech; small balances accuracy vs speed
set "ASR_MODEL=small"
rem VIDEO_QUALITY: download ceiling 360/480/720/1080 (720+ usually needs cookies)
set "VIDEO_QUALITY=720"
rem VIDEO_COOKIES=1 enables --cookies-from-browser (needed for premium/high quality)
set "VIDEO_COOKIES=0"
rem VIDEO_PREFLIGHT=1 probes the format table before downloading (fails fast)
set "VIDEO_PREFLIGHT=1"
rem HF_ENDPOINT: CN mirror for first-time whisper model download (offline after cache)
set "HF_ENDPOINT=https://hf-mirror.com"
rem VIDEO-UNDERSTAND-ASR
rem VLM_MODEL: multimodal model id used by L1/L2 frame analysis (default hardcoded deepseek-chat)
set "VLM_MODEL=deepseek-flash"

where node >nul 2>nul
if errorlevel 1 goto :nonode
if not exist "%HELPER%" (
    echo [dsh] 缺少配套脚本 %HELPER%
    echo [dsh] 请把 dsh-start-helper.mjs 与本 bat 放在同一目录�?
    if not "%NO_PAUSE%"=="1" pause
    exit /b 1
)

if "%DRYRUN%"=="1" goto :skip_port
if "%SKIP_PORTCHECK%"=="1" goto :skip_port
netstat -ano 2>nul | findstr ":3080" | findstr "LISTENING" >nul
if errorlevel 1 goto :skip_port
echo.
echo [dsh] port 3080 is already in use - reusing the running instance instead of starting a second one.
rem Old behaviour just said "close it" and exited, which looked exactly like "DSH failed to start".
rem Now we verify it really answers as DSH and open it; DSH_FORCE_RESTART=1 kills and restarts.
set "DSH_ALIVE=0"
for /f "delims=" %%L in ('powershell -NoProfile -Command "try{(Invoke-WebRequest -Uri http://127.0.0.1:3080/ -UseBasicParsing -TimeoutSec 5).StatusCode}catch{if($_.Exception.Response){[int]$_.Exception.Response.StatusCode}else{0}}"') do set "DSH_ALIVE=%%L"
if not "%DSH_ALIVE%"=="0" goto :reuse_instance
echo [dsh] port 3080 is in use but does not answer as DSH.
echo [dsh] close whatever owns the port, or start with DSH_PORT=3099 to use another port.
if not "%NO_PAUSE%"=="1" pause
exit /b 1
:reuse_instance
echo [dsh] DSH is already serving http://127.0.0.1:3080/ - opening it in your browser.
echo [dsh] to restart instead: set DSH_FORCE_RESTART=1, or close the old window first.
if "%DSH_FORCE_RESTART%"=="1" goto :force_restart
start "" http://127.0.0.1:3080/
if not "%NO_PAUSE%"=="1" pause
exit /b 0
:force_restart
echo [dsh] DSH_FORCE_RESTART=1 - killing the existing dsh web process ...
for /f "tokens=5" %%P in ('netstat -ano ^| findstr ":3080" ^| findstr "LISTENING"') do taskkill /PID %%P /F >nul 2>nul
timeout /t 2 /nobreak >nul
:skip_port

set "DSH_UPDATE_MODE=%UPDATE_MODE%"
set "DSH_DRYRUN=%DRYRUN%"
set "DSH_PLUGIN_AUTOFIX=%PLUGIN_AUTOFIX%"
echo [dsh] 检�?dsh 更新与插件版本对�?...
node "%HELPER%"
if errorlevel 1 (
    echo.
    echo [dsh] 更新/检查脚本异常，仍将直接启动�?
)
if "%DRYRUN%"=="1" (
    echo.
    echo [dsh] DRYRUN=1：本次仅检查，未更新、未启动�?
    if not "%NO_PAUSE%"=="1" pause
    exit /b 0
)
:run
echo.
echo [dsh] 正在启动: dsh %DSH_ARGS% ...
rem ===== preflight + boot gate (never blocks startup) =====
if exist "%USERPROFILE%\.dsh\boot-check.mjs" (
    echo [dsh] preflight: checking plugins before boot ...
    node "%USERPROFILE%\.dsh\boot-check.mjs" --port 3080
    set "RC=%ERRORLEVEL%"
    if "%RC%"=="10" echo [dsh] port 3080 is already in use - another DSH instance is probably running.
    if "%RC%"=="20" echo [dsh] preflight reported a fatal problem; started in degraded mode for triage.
    echo [dsh] dsh exited, code %RC%
    if not "%NO_PAUSE%"=="1" pause
    exit /b %RC%
)
rem ===== fallback: boot-check.mjs missing, launch directly =====
call dsh %DSH_ARGS% %*
set "RC=%ERRORLEVEL%"
echo.
echo [dsh] dsh 已退出，退出码 %RC%
if not "%NO_PAUSE%"=="1" pause
exit /b %RC%

:nonode
echo [dsh] 未找�?node.exe，请先安�?Node.js�?
if not "%NO_PAUSE%"=="1" pause
exit /b 1
