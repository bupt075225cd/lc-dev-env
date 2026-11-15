#!/usr/bin/env bash
# 后台运行开发容器，并挂载宿主机 git 目录
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-lc-ubuntu-dev:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-lc-dev-env}"
HOST_GIT_DIR="${HOST_GIT_DIR:-/home/lc/git}"

# 清理同名旧容器（若存在）
podman stop -t 2 "$CONTAINER_NAME" 2>/dev/null || true
podman rm "$CONTAINER_NAME" 2>/dev/null || true

podman run -d --name "$CONTAINER_NAME" \
  --restart=unless-stopped \
  -v "${HOST_GIT_DIR}:/home/git:Z" \
  "$IMAGE_NAME"

echo "容器已启动: $CONTAINER_NAME"
echo "进入容器: scripts/enter.sh 或 podman exec -it $CONTAINER_NAME bash"
