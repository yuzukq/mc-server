#!/usr/bin/env ruby
# frozen_string_literal: true

# Minecraft ワールドデータ バックアップスクリプト for Cloudflare R2
# 定期バックアップと手動バックアップをサポート

require 'aws-sdk-s3'
require 'socket'
require 'fileutils'
require 'time'

# =============================================================================
# 設定
# =============================================================================

R2_ACCOUNT_ID = ENV['R2_ACCOUNT_ID']
R2_ACCESS_KEY_ID = ENV['R2_ACCESS_KEY_ID']
R2_SECRET_ACCESS_KEY = ENV['R2_SECRET_ACCESS_KEY']
R2_BUCKET_NAME = ENV['R2_BUCKET_NAME']
R2_ENDPOINT = ENV['R2_ENDPOINT']
LOCAL_DATA_DIR = ENV.fetch('LOCAL_DATA_DIR', './data')

BACKUP_PREFIX = 'backups/'
MAX_BACKUPS = 3
BACKUP_INTERVAL_MINUTES = ENV.fetch('BACKUP_INTERVAL_MINUTES', '30').to_i

# RCON設定
RCON_HOST = ENV.fetch('RCON_HOST', 'server')
RCON_PORT = ENV.fetch('RCON_PORT', '25575').to_i
RCON_PASSWORD = ENV.fetch('RCON_PASSWORD', 'minecraft')
MAX_RETRIES = ENV.fetch('MAX_RETRIES', '30').to_i
RETRY_INTERVAL = ENV.fetch('RETRY_INTERVAL', '5').to_i

# RCONパケットタイプ
SERVERDATA_AUTH = 3
SERVERDATA_AUTH_RESPONSE = 2
SERVERDATA_EXECCOMMAND = 2

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

  def connect
    @socket = TCPSocket.new(@host, @port)
    authenticate
  rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
    raise ConnectionError, "#{@host}:#{@port} への接続に失敗しました - #{e.message}"
  end

  def disconnect
    @socket&.close
    @socket = nil
  end

  def command(cmd)
    raise ConnectionError, '未接続です' unless @socket

    send_packet(SERVERDATA_EXECCOMMAND, cmd)
    _, _, body = receive_packet
    body
  end

  private

  def authenticate
    send_packet(SERVERDATA_AUTH, @password)
    id, type, = receive_packet

    raise AuthenticationError, 'RCON認証に失敗しました' if id == -1 || type != SERVERDATA_AUTH_RESPONSE
  end

  def send_packet(type, body)
    @request_id += 1
    body_bytes = body.encode('UTF-8')

    packet_body = [@request_id, type].pack('VV') + body_bytes + "\x00\x00"
    packet = [packet_body.bytesize].pack('V') + packet_body

    @socket.write(packet)
    @request_id
  end

  def receive_packet
    size_data = @socket.read(4)
    raise ConnectionError, '接続が切断されました' unless size_data

    size = size_data.unpack1('V')

    data = @socket.read(size)
    raise ConnectionError, 'パケットが不完全です' unless data && data.bytesize == size

    id, type = data[0, 8].unpack('VV')
    body = data[8..-3] || ''

    [id, type, body]
  end
end

# =============================================================================
# バックアップ通知クラス
# =============================================================================

class BackupNotifier
  def initialize
    @rcon = nil
  end

  def connect
    @rcon = RconClient.new(RCON_HOST, RCON_PORT, RCON_PASSWORD)
    @rcon.connect
    true
  rescue RconClient::ConnectionError, RconClient::AuthenticationError => e
    puts "⚠️  RCON接続エラー: #{e.message}"
    @rcon = nil
    false
  end

  def disconnect
    @rcon&.disconnect
    @rcon = nil
  end

  def save_all_flush
    return false unless @rcon

    puts '  > save-all flush'
    result = @rcon.command('save-all flush')
    puts "    #{result}" unless result.empty?
    sleep 2
    true
  rescue StandardError => e
    puts "⚠️  save-all flush エラー: #{e.message}"
    false
  end

  def save_off
    return false unless @rcon

    puts '  > save-off'
    result = @rcon.command('save-off')
    puts "    #{result}" unless result.empty?
    true
  rescue StandardError => e
    puts "⚠️  save-off エラー: #{e.message}"
    false
  end

  def save_on
    return false unless @rcon

    puts '  > save-on'
    result = @rcon.command('save-on')
    puts "    #{result}" unless result.empty?
    true
  rescue StandardError => e
    puts "⚠️  save-on エラー: #{e.message}"
    false
  end

  def notify_chat(message)
    return false unless @rcon

    json_message = %Q({"text":"[Backup] #{message}","color":"aqua"})
    cmd = "tellraw @a #{json_message}"
    puts "  > #{cmd}"
    @rcon.command(cmd)
    true
  rescue StandardError => e
    puts "⚠️  チャット通知エラー: #{e.message}"
    false
  end
