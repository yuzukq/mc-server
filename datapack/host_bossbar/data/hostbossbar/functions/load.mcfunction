# サーバー起動時（データパック読み込み時）に実行
# tickループを開始する
bossbar set minecraft:host_info players @a
schedule function hostbossbar:tick 20t
