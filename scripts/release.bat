@echo off
REM ============================================================
REM Token Gate Windows Release Script
REM
REM Prerequisites:
REM   - TOKEN_GATE_GITHUB_TOKEN env var set
REM   - SSH key added to GitHub (for git push)
REM   - Run from the project root directory
REM
REM Usage:
REM   .\scripts\release.bat v2.0.0
REM
REM What this script does:
REM   1. Builds installer locally (Go + Flutter + Inno Setup)
REM   2. Tags the commit and pushes to GitHub
REM   3. Creates a GitHub Release via API and uploads the installer
REM ============================================================

setlocal EnableDelayedExpansion

if "%~1"=="" (
    echo [ERROR] Usage: %~nx0 ^<version^>  e.g. %~nx0 v2.0.0
    exit /b 1
)

set "VERSION=%~1"

REM Validate version format
echo %VERSION% | findstr /r "^v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul
if errorlevel 1 (
    echo [ERROR] Version must be in format vX.Y.Z (e.g. v2.0.0)
    exit /b 1
)

set "VERSION_NUM=%VERSION:~1%"
set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."
set "INSTALLER_NAME=TokenGate-%VERSION_NUM%-setup.exe"
set "INSTALLER_PATH=%PROJECT_ROOT%\build\%INSTALLER_NAME%"
set "REPO_API=https://api.github.com/repos/simpossible/token_gate"
set "UPLOAD_API=https://uploads.github.com/repos/simpossible/token_gate"

REM Check GitHub token
if "%TOKEN_GATE_GITHUB_TOKEN%"=="" (
    echo [ERROR] TOKEN_GATE_GITHUB_TOKEN not set.
    echo   set TOKEN_GATE_GITHUB_TOKEN=ghp_xxxx
    exit /b 1
)

echo [INFO] Releasing %VERSION%

REM ============================================================
REM Step 1: Build installer locally
REM ============================================================
echo.
echo [INFO] Building installer...
call "%SCRIPT_DIR%build_installer.bat" %VERSION_NUM%
if errorlevel 1 (
    echo [ERROR] Installer build failed
    exit /b 1
)

if not exist "%INSTALLER_PATH%" (
    echo [ERROR] Installer not found at %INSTALLER_PATH%
    exit /b 1
)

REM Calculate SHA256
echo [INFO] Calculating SHA256...
for /f "skip=1 tokens=*" %%i in ('certutil -hashfile "%INSTALLER_PATH%" SHA256') do (
    if not defined INSTALLER_SHA256 set "INSTALLER_SHA256=%%i"
)
set "INSTALLER_SHA256=!INSTALLER_SHA256: =!"
echo [INFO] SHA256: !INSTALLER_SHA256!

REM ============================================================
REM Step 2: Tag and push
REM ============================================================
echo.
echo [INFO] Tagging %VERSION% and pushing...
cd /d "%PROJECT_ROOT%"
git tag %VERSION%
if errorlevel 1 (
    echo [WARN] Tag may already exist, continuing...
)

git push origin %VERSION%
if errorlevel 1 (
    echo [ERROR] Failed to push tag
    exit /b 1
)

git push origin master
if errorlevel 1 (
    echo [ERROR] Failed to push master
    exit /b 1
)

REM ============================================================
REM Step 3: Create GitHub Release and upload installer
REM ============================================================
echo.
echo [INFO] Creating GitHub Release...

set "RELEASE_BODY=Token Gate %VERSION%\n\nWindows: Download TokenGate-%VERSION_NUM%-setup.exe and run to install."

REM Use PowerShell for reliable JSON handling
for /f "usebackq tokens=*" %%i in (`powershell.exe -Command "$headers = @{ 'Authorization' = 'token %TOKEN_GATE_GITHUB_TOKEN%'; 'Content-Type' = 'application/json' }; $body = @{ tag_name = '%VERSION%'; name = '%VERSION%'; body = 'Token Gate %VERSION% - Windows installer'; draft = $false; prerelease = $false } | ConvertTo-Json; $r = Invoke-RestMethod -Uri '%REPO_API%/releases' -Method Post -Headers $headers -Body $body; $r.id"`) do (
    set "RELEASE_ID=%%i"
)

if "!RELEASE_ID!"=="" (
    echo [ERROR] Failed to create release
    exit /b 1
)

echo [INFO] Release created (ID: !RELEASE_ID!)

echo [INFO] Uploading installer...
powershell.exe -Command "$headers = @{ 'Authorization' = 'token %TOKEN_GATE_GITHUB_TOKEN%'; 'Content-Type' = 'application/octet-stream' }; Invoke-RestMethod -Uri '%UPLOAD_API%/releases/!RELEASE_ID!/assets?name=%INSTALLER_NAME%' -Method Post -Headers $headers -InFile '%INSTALLER_PATH%'" >nul
if errorlevel 1 (
    echo [ERROR] Failed to upload installer
    exit /b 1
)

echo [INFO] Installer uploaded

REM ============================================================
REM Done
REM ============================================================
echo.
echo [INFO] =========================================
echo [INFO]   Done! %VERSION% released.
echo [INFO] =========================================
echo [INFO]   Download: https://github.com/simpossible/token_gate/releases/download/%VERSION%/%INSTALLER_NAME%
echo [INFO]   SHA256: !INSTALLER_SHA256!
echo [INFO] =========================================

endlocal
