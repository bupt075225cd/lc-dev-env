#!/usr/bin/env bash
# 构建开发环境镜像（本机使用内网 SWR 基础镜像 + 阿里云下载镜像）
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-lc-ubuntu-dev:latest}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

podman build -f Dockerfile -t "$IMAGE_NAME" \
  --build-arg BASE_IMAGE=swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/library/ubuntu:latest \
  --build-arg GO_DL_BASE=https://mirrors.aliyun.com/golang \
  --build-arg NODE_DL_BASE=https://mirrors.aliyun.com/nodejs-release \
  .

echo "镜像构建完成: $IMAGE_NAME"
