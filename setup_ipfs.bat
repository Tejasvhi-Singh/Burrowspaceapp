@echo off
echo BurrowSpace IPFS Setup
echo ======================
echo.

echo This script will help you set up IPFS for BurrowSpace on Windows.
echo.

REM Check if IPFS is already installed
where ipfs >nul 2>&1
if %ERRORLEVEL% == 0 (
    echo IPFS is already installed.
    for /f "tokens=3" %%i in ('ipfs --version') do set IPFS_VERSION=%%i
    echo Current version: %IPFS_VERSION%
) else (
    echo IPFS is not installed.
    echo Please download and install IPFS Desktop from:
    echo https://docs.ipfs.tech/install/ipfs-desktop/
    echo.
    echo After installation, please run this script again.
    pause
    exit /b 1
)

REM Check if IPFS is initialized
if not exist "%USERPROFILE%\.ipfs" (
    echo Initializing IPFS...
    ipfs init
) else (
    echo IPFS is already initialized.
)

REM Configure IPFS for BurrowSpace
echo Configuring IPFS for BurrowSpace...

REM Enable CORS
ipfs config --json API.HTTPHeaders.Access-Control-Allow-Origin "[\"*\"]"
ipfs config --json API.HTTPHeaders.Access-Control-Allow-Methods "[\"PUT\", \"POST\", \"GET\"]"

REM Configure Gateway
ipfs config --json Gateway.HTTPHeaders.Access-Control-Allow-Origin "[\"*\"]"
ipfs config --json Gateway.HTTPHeaders.Access-Control-Allow-Methods "[\"PUT\", \"POST\", \"GET\"]"

echo.
echo IPFS setup complete! Your node is ready for use with BurrowSpace.
echo API address: http://localhost:5001/api/v0
echo Gateway address: http://localhost:8080/ipfs/
echo.
echo Please configure these addresses in the BurrowSpace app settings.
echo.
echo To start the IPFS daemon, run: ipfs daemon
echo It's recommended to use IPFS Desktop for easier management.
echo.

pause 