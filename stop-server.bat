@echo off
chcp 65001 > nul
REM MCサーバー停止スクリプト
REM バックアップスケジューラを削除し、サーバーを停止してワールドデータを同期します

echo ========================================
echo     Minecraftサーバー停止 -> R2同期
echo ========================================
echo.

cd /d "%~dp0"

echo バックアップスケジューラを削除中...
schtasks /delete /tn "MinecraftBackup" /f >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo バックアップスケジューラを削除しました。
) else (
    echo [情報] バックアップスケジューラは登録されていませんでした。
)
echo.

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
