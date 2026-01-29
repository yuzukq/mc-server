@echo off
REM Minecraft Server Startup Script with R2 Sync
REM This script starts the Minecraft server with automatic world sync

echo ========================================
echo Minecraft Server Startup (with R2 Sync)
echo ========================================
echo.

cd /d "%~dp0"

REM Check if .env file exists
if not exist .env (
    echo [ERROR] .env file not found!
    echo Please copy .env.example to .env and configure your R2 credentials.
    echo.
    pause
    exit /b 1
)

echo Starting server...
echo.

docker compose up -d

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo Server started successfully!
    echo ========================================
    echo.
    echo To view logs: docker logs -f mc_server
    echo To stop server: run stop-server.bat
    echo.
) else (
    echo.
    echo [ERROR] Failed to start server
    echo Check the error messages above
    echo.
)

pause