end

# =============================================================================
# R2バックアップクラス
# =============================================================================

class R2Backup
  def initialize
    validate_config
    @s3_client = Aws::S3::Client.new(
      endpoint: R2_ENDPOINT,
      access_key_id: R2_ACCESS_KEY_ID,
      secret_access_key: R2_SECRET_ACCESS_KEY,
      region: 'auto',
      force_path_style: true
    )
  end

  def validate_config
    required_vars = %w[
      R2_ACCOUNT_ID
      R2_ACCESS_KEY_ID
      R2_SECRET_ACCESS_KEY
      R2_BUCKET_NAME
      R2_ENDPOINT
    ]
    missing = required_vars.select { |var| ENV[var].nil? || ENV[var].empty? }
    return if missing.empty?

    puts "❌ エラー: 必須環境変数が設定されていません: #{missing.join(', ')}"
    puts '.envファイルを確認してください'
    exit 1
  end

  def create_backup
    local_data_path = File.expand_path(LOCAL_DATA_DIR)
    timestamp = Time.now.strftime('%Y%m%d-%H%M%S')
    backup_key = "#{BACKUP_PREFIX}backup-#{timestamp}.tar.gz"
    archive_path = File.join(File.dirname(local_data_path), "backup-#{timestamp}.tar.gz")

    unless Dir.exist?(local_data_path)
      puts "❌ エラー: データディレクトリが見つかりません: #{local_data_path}"
      return nil
    end

    puts "📦 バックアップを作成中: #{backup_key}"

    create_tar_gz(local_data_path, archive_path)

    File.open(archive_path, 'rb') do |file|
      @s3_client.put_object(
        bucket: R2_BUCKET_NAME,
        key: backup_key,
        body: file
      )
    end

    FileUtils.rm_f(archive_path)
    puts "✅ バックアップをR2にアップロードしました: #{backup_key}"
    backup_key
  rescue StandardError => e
    FileUtils.rm_f(archive_path) if archive_path && File.exist?(archive_path)
    puts "❌ バックアップ作成エラー: #{e.message}"
    nil
  end

  def list_backups
    response = @s3_client.list_objects_v2(
      bucket: R2_BUCKET_NAME,
      prefix: BACKUP_PREFIX
    )

    backups = response.contents.select { |obj| obj.key.end_with?('.tar.gz') }
    backups.sort_by(&:last_modified)
  rescue StandardError => e
    puts "❌ バックアップ一覧取得エラー: #{e.message}"
    []
  end

  def rotate_backups
    backups = list_backups

    return if backups.size <= MAX_BACKUPS

    to_delete = backups[0..-(MAX_BACKUPS + 1)]
    to_delete.each do |backup|
      puts "🗑️  古いバックアップを削除: #{backup.key}"
      @s3_client.delete_object(
        bucket: R2_BUCKET_NAME,
        key: backup.key
      )
    end
  rescue StandardError => e
    puts "⚠️  バックアップローテーションエラー: #{e.message}"
  end

  private

  def create_tar_gz(source_dir, archive_path)
    abs_archive_path = File.expand_path(archive_path)
    Dir.chdir(source_dir) do
      result = system('tar', '-czf', abs_archive_path, '.')
      raise 'tarアーカイブの作成に失敗しました' unless result
    end
  end
end

# =============================================================================
# バックアップスケジューラクラス
# =============================================================================

