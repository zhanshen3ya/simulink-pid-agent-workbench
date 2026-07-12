@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
set "URL=http://127.0.0.1:8788"
set "SERVER=%ROOT%local_pid_gateway\server_ai.py"
set "RUNNER=%ROOT%local_pid_gateway\run_gateway.bat"
set "LOG=%ROOT%local_pid_gateway\gateway_launcher.log"

cd /d "%ROOT%"

echo ========================================
echo  PID Simulink Tuning Console
echo ========================================
echo Root: %ROOT%
echo URL : %URL%
echo Log : %LOG%
echo.

echo [%date% %time%] launcher started > "%LOG%"

if not exist "%SERVER%" (
  echo [ERROR] Missing server_ai.py:
  echo %SERVER%
  echo [%date% %time%] missing server.py >> "%LOG%"
  pause
  exit /b 1
)

if not exist "%RUNNER%" (
  echo [ERROR] Missing run_gateway.bat:
  echo %RUNNER%
  echo [%date% %time%] missing run_gateway.bat >> "%LOG%"
  pause
  exit /b 1
)

call :check_health
if %errorlevel%==0 (
  echo [OK] Gateway is already running. Opening browser...
  echo [%date% %time%] gateway already running >> "%LOG%"
  start "" "%URL%"
  exit /b 0
)

echo [START] Starting local gateway...
echo [%date% %time%] starting gateway >> "%LOG%"
start "PID Local Gateway" /min "%RUNNER%"

echo [WAIT] Waiting for gateway...
for /l %%i in (1,1,25) do (
  call :check_health
  if not errorlevel 1 goto ready
  timeout /t 1 /nobreak >nul
)

echo [ERROR] Gateway did not start in 25 seconds.
echo Check this log:
echo %LOG%
echo Also check the PID Local Gateway window.
echo [%date% %time%] gateway start timeout >> "%LOG%"
pause
exit /b 1

:ready
echo [OK] Gateway is ready. Opening browser...
echo [%date% %time%] gateway ready >> "%LOG%"
start "" "%URL%"
exit /b 0

:check_health
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $r = Invoke-WebRequest -Uri '%URL%/api/health' -UseBasicParsing -TimeoutSec 2; if ($r.StatusCode -eq 200) { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>nul
exit /b %errorlevel%