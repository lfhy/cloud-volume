@echo off
REM Double-click launcher for the user-scoped Android development environment.
setlocal
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_android_dev.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"
if not "%CLOUD_VOLUME_NO_PAUSE%"=="1" pause
exit /b %EXIT_CODE%
