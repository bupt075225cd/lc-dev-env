#!/usr/bin/env bash
# 构建开发环境镜像（本机使用内网 SWR 基础镜像 + 阿里云下载镜像）
# 兼容 podman 与 docker
set -euo pipefail

if command -v podman >/dev/null 2>&1; then
  RUNTIME=podman
elif command -v docker >/dev/null 2>&1; then
  RUNTIME=docker
else
  echo "错误: 未找到 podman 或 docker，请先安装其一" >&2
  exit 1
fi

IMAGE_NAME="${IMAGE_NAME:-lc-ubuntu-dev:latest}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

"$RUNTIME" build -f Dockerfile -t "$IMAGE_NAME" \
  --build-arg BASE_IMAGE=swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/library/ubuntu:latest \
  --build-arg GO_DL_BASE=https://mirrors.aliyun.com/golang \
  --build-arg NODE_DL_BASE=https://mirrors.aliyun.com/nodejs-release \
  --build-arg DSH_VERSION="${DSH_VERSION:-latest}" \
  --build-arg NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}" \
  .

echo "镜像构建完成: $IMAGE_NAME"
