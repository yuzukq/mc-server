#!/bin/bash
# MCサーバー停止スクリプト
# サーバーを停止し、ワールドデータを自動同期します
# 使い方: ./stop-server.sh [環境名]
#   例: ./stop-server.sh dev  → .env.dev を使用

echo "========================================"
echo "Minecraftサーバー停止 (R2同期)"
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

echo "サーバーを停止中..."
docker compose --env-file "$ENV_FILE" down

echo
echo "ワールドデータをR2にアップロードしてロックを解放中..."
docker compose --env-file "$ENV_FILE" run --rm sync-shutdown

if [ $? -eq 0 ]; then
    echo
    echo "========================================"
    echo "サーバーが正常に停止しました！"
    echo "ワールドデータをR2にアップロードしました"
    echo "========================================"
    echo
else
    echo
    echo "[エラー] データの同期に失敗しました"
    echo "上記のエラーメッセージを確認してください"
    echo
    exit 1
fi
