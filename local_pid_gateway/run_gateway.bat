@echo off
setlocal EnableExtensions

set "GATEWAY_DIR=%~dp0"
set "ROOT=%GATEWAY_DIR%..\"
set "SERVER=%GATEWAY_DIR%server_ai.py"

cd /d "%ROOT%"

echo ========================================
echo  PID Local Gateway
echo ========================================
echo Root  : %ROOT%
echo Server: %SERVER%
echo URL   : http://127.0.0.1:8788
echo.

where python >nul 2>nul
if %errorlevel%==0 (
  python "%SERVER%"
  goto finished
)

where py >nul 2>nul
if %errorlevel%==0 (
  py -3 "%SERVER%"
  goto finished
)

echo [ERROR] Python was not found. Install Python or add it to PATH.

:finished
echo.
echo [INFO] Gateway process exited. If there is an error above, send it to Codex.
pause