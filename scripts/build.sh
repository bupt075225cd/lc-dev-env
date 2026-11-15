#!/usr/bin/env bash
# 构建开发环境镜像
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-lc-ubuntu-dev:latest}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"
podman build -f Dockerfile -t "$IMAGE_NAME" .
echo "镜像构建完成: $IMAGE_NAME"
