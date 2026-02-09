# frozen_string_literal: true

require 'socket'

# RCONパケットタイプ
SERVERDATA_AUTH = 3
SERVERDATA_AUTH_RESPONSE = 2
SERVERDATA_EXECCOMMAND = 2
SERVERDATA_RESPONSE_VALUE = 0

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