class BackupScheduler
  def initialize
    @r2_backup = R2Backup.new
    @notifier = BackupNotifier.new
    @running = false
  end

  def wait_for_server
    puts '⏳ Minecraftサーバーの起動を待機中...'

    MAX_RETRIES.times do |i|
      if @notifier.connect
        puts '✅ サーバーに接続しました！'
        return true
      end

      puts "   試行 #{i + 1}/#{MAX_RETRIES}"
      sleep RETRY_INTERVAL
    end

    puts '❌ サーバーが時間内に起動しませんでした'
    false
  end

  def run_backup
    puts
    puts '=' * 60
    puts "🔄 バックアップを開始: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
    puts '=' * 60

    @notifier.connect unless @notifier.instance_variable_get(:@rcon)

    start_time = Time.now
    @notifier.notify_chat("バックアップを開始します... (#{start_time.strftime('%H:%M')})")

    @notifier.save_all_flush
    @notifier.save_off

    begin
      backup_key = @r2_backup.create_backup

      if backup_key
        @r2_backup.rotate_backups
        end_time = Time.now
        @notifier.notify_chat("バックアップが完了しました! (#{end_time.strftime('%Y-%m-%d %H:%M')})")
        puts '✅ バックアップ処理が完了しました'
      else
        @notifier.notify_chat('バックアップに失敗しました')
        puts '❌ バックアップ処理に失敗しました'
      end
    ensure
      @notifier.save_on
    end
  end

  def run_scheduler
    unless wait_for_server
      exit 1
    end

    @running = true
    interval_seconds = BACKUP_INTERVAL_MINUTES * 60

    puts
    puts "📅 定期バックアップスケジューラを開始"
    puts "   間隔: #{BACKUP_INTERVAL_MINUTES}分"
    puts "   最大保持数: #{MAX_BACKUPS}"
    puts

    trap('INT') do
      puts "\n⚠️  シャットダウンシグナルを受信しました..."
      @running = false
    end

    trap('TERM') do
      puts "\n⚠️  シャットダウンシグナルを受信しました..."
      @running = false
    end

    while @running
      run_backup

      puts
      puts "💤 次のバックアップまで #{BACKUP_INTERVAL_MINUTES}分 待機中..."
      puts

      sleep_with_interrupt(interval_seconds)
    end

    @notifier.disconnect
    puts '👋 スケジューラを終了しました'
  end

  def run_once
    puts '🚀 即時バックアップを実行'

    unless @notifier.connect
      puts '⚠️  サーバーに接続できません。RCONなしでバックアップを実行します。'
    end

    run_backup
    @notifier.disconnect
  end

  def show_list
    puts '📋 バックアップ一覧'
    puts

    backups = @r2_backup.list_backups

    if backups.empty?
      puts '   バックアップがありません'
      return
    end

    backups.reverse.each_with_index do |backup, idx|
      size_mb = (backup.size / 1024.0 / 1024.0).round(2)
      time = backup.last_modified.localtime.strftime('%Y-%m-%d %H:%M:%S')
      puts "   #{idx + 1}. #{backup.key}"
      puts "      サイズ: #{size_mb} MB | 作成日時: #{time}"
    end
  end

  private

  def sleep_with_interrupt(seconds)
    end_time = Time.now + seconds
    while @running && Time.now < end_time
      sleep 1
    end
  end
end

# =============================================================================
# メイン処理
# =============================================================================

def print_usage
  puts '使用方法: ruby backup.rb <コマンド>'
  puts
  puts 'コマンド:'
  puts '  run    - 定期バックアップスケジューラを起動'
  puts '  now    - 即時バックアップを実行'
  puts '  list   - バックアップ一覧を表示'
  exit 1
end

def main
  print_usage if ARGV.empty?

  command = ARGV[0]
  scheduler = BackupScheduler.new

  case command
  when 'run'
    scheduler.run_scheduler
  when 'now'
    scheduler.run_once
  when 'list'
    scheduler.show_list
  else
    puts "❌ 不明なコマンド: #{command}"
    print_usage
  end
rescue StandardError => e
  puts "❌ エラー: #{e.message}"
  exit 1
end

main
