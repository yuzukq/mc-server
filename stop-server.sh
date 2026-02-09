#!/bin/bash
# MCサーバー停止スクリプト
# バックアップスケジューラを削除し、サーバーを停止してワールドデータを同期します

echo "========================================"
echo "    Minecraftサーバー停止 -> R2同期"
echo "========================================"
echo

cd "$(dirname "$0")"

echo "バックアップスケジューラを削除中..."
# cronジョブを削除
crontab -l 2>/dev/null | grep -v "MinecraftBackup" | crontab -
echo "バックアップスケジューラを削除しました。"
echo

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
