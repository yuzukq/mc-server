#!/bin/bash
# MCサーバー手動バックアップスクリプト
# ワールドデータを即時バックアップします

echo "========================================"
echo "    Minecraft ワールドバックアップ"
echo "========================================"
echo

cd "$(dirname "$0")"

# サーバーが起動しているか確認
if ! docker compose ps server 2>/dev/null | grep -q "running"; then
    echo "[エラー] Minecraftサーバーが起動していません"
    echo "先に start-server.sh でサーバーを起動してください"
    exit 1
fi

echo "バックアップを実行中..."
docker compose run --rm backup

if [ $? -eq 0 ]; then
    echo
    echo "========================================"
    echo "バックアップが正常に完了しました！"
    echo "========================================"
    echo
else
    echo
    echo "[エラー] バックアップに失敗しました"
    echo "上記のエラーメッセージを確認してください"
    echo
    exit 1
fi
