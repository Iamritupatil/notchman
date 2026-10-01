@echo off
REM Builds the Notchman installer on this PC and starts it.
REM Double-click this file. It takes a few minutes the first time.
cd /d "%~dp0"
title Building Notchman

where node >nul 2>nul
if errorlevel 1 (
  echo Node.js is not installed. Get it from https://nodejs.org ^(LTS^), then double-click this file again.
  pause
  exit /b 1
)

echo [1/2] Getting what Notchman needs...
call npm install --no-audit --no-fund
if errorlevel 1 goto failed

echo [2/2] Building the installer...
call npm run dist
if errorlevel 1 goto failed

for %%f in (dist\Notchman-Setup-*.exe) do set INSTALLER=%%f
if not defined INSTALLER goto failed

echo.
echo Done: %INSTALLER%
echo Starting the installer...
start "" "%INSTALLER%"
explorer /select,"%INSTALLER%"
exit /b 0

:failed
echo.
echo The build didn't finish. Copy the messages above and send them to Claude.
pause
exit /b 1
