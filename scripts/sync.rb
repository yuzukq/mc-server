# frozen_string_literal: true

# Minecraft ワールドデータ同期スクリプト for Cloudflare R2
# ワールドデータの同期とサーバーロック機構を管理する

require 'aws-sdk-s3'
require 'json'
require 'socket'
require 'fileutils'

# =============================================================================
# 設定
# =============================================================================

R2_ACCOUNT_ID = ENV['R2_ACCOUNT_ID']
R2_ACCESS_KEY_ID = ENV['R2_ACCESS_KEY_ID']
R2_SECRET_ACCESS_KEY = ENV['R2_SECRET_ACCESS_KEY']
R2_BUCKET_NAME = ENV['R2_BUCKET_NAME']
R2_ENDPOINT = ENV['R2_ENDPOINT']
LOCAL_DATA_DIR = ENV.fetch('LOCAL_DATA_DIR', './data')

LOCK_FILE_KEY = 'server.lock'
DATA_ARCHIVE_KEY = 'server-data.tar.gz'

# =============================================================================
# R2同期クラス
# =============================================================================

class R2Sync
  def initialize
    validate_config
    @s3_client = Aws::S3::Client.new(
      endpoint: R2_ENDPOINT,
      access_key_id: R2_ACCESS_KEY_ID,
      secret_access_key: R2_SECRET_ACCESS_KEY,
      region: 'auto',
      force_path_style: true
    )
    @hostname = Socket.gethostname
  end

  # 必須環境変数のバリデーション
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

  # ロックファイルの存在確認
  def check_lock
    response = @s3_client.get_object(
      bucket: R2_BUCKET_NAME,
      key: LOCK_FILE_KEY
    )
    JSON.parse(response.body.read)
  rescue Aws::S3::Errors::NoSuchKey
    nil
  end

  # ロックファイルの作成
  def create_lock
    lock_data = {
      'hostname' => @hostname,
      'timestamp' => Time.now.utc.iso8601,
      'pid' => Process.pid
    }

    existing_lock = check_lock
    if existing_lock
      puts '❌ エラー: サーバーは既に起動しています！'
      puts "   ロック元: #{existing_lock['hostname'] || 'unknown'}"
      puts "   開始時刻: #{existing_lock['timestamp'] || 'unknown'}"
      puts
      puts "サーバーが起動していないことが確実な場合は、R2バケットから'server.lock'を手動で削除してください"
      exit 1
    end

    @s3_client.put_object(
      bucket: R2_BUCKET_NAME,
      key: LOCK_FILE_KEY,
      body: JSON.pretty_generate(lock_data),
      content_type: 'application/json'
    )
    puts "✅ ロックを取得しました: #{@hostname}"
  end

  # ロック解放
  def release_lock
    @s3_client.delete_object(
      bucket: R2_BUCKET_NAME,
      key: LOCK_FILE_KEY
    )
    puts '✅ ロックを解放しました'
  rescue Aws::S3::Errors::ServiceError => e
    puts "⚠️  警告: ロックを解放できませんでした: #{e.message}"
  end

  # R2からのダウンロード
  def download_data
    local_data_path = File.expand_path(LOCAL_DATA_DIR)
    parent_dir = File.dirname(local_data_path)
    archive_path = File.join(parent_dir, DATA_ARCHIVE_KEY)
    temp_dir = File.join(parent_dir, "#{File.basename(local_data_path)}.tmp.#{Process.pid}")

    puts '📥 R2からサーバーデータをダウンロード中...'

    begin
      @s3_client.head_object(
        bucket: R2_BUCKET_NAME,
        key: DATA_ARCHIVE_KEY
      )

      FileUtils.mkdir_p(parent_dir)
      File.open(archive_path, 'wb') do |file|
        @s3_client.get_object(
          bucket: R2_BUCKET_NAME,
          key: DATA_ARCHIVE_KEY
        ) do |chunk|
          file.write(chunk)
        end
      end

      # 一時ディレクトリに展開
      FileUtils.rm_rf(temp_dir)
      FileUtils.mkdir_p(temp_dir)

      begin
        extract_tar_gz(archive_path, temp_dir)
      rescue StandardError => e
        # 展開失敗時: 一時ディレクトリとアーカイブをクリーンアップ
        FileUtils.rm_rf(temp_dir)
        FileUtils.rm_f(archive_path)
        raise e
      end

      # 展開成功後: 既存データを削除して一時ディレクトリの内容を移動
      FileUtils.mkdir_p(local_data_path) unless Dir.exist?(local_data_path)

      # 既存のデータディレクトリの中身をクリア（マウントポイントなのでディレクトリ自体は削除しない）
      Dir.each_child(local_data_path) do |item|
        FileUtils.rm_rf(File.join(local_data_path, item))
      end

      # 一時ディレクトリの内容を移動
      Dir.each_child(temp_dir) do |item|
        FileUtils.mv(File.join(temp_dir, item), local_data_path)
      end

      puts "✅ サーバーデータをダウンロードして展開しました: #{local_data_path}"
    rescue Aws::S3::Errors::NotFound
      puts 'ℹ️  R2にサーバーデータがありません。新規サーバーとして起動します。'
    rescue Aws::S3::Errors::ServiceError => e
      puts "❌ サーバーデータのダウンロードエラー: #{e.message}"
      raise
    ensure
      # 一時ディレクトリとアーカイブをクリーンアップ
      FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
      FileUtils.rm_f(archive_path) if File.exist?(archive_path)
    end
  end

  # R2へのアップロード
  def upload_data
    local_data_path = File.expand_path(LOCAL_DATA_DIR)
    archive_path = File.join(File.dirname(local_data_path), DATA_ARCHIVE_KEY)

    unless Dir.exist?(local_data_path)
      puts "⚠️  警告: データディレクトリが見つかりません: #{local_data_path}"
      return
    end

    puts '📤 サーバーデータをR2にアップロード中...'

    create_tar_gz(local_data_path, archive_path)

    File.open(archive_path, 'rb') do |file|
      @s3_client.put_object(
        bucket: R2_BUCKET_NAME,
        key: DATA_ARCHIVE_KEY,
        body: file
      )
    end

    FileUtils.rm_f(archive_path)
    puts '✅ サーバーデータをR2にアップロードしました'
  end

  # 初期化処理: ロック取得 → データダウンロード
  def sync_init
    puts '🚀 サーバー同期を初期化中...'
    create_lock
    download_data
    puts '✅ 同期の初期化が完了しました'
  end

  # シャットダウン処理: データアップロード → ロック解放
  def sync_shutdown
    puts '🔄 サーバー同期をシャットダウン中...'
    upload_data
    release_lock
    puts '✅ 同期のシャットダウンが完了しました'
  end

  private

  # tar.gzアーカイブを作成
  def create_tar_gz(source_dir, archive_path)
    abs_archive_path = File.expand_path(archive_path)
    Dir.chdir(source_dir) do
      result = system('tar', '-czf', abs_archive_path, '.')
      raise 'tarアーカイブの作成に失敗しました' unless result
    end
  end

  # tar.gzアーカイブを展開
  def extract_tar_gz(archive_path, dest_dir)
    FileUtils.mkdir_p(dest_dir)
    result = system('tar', '-xzf', archive_path, '-C', dest_dir)
    raise 'tarアーカイブの展開に失敗しました' unless result
  end
