@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start-offline.ps1" %*
if errorlevel 1 (
  echo Nepodarilo sa spustit lokalnu AI.
  pause
  exit /b 1
)
exit /b 0
