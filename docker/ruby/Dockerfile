# Ruby実行環境カスタムイメージ
# aws-sdk-s3とtar/gzipをプリインストール

FROM ruby:3.2-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    tar \
    gzip \
    && rm -rf /var/lib/apt/lists/*

# R2同期用のgem
RUN gem install aws-sdk-s3 --no-document

WORKDIR /app
