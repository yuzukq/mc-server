#!/bin/bash
# MCサーバー起動スクリプト
# サーバーを起動し、自動バックアップスケジューラを設定します

echo "========================================"
echo "    R2同期 -> Minecraftサーバー起動"
echo "========================================"
echo

cd "$(dirname "$0")"
SCRIPT_DIR="$(pwd)"

if [ ! -f .env ]; then
    echo "[エラー] .envファイルが見つかりません！"
    echo ".env.exampleを.envにコピーして、R2の認証情報を設定してください。"
    echo
    exit 1
fi

# カスタムRubyイメージのビルドが必要か確認
if ! docker compose images sync-init -q 2>/dev/null | grep -q .; then
    echo "[情報] 初回起動を検出しました。カスタムRubyイメージをビルド中..."
    echo
    if ! docker compose build; then
        echo "[エラー] イメージのビルドに失敗しました"
        exit 1
    fi
    echo
fi

echo "サーバーを起動中..."
echo

docker compose up -d

if [ $? -eq 0 ]; then
    echo
    echo "========================================"
    echo "サーバーが正常に起動しました！"
    echo "========================================"
    echo
    echo "バックアップスケジューラを設定中 (30分間隔)..."
    # 既存のcronジョブがあれば削除し、新しいものを追加
    (crontab -l 2>/dev/null | grep -v "MinecraftBackup"; echo "*/30 * * * * cd \"$SCRIPT_DIR\" && ./backup.sh > /dev/null 2>&1 # MinecraftBackup") | crontab -
    echo "バックアップスケジューラを登録しました。"
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
