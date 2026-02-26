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
        echo キャンセルしました。開発環境を使用する場合: start-server.bat dev
        echo.
        pause
        exit /b 1
    )
    echo.
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

echo 同期を初期化中...
echo.

docker compose --env-file !ENV_FILE! up sync-init

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [エラー] 同期の初期化に失敗しました
    echo.
    pause
    exit /b 1
)

echo.
echo サーバーを起動中...
echo.

docker compose --env-file !ENV_FILE! up -d --no-deps server bossbar-manager discord-notify

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo サーバーが正常に起動しました！
    echo ========================================
    echo.
    echo ログを確認: docker logs -f mc_server
    if not "%~1"=="" (
        echo サーバー停止: stop-server.bat %~1 を実行
    ) else (
        echo サーバー停止: stop-server.bat を実行
    )
    echo.
) else (
    echo.
    echo [エラー] サーバーの起動に失敗しました
    echo 上記のエラーメッセージを確認してください
    echo.
)

pause
