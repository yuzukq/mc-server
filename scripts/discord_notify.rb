# frozen_string_literal: true

# Discord Webhook 通知スクリプト
# サーバ起動/停止、プレイヤー参加/退出をDiscordに通知する

require 'net/http'
require 'json'
require 'uri'
require 'time'
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
DISCORD_WEBHOOK_URL = ENV.fetch('DISCORD_WEBHOOK_URL', '')
LOG_FILE_PATH = '/app/logs/latest.log'

# =============================================================================
# Discord Webhook 送信
# =============================================================================

class DiscordWebhook
  COLOR_BLUE = 0x58b2f2
  COLOR_GREEN = 0x57F287
  COLOR_ORANGE = 0xF0B232
  COLOR_RED = 0xED4245

  def initialize(webhook_url)
    @webhook_url = webhook_url
    @enabled = !webhook_url.empty?
  end

  def send(payload, log_message: nil)
    puts "[Discord] #{log_message || payload.to_json}"

    return unless @enabled

    uri = URI.parse(@webhook_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 10


    request = Net::HTTP::Post.new(uri.request_uri, { 'Content-Type' => 'application/json' })
    request.body = payload.to_json

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPNoContent)
      puts "[Discord] Webhook送信失敗: #{response.code} #{response.message}"
    end
  rescue StandardError => e
    puts "[Discord] Webhook送信エラー: #{e.message}"
  end
end

# =============================================================================
# ログファイル監視
# =============================================================================

class LogWatcher
  JOIN_PATTERN = /\[Server thread\/INFO\].*: (\w+) joined the game/
  LEAVE_PATTERN = /\[Server thread\/INFO\].*: (\w+) left the game/

  def initialize(log_path)
    @log_path = log_path
    @running = false
  end

  def start(&block)
    @running = true

    # ログファイルが存在するまで待機
    until File.exist?(@log_path)
      puts "[LogWatcher] ログファイル待機中: #{@log_path}"
      sleep 1
      return unless @running
    end

    File.open(@log_path, 'r') do |file|
      # 末尾にシーク（既存ログはスキップ）
      file.seek(0, IO::SEEK_END)

      while @running
        line = file.gets
        if line
          line = line.strip
          case line
          when JOIN_PATTERN
            block.call(:join, ::Regexp.last_match(1))
          when LEAVE_PATTERN
            block.call(:leave, ::Regexp.last_match(1))
          end
        else
          sleep 0.5
        end
      end
    end
  end

  def stop
    @running = false
  end
end

# =============================================================================
# メイン通知制御
# =============================================================================

class DiscordNotifier
  def initialize
    @webhook = DiscordWebhook.new(DISCORD_WEBHOOK_URL)
    @log_watcher = LogWatcher.new(LOG_FILE_PATH)
    @rcon = nil
    @stopping = false
    @shutdown_sent = false
  end

  def run
    puts '=' * 60
    puts '🔔 Discord 通知サービス'
    puts '=' * 60
    puts
    puts '設定:'
    puts "  RCONホスト: #{RCON_HOST}:#{RCON_PORT}"
    puts "  ホスト表示名: #{HOST_DISPLAY_NAME}"
    puts "  Webhook: #{DISCORD_WEBHOOK_URL.empty? ? '未設定（stdout出力のみ）' : '設定済み'}"
    puts

    setup_signal_handlers
    @rcon = wait_for_server

    # 起動通知
    @webhook.send({
      embeds: [{
        title: 'サーバー起動',
        description: "**#{HOST_DISPLAY_NAME}** さんがホストとして起動しました。",
        color: DiscordWebhook::COLOR_BLUE,
        fields: [
          { name: '📋 お知らせ', value: 'Tailscaleの接続先に注意して参加してください。' }
        ],
        timestamp: Time.now.utc.iso8601
      }]
    }, log_message: "サーバ起動通知: #{HOST_DISPLAY_NAME}")

    # ログ監視開始
    puts '📋 ログ監視を開始します...'
    @log_watcher.start do |event, player_name|
      handle_player_event(event, player_name)
    end
  end

  private

  def setup_signal_handlers
    Signal.trap('TERM') do
      @stopping = true
      @log_watcher.stop
    end

    Signal.trap('INT') do
      @stopping = true
      @log_watcher.stop
    end
  end

  def wait_for_server
    puts '⏳ Minecraftサーバーの起動を待機中...'

    MAX_RETRIES.times do |i|
      rcon = RconClient.new(RCON_HOST, RCON_PORT, RCON_PASSWORD)
      rcon.connect

      result = rcon.command('list')
      puts "   サーバー応答: #{result}"
      puts '✅ サーバーが起動しました！'
      return rcon
    rescue RconClient::ConnectionError => e
      puts "   試行 #{i + 1}/#{MAX_RETRIES}: #{e.message}"
      sleep RETRY_INTERVAL
    rescue RconClient::AuthenticationError => e
      puts "❌ 認証失敗: #{e.message}"
      exit 1
    end

    puts '❌ サーバーが時間内に起動しませんでした'
    exit 1
  end

  def handle_player_event(event, player_name)
    count = fetch_player_count

    case event
    when :join
      @webhook.send({
        embeds: [{
          description: "🟢 **#{player_name}** がサーバーに参加しました",
          color: DiscordWebhook::COLOR_GREEN,
          fields: [
            { name: 'オンライン', value: "#{count}人", inline: true }
          ],
          timestamp: Time.now.utc.iso8601
        }]
      }, log_message: "#{player_name} が参加（#{count}人）")
    when :leave
      @webhook.send({
        embeds: [{
          description: "🔴 **#{player_name}** がサーバーから退出しました",
          color: DiscordWebhook::COLOR_ORANGE,
          fields: [
            { name: 'オンライン', value: "#{count}人", inline: true }
          ],
          timestamp: Time.now.utc.iso8601
        }]
      }, log_message: "#{player_name} が退出（#{count}人）")
    end
  end

  def fetch_player_count
    result = @rcon.command('list')
    # "There are X of a max of Y players online: ..."
    if result =~ /There are (\d+)/
      ::Regexp.last_match(1)
    else
      '?'
    end
  rescue StandardError => e
    puts "[RCON] プレイヤー数取得エラー: #{e.message}"
    # RCON再接続を試みる
    reconnect_rcon
    '?'
  end

  def reconnect_rcon
    @rcon&.disconnect
    @rcon = RconClient.new(RCON_HOST, RCON_PORT, RCON_PASSWORD)
    @rcon.connect
  rescue StandardError => e
    puts "[RCON] 再接続失敗: #{e.message}"
  end

  def shutdown
    return if @shutdown_sent

    @shutdown_sent = true
    @webhook.send({
      embeds: [{
        title: 'サーバー停止',
        description: 'サーバーが停止しました。',
        color: DiscordWebhook::COLOR_RED,
        timestamp: Time.now.utc.iso8601
      }]
    }, log_message: 'サーバ停止通知')
    @rcon&.disconnect
  end
end

# =============================================================================
# メイン処理
# =============================================================================

$stdout.sync = true

notifier = DiscordNotifier.new

at_exit do
  notifier.send(:shutdown)
end

notifier.run