end

# =============================================================================
# メイン処理
# =============================================================================

def print_usage
  puts '使用方法: ruby sync.rb <コマンド>'
  puts
  puts 'コマンド:'
  puts '  init         - ロック取得とデータダウンロード（サーバー起動前に実行）'
  puts '  shutdown     - データアップロードとロック解放（サーバー停止後に実行）'
  puts '  download     - サーバーデータのダウンロードのみ'
  puts '  upload       - サーバーデータのアップロードのみ'
  puts '  lock         - サーバーロックの取得のみ'
  puts '  unlock       - サーバーロックの解放のみ'
  puts '  check-lock   - 現在のロック状態を確認'
  exit 1
end

def main
  print_usage if ARGV.empty?

  command = ARGV[0]
  sync = R2Sync.new

  case command
  when 'init'
    sync.sync_init
  when 'shutdown'
    sync.sync_shutdown
  when 'download'
    sync.download_data
  when 'upload'
    sync.upload_data
  when 'lock'
    sync.create_lock
  when 'unlock'
    sync.release_lock
  when 'check-lock'
    lock = sync.check_lock
    if lock
      puts '🔒 サーバーはロックされています'
      puts "   ホスト名: #{lock['hostname'] || 'unknown'}"
      puts "   開始時刻: #{lock['timestamp'] || 'unknown'}"
    else
      puts '🔓 サーバーはロックされていません'
    end
  else
    puts "❌ 不明なコマンド: #{command}"
    exit 1
  end
rescue StandardError => e
  puts "❌ エラー: #{e.message}"
  exit 1
end

main
