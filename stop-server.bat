@echo off
chcp 65001 > nul
REM MCサーバー停止スクリプト
REM サーバーを停止し、ワールドデータを自動同期します

echo ========================================
echo     Minecraftサーバー停止 -> R2同期
echo ========================================
echo.

cd /d "%~dp0"

echo サーバーを停止中...
docker compose down

echo.
echo ワールドデータをR2にアップロードしてロックを解放中...
docker compose run --rm sync-shutdown

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
