@echo off
setlocal
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-WeComFork.ps1" -RefreshNativeCore %*
set "exit_code=%errorlevel%"
echo.
pause
exit /b %exit_code%
