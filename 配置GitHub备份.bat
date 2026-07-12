@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
set "GH=%ROOT%.tools\github-cli\bin\gh.exe"

if not exist "%GH%" (
  echo GitHub CLI is missing: %GH%
  pause
  exit /b 1
)

"%GH%" auth status >nul 2>nul
if errorlevel 1 (
  "%GH%" auth login --hostname github.com --git-protocol https --web
  if errorlevel 1 (
    echo GitHub login failed.
    pause
    exit /b 1
  )
)

set /p "REMOTE=Private repository HTTPS URL: "
if "%REMOTE%"=="" (
  echo Repository URL is required.
  pause
  exit /b 1
)

git -C "%ROOT%" remote get-url origin >nul 2>nul
if errorlevel 1 (
  git -C "%ROOT%" remote add origin "%REMOTE%"
) else (
  git -C "%ROOT%" remote set-url origin "%REMOTE%"
)

for /f "delims=" %%U in ('"%GH%" api user --jq .login') do set "GH_USER=%%U"
if not "%GH_USER%"=="" git -C "%ROOT%" config user.name "%GH_USER%"
if not "%GH_USER%"=="" git -C "%ROOT%" config user.email "%GH_USER%@users.noreply.github.com"

git -C "%ROOT%" branch -M main
call "%ROOT%备份代码到GitHub.bat"
