#!/bin/bash
# MCサーバー起動スクリプト
# サーバーを起動し、ワールドデータを自動同期します

echo "========================================"
echo "Minecraftサーバー停止 (R2同期)"
echo "========================================"
echo

cd "$(dirname "$0")"

echo "サーバーを停止中..."
docker compose down

echo
echo "ワールドデータをR2にアップロードしてロックを解放中..."
docker compose run --rm sync-shutdown

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
