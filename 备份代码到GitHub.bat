@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%local_pid_gateway\git_code_backup.ps1" -JobId manual -Root "%ROOT%"
if errorlevel 1 (
  echo.
  echo Backup was not completed. Check:
  echo %ROOT%local_pid_gateway\git_backup.log
  pause
  exit /b 1
)
echo Code backup completed.
pause
