#!/bin/bash
# MCサーバー起動スクリプト
# サーバーを起動し、ワールドデータを自動同期します
# 使い方: ./start-server.sh [環境名]
#   例: ./start-server.sh dev  → .env.dev を使用

echo "========================================"
echo "Minecraftサーバー起動 (R2同期)"
echo "========================================"
echo

cd "$(dirname "$0")"

# 環境引数の処理
ENV_ARG="${1:-}"
if [ -n "$ENV_ARG" ]; then
    ENV_FILE=".env.${ENV_ARG}"
    echo "[${ENV_ARG}モード] ${ENV_FILE} を使用します"
    echo
else
    ENV_FILE=".env"
fi

if [ ! -f "$ENV_FILE" ]; then
    echo "[エラー] ${ENV_FILE}ファイルが見つかりません！"
    echo ".env.exampleを${ENV_FILE}にコピーして、R2の認証情報を設定してください。"
    echo
    exit 1
fi

# カスタムRubyイメージのビルドチェック
if ! docker compose --env-file "$ENV_FILE" images sync-init -q 2>/dev/null | grep -q .; then
    echo "[情報] 初回起動を検出しました。カスタムRubyイメージをビルド中..."
    echo
    if ! docker compose --env-file "$ENV_FILE" build; then
        echo "[エラー] イメージのビルドに失敗しました"
        exit 1
    fi
    echo
fi

echo "サーバーを起動中..."
echo

docker compose --env-file "$ENV_FILE" up -d

if [ $? -eq 0 ]; then
    echo
    echo "========================================"
    echo "サーバーが正常に起動しました！"
    echo "========================================"
    echo
    echo "ログを確認: docker logs -f mc_server"
    echo "サーバー停止: ./stop-server.sh を実行"
    echo
else
    echo
    echo "[エラー] サーバーの起動に失敗しました"
    echo "上記のエラーメッセージを確認してください"
    echo
    exit 1
fi
