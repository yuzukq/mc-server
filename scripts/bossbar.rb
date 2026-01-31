#!/usr/bin/env ruby
# frozen_string_literal: true

# Minecraft Bossbar マネージャー
# サーバー起動中のホスト情報をbossbarで全プレイヤーに表示する

require 'socket'

# =============================================================================
# 設定
# =============================================================================

RCON_HOST = ENV.fetch('RCON_HOST', 'server')
RCON_PORT = ENV.fetch('RCON_PORT', '25575').to_i
RCON_PASSWORD = ENV.fetch('RCON_PASSWORD', 'minecraft')
HOST_DISPLAY_NAME = ENV.fetch('HOST_DISPLAY_NAME', 'Unknown')
MAX_RETRIES = ENV.fetch('MAX_RETRIES', '30').to_i
RETRY_INTERVAL = ENV.fetch('RETRY_INTERVAL', '5').to_i

# RCONパケットタイプ
SERVERDATA_AUTH = 3
SERVERDATA_AUTH_RESPONSE = 2
SERVERDATA_EXECCOMMAND = 2
SERVERDATA_RESPONSE_VALUE = 0

# =============================================================================
# RCONクライアント実装
# =============================================================================

class RconClient
  class AuthenticationError < StandardError; end
  class ConnectionError < StandardError; end

  def initialize(host, port, password)
    @host = host
    @port = port
    @password = password
    @socket = nil
    @request_id = 0
  end

  # サーバーに接続して認証を行う
  def connect
    @socket = TCPSocket.new(@host, @port)
    authenticate
  rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
    raise ConnectionError, "#{@host}:#{@port} への接続に失敗しました - #{e.message}"
  end

  # 接続を切断する
  def disconnect
    @socket&.close
    @socket = nil
  end

  # コマンドを実行して結果を返す
  def command(cmd)
    raise ConnectionError, '未接続です' unless @socket

    send_packet(SERVERDATA_EXECCOMMAND, cmd)
    _, _, body = receive_packet
    body
  end

  private

  # RCON認証を行う
  def authenticate
    send_packet(SERVERDATA_AUTH, @password)
    id, type, = receive_packet

    raise AuthenticationError, 'RCON認証に失敗しました' if id == -1 || type != SERVERDATA_AUTH_RESPONSE
  end

  # パケットを送信する
  def send_packet(type, body)
    @request_id += 1
    body_bytes = body.encode('UTF-8')

    # パケット構造: サイズ(4) + ID(4) + タイプ(4) + ボディ + null(1) + null(1)
    packet_body = [@request_id, type].pack('VV') + body_bytes + "\x00\x00"
    packet = [packet_body.bytesize].pack('V') + packet_body

    @socket.write(packet)
    @request_id
  end

  # パケットを受信する
  def receive_packet
    # サイズを読み取る（4バイト）
    size_data = @socket.read(4)
    raise ConnectionError, '接続が切断されました' unless size_data

    size = size_data.unpack1('V')

    # パケットの残りを読み取る
    data = @socket.read(size)
    raise ConnectionError, 'パケットが不完全です' unless data && data.bytesize == size

    id, type = data[0, 8].unpack('VV')
    body = data[8..-3] || '' # 末尾のnullを除去

    [id, type, body]
  end
end

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
