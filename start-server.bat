@echo off
REM MCサーバー起動スクリプト
REM サーバーを起動し、ワールドデータを自動同期します


echo ========================================
echo Minecraftサーバー起動 (R2同期)
echo ========================================
echo.

cd /d "%~dp0"

REM .envファイルの存在確認
if not exist .env (
    echo [エラー] .envファイルが見つかりません！
    echo .env.exampleを.envにコピーして、R2の認証情報を設定してください。
    echo.
    pause
    exit /b 1
)

REM カスタムRubyイメージのビルドが必要か確認
docker compose images sync-init -q >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [情報] 初回起動を検出しました。カスタムRubyイメージをビルド中...
    echo.
    docker compose build
    if %ERRORLEVEL% NEQ 0 (
        echo [エラー] イメージのビルドに失敗しました
        pause
        exit /b 1
    )
    echo.
)

echo サーバーを起動中...
echo.

docker compose up -d

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo サーバーが正常に起動しました！
    echo ========================================
    echo.
    echo ログを確認: docker logs -f mc_server
    echo サーバー停止: stop-server.bat を実行
    echo.
) else (
    echo.
    echo [エラー] サーバーの起動に失敗しました
    echo 上記のエラーメッセージを確認してください
    echo.
)

pause
