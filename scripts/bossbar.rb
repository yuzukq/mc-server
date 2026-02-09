#!/usr/bin/env ruby
# frozen_string_literal: true

# Minecraft Bossbar マネージャー
# サーバー起動中のホスト情報をbossbarで全プレイヤーに表示する

require_relative 'lib/rcon_client'

# =============================================================================
# 設定
# =============================================================================

RCON_HOST = ENV.fetch('RCON_HOST', 'server')
RCON_PORT = ENV.fetch('RCON_PORT', '25575').to_i
RCON_PASSWORD = ENV.fetch('RCON_PASSWORD', 'minecraft')
HOST_DISPLAY_NAME = ENV.fetch('HOST_DISPLAY_NAME', 'Unknown')
MAX_RETRIES = ENV.fetch('MAX_RETRIES', '30').to_i
RETRY_INTERVAL = ENV.fetch('RETRY_INTERVAL', '5').to_i

# =============================================================================
# Bossbarマネージャー
# =============================================================================

class BossbarManager
  BOSSBAR_ID = 'minecraft:host_info'

  def initialize(rcon)
    @rcon = rcon
  end

  # bossbarをセットアップする
  def setup(hostname)
    puts "📍 ホスト用bossbarを設定中: #{hostname}"

    # 既存のbossbarがあれば削除
    execute("bossbar remove #{BOSSBAR_ID}")

    # ホスト名を含む新しいbossbarを作成
    # JSONテキストコンポーネントで適切なフォーマット
    title = %Q({"text":"Current Host: #{hostname}","color":"green"})
    execute("bossbar add #{BOSSBAR_ID} #{title}")

    # bossbarの外観を設定
    execute("bossbar set #{BOSSBAR_ID} color green")
    execute("bossbar set #{BOSSBAR_ID} style progress")
    execute("bossbar set #{BOSSBAR_ID} max 100")
    execute("bossbar set #{BOSSBAR_ID} value 100")
    execute("bossbar set #{BOSSBAR_ID} visible true")

    # 全プレイヤーに表示
    execute("bossbar set #{BOSSBAR_ID} players @a")

    puts '✅ Bossbarの設定が完了しました！'
  end

  private

  # コマンドを実行してログ出力する
  def execute(command)
    puts "  > #{command}"
    result = @rcon.command(command)
    puts "    #{result}" unless result.empty?
    result
  end
end

# =============================================================================
# メイン処理
# =============================================================================

# Minecraftサーバーの起動を待機する
def wait_for_server
  puts '⏳ Minecraftサーバーの起動を待機中...'

  MAX_RETRIES.times do |i|
    begin
      rcon = RconClient.new(RCON_HOST, RCON_PORT, RCON_PASSWORD)
      rcon.connect

      # listコマンドで接続をテスト
      result = rcon.command('list')
      puts "   サーバー応答: #{result}"

      puts '✅ サーバーが起動しました！'
      return rcon
    rescue RconClient::ConnectionError => e
      puts "   試行 #{i + 1}/#{MAX_RETRIES}: #{e.message}"
      sleep RETRY_INTERVAL
    rescue RconClient::AuthenticationError => e
      puts "❌ 認証失敗: #{e.message}"
      puts '   .envファイルのRCON_PASSWORDを確認してください'
      exit 1
    end
  end

  puts '❌ サーバーが時間内に起動しませんでした'
  exit 1
end

# メイン関数
def main
  puts '=' * 60
  puts '🎮 Minecraft Bossbar マネージャー'
  puts '=' * 60
  puts
  puts '設定:'
  puts "  RCONホスト: #{RCON_HOST}:#{RCON_PORT}"
  puts "  ホスト表示名: #{HOST_DISPLAY_NAME}"
  puts

  rcon = wait_for_server

  begin
    manager = BossbarManager.new(rcon)
    manager.setup(HOST_DISPLAY_NAME)
  ensure
    rcon.disconnect
  end

  puts
  puts '🎉 Bossbarのセットアップが完了しました！終了します...'
end

main
