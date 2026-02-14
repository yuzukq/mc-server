#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="mc_server"

# コンテナ起動チェック
if ! docker inspect --format='{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q true; then
  echo "Error: Container '$CONTAINER_NAME' is not running." >&2
  exit 1
fi

# CPU/メモリ取得
IFS='|' read -r cpu mem_usage mem_pct < <(
  docker stats "$CONTAINER_NAME" --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}'
)

# Overall行をパース、ANSIエスケープを除去
tps_output=$(docker exec "$CONTAINER_NAME" rcon-cli forge tps 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
overall_line=$(echo "$tps_output" | grep -i 'Overall:')
mspt=$(echo "$overall_line" | sed 's/.*Mean tick time: \([0-9.]*\).*/\1/')
tps=$(echo "$overall_line" | sed 's/.*Mean TPS: \([0-9.]*\).*/\1/')

# ターミナル出力用
echo "=== MC Server Performance ==="
printf "TPS:    %s / 20.0\n" "$tps"
printf "MSPT:   %s ms\n" "$mspt"
printf "CPU:    %s\n" "$cpu"
printf "Memory: %s (%s)\n" "$mem_usage" "$mem_pct"
echo "=============================="

tps_int=${tps%%.*}
if [ "$tps_int" -ge 18 ]; then
  tps_color="green"
elif [ "$tps_int" -ge 15 ]; then
  tps_color="yellow"
else
  tps_color="red"
fi

# tellrawでゲーム内チャットに送信
tellraw_json=$(cat <<EOF
["",{"text":"=== Server Performance ===\n","color":"gold","bold":true},{"text":"TPS:    ","color":"gray"},{"text":"${tps} / 20.0\n","color":"${tps_color}"},{"text":"MSPT:   ","color":"gray"},{"text":"${mspt} ms\n","color":"white"},{"text":"CPU:    ","color":"gray"},{"text":"${cpu}\n","color":"white"},{"text":"Memory: ","color":"gray"},{"text":"${mem_usage} (${mem_pct})","color":"white"}]
EOF
)

docker exec "$CONTAINER_NAME" rcon-cli "tellraw @a ${tellraw_json}" > /dev/null 2>&1

echo "(Sent to in-game chat)"
