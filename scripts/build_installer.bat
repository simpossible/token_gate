@echo off
REM ============================================================
REM Token Gate Windows Installer Build Script
REM
REM Prerequisites:
REM   1. Go (golang.org/dl)
REM   2. Flutter (C:\flutter)
REM   3. Inno Setup (winget install JRSoftware.InnoSetup)
REM
REM Usage:
REM   .\scripts\build_installer.bat [version]
REM
REM   version  - optional, e.g. "2.0.0". Defaults to 2.0.0
REM
REM Output:
REM   build\TokenGate-{version}-setup.exe
REM ============================================================

setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."
set "APP_DIR=%PROJECT_ROOT%\app"
set "SERVER_DIR=%PROJECT_ROOT%\server"
set "BUILD_DIR=%PROJECT_ROOT%\build"
set "ISS_SCRIPT=%SCRIPT_DIR%installer.iss"

REM Flutter and Inno Setup paths
set "FLUTTER=C:\flutter\bin\flutter.bat"
set "ISCC=C:\Users\Administrator\AppData\Local\Programs\Inno Setup 6\ISCC.exe"

REM Flutter mirror for China
set "FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn"
set "PUB_HOSTED_URL=https://pub.flutter-io.cn"

REM Get version from argument or use default
if "%~1"=="" (
    set "VERSION=2.0.0"
    echo [INFO] No version specified, using default: 2.0.0
) else (
    set "VERSION=%~1"
)
echo [INFO] Building TokenGate v%VERSION% for Windows

REM Create build directory
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

REM ============================================================
REM Step 1: Check prerequisites
REM ============================================================
echo.
echo [INFO] Checking prerequisites...

where go >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Go not found in PATH
    exit /b 1
)

if not exist "%FLUTTER%" (
    echo [ERROR] Flutter not found at %FLUTTER%
    exit /b 1
)

if not exist "%ISCC%" (
    echo [ERROR] Inno Setup not found at %ISCC%
    echo   Install via: winget install JRSoftware.InnoSetup
    exit /b 1
)

echo [INFO] Prerequisites OK

REM ============================================================
REM Step 2: Build Go binary
REM ============================================================
echo.
echo [INFO] Building Go binary...
cd /d "%SERVER_DIR%"
set GOOS=windows
set GOARCH=amd64
go build -o token_gate_windows_amd64.exe .
if errorlevel 1 (
    echo [ERROR] Go build failed
    exit /b 1
)

echo [INFO] Copying Go binary to Flutter assets...
if not exist "%APP_DIR%\assets\bin" mkdir "%APP_DIR%\assets\bin"
copy /Y token_gate_windows_amd64.exe "%APP_DIR%\assets\bin\token_gate.exe" >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy Go binary
    exit /b 1
)

echo [INFO] Go binary built

REM ============================================================
REM Step 3: Build Flutter Windows app
REM ============================================================
echo.
echo [INFO] Building Flutter Windows app (Release)...
cd /d "%APP_DIR%"
call "%FLUTTER%" build windows --release
if errorlevel 1 (
    echo [ERROR] Flutter build failed
    exit /b 1
)

echo [INFO] Flutter build complete

REM ============================================================
REM Step 4: Build installer with Inno Setup
REM ============================================================
echo.
echo [INFO] Building installer with Inno Setup...

REM Delete old installer if exists
if exist "%BUILD_DIR%\TokenGate-%VERSION%-setup.exe" del "%BUILD_DIR%\TokenGate-%VERSION%-setup.exe"

cd /d "%SCRIPT_DIR%"
"%ISCC%" /O"%BUILD_DIR%" /F"TokenGate-%VERSION%-setup" /DTOKEN_GATE_VERSION="%VERSION%" "%ISS_SCRIPT%"
if errorlevel 1 (
    echo [ERROR] Inno Setup compilation failed
    exit /b 1
)

REM ============================================================
REM Step 5: Output summary
REM ============================================================
echo.
echo [INFO] =========================================
echo [INFO]   Build complete!
echo [INFO] =========================================
echo [INFO]   Installer: %BUILD_DIR%\TokenGate-%VERSION%-setup.exe
echo [INFO]   Version: %VERSION%
echo [INFO] =========================================

cd /d "%PROJECT_ROOT%"
endlocal
