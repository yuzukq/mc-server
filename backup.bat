@echo off
chcp 65001 > nul
REM MCサーバー手動バックアップスクリプト
REM ワールドデータを即時バックアップします

echo ========================================
echo     Minecraft ワールドバックアップ
echo ========================================
echo.

cd /d %~dp0

echo バックアップを実行中...
docker compose run --rm backup

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo バックアップが正常に完了しました！
    echo ========================================
    echo.
) else (
    echo.
    echo [エラー] バックアップに失敗しました
    echo 上記のエラーメッセージを確認してください
    echo.
)

pause
