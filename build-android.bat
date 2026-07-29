@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-android.ps1" %*
exit /b %ERRORLEVEL%
