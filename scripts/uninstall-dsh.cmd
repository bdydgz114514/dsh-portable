@echo off
rem Completely uninstall DSH. Preview first with:  uninstall-dsh.cmd -DryRun
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall-dsh.ps1" %*
echo.
pause
