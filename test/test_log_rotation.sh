#!/bin/bash
# ログローテーション検証スクリプト

set -e

# serverコンテナ内のパス（書き込み可能）
LOG_FILE="/data/logs/latest.log"
# 操作はserverコンテナで、監視結果はdiscord-notifyで確認
WRITE_SERVICE="server"

echo "=== ログローテーション検証スクリプト ==="
echo

# 1. 初期状態確認
echo "1. 初期i-node確認"
docker compose exec $WRITE_SERVICE stat -c "i-node: %i" $LOG_FILE

sleep 2

# 2. ログに参加イベントを書き込み（ローテーション前）
echo "2. ローテーション前のイベント書き込み"
docker compose exec $WRITE_SERVICE sh -c "echo '[$(date +%H:%M:%S)] [Server thread/INFO]: PlayerBefore joined the game' >> $LOG_FILE"

sleep 2

# 3. ログローテーション実行
echo "3. ログローテーション実行"
docker compose exec $WRITE_SERVICE sh -c "
  mv $LOG_FILE ${LOG_FILE}.old
  touch $LOG_FILE
"

sleep 2

# 4. 新しいi-node確認
echo "4. 新しいi-node確認"
docker compose exec $WRITE_SERVICE stat -c "i-node: %i" $LOG_FILE

sleep 2

# 5. ログに参加イベントを書き込み（ローテーション後）
echo "5. ローテーション後のイベント書き込み"
docker compose exec $WRITE_SERVICE sh -c "echo '[$(date +%H:%M:%S)] [Server thread/INFO]: PlayerAfter joined the game' >> $LOG_FILE"

echo
echo "=== 検証完了 ==="
echo "discord-notifyのログで以下を確認してください："
echo "  - '[LogWatcher] ログローテーションを検出しました' が表示される"
echo "  - PlayerBefore と PlayerAfter の両方が検出される"
