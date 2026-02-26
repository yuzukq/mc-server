@echo off
chcp 65001 > nul
setlocal enabledelayedexpansion
REM MCサーバー停止スクリプト
REM サーバーを停止し、ワールドデータを自動同期します
REM 使い方: stop-server.bat [環境名]
REM   例: stop-server.bat dev  → .env.dev を使用

echo ========================================
echo     Minecraftサーバー停止 -> R2同期
echo ========================================
echo.

cd /d "%~dp0"

REM 環境引数の処理
set "ENV_FILE=.env"
if not "%~1"=="" (
    set "ENV_FILE=.env.%~1"
    echo [%~1モード] !ENV_FILE! を使用します
    echo.
)

REM 本番環境ガード: 引数なし(本番)の場合に明示的な確認を要求
if "%~1"=="" (
    echo ========================================
    echo [警告] 本番環境で操作します
    echo 本番R2バケットにアクセスします。
    echo ========================================
    echo.
    set "CONFIRM="
    set /p CONFIRM="続行するには yes と入力してください (それ以外でキャンセル): "
    if /i not "!CONFIRM!"=="yes" (
        echo.
        echo キャンセルしました。開発環境を使用する場合: stop-server.bat dev
        echo.
        pause
        exit /b 1
    )
    echo.
)

echo サーバーを停止中...
docker compose --env-file !ENV_FILE! down

echo.
echo ワールドデータをR2にアップロードしてロックを解放中...
docker compose --env-file !ENV_FILE! run --rm sync-shutdown

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo サーバーが正常に停止しました！
    echo ワールドデータをR2にアップロードしました
    echo ========================================
    echo.
) else (
    echo.
    echo [エラー] データの同期に失敗しました
    echo 上記のエラーメッセージを確認してください
    echo.
)

pause
