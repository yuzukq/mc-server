# Host Bossbar設定をすべてのプレイヤーに適用
# scheduleで1秒後に自分自身を呼び出す（ループ）
bossbar set minecraft:host_info players @a
schedule function hostbossbar:tick 20t
