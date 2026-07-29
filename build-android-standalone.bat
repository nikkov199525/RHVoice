@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-android-standalone.ps1" %*
exit /b %ERRORLEVEL%
