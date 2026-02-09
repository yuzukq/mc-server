@echo off
chcp 65001 > nul
setlocal enabledelayedexpansion
REM MCサーバー起動スクリプト
REM サーバーを起動し、ワールドデータを自動同期します
REM 使い方: start-server.bat [環境名]
REM   例: start-server.bat dev  → .env.dev を使用


echo ========================================
echo     R2同期 -> Minecraftサーバー起動
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

REM .envファイルの存在確認
if not exist !ENV_FILE! (
    echo [エラー] !ENV_FILE!ファイルが見つかりません！
    echo .env.exampleを!ENV_FILE!にコピーして、R2の認証情報を設定してください。
    echo.
    pause
    exit /b 1
)

REM カスタムRubyイメージのビルドが必要か確認
docker compose --env-file !ENV_FILE! images sync-init -q >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [情報] 初回起動を検出しました。カスタムRubyイメージをビルド中...
    echo.
    docker compose --env-file !ENV_FILE! build
    if %ERRORLEVEL% NEQ 0 (
        echo [エラー] イメージのビルドに失敗しました
        pause
        exit /b 1
    )
    echo.
)

echo サーバーを起動中...
echo.

docker compose --env-file !ENV_FILE! up -d

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
