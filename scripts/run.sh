#!/usr/bin/env bash
# 后台运行开发容器：从阿里云 ACR 拉取 CI 构建的镜像并挂载宿主机 git 目录
set -euo pipefail

REGISTRY="${REGISTRY:-crpi-vb458bo8ja2welze.cn-chengdu.personal.cr.aliyuncs.com}"
IMAGE_NAME="${IMAGE_NAME:-${REGISTRY}/peak2026/lc-dev-env:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-lc-dev-env}"
HOST_GIT_DIR="${HOST_GIT_DIR:-/home/lc/git}"

# 若宿主机挂载目录不存在，先创建
mkdir -p "$HOST_GIT_DIR"

# 镜像不存在则从 ACR 拉取（未提供凭据时，依赖已手动 podman login 的凭据）
if ! podman image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "本地镜像不存在，从 ACR 拉取: $IMAGE_NAME"
  if [[ -n "${ALIYUN_ACR_USERNAME:-}" && -n "${ALIYUN_ACR_PASSWORD:-}" ]]; then
    echo "$ALIYUN_ACR_PASSWORD" | podman login "$REGISTRY" -u "$ALIYUN_ACR_USERNAME" --password-stdin
  fi
  podman pull "$IMAGE_NAME"
fi

# 清理同名旧容器（若存在）
podman stop -t 2 "$CONTAINER_NAME" 2>/dev/null || true
podman rm "$CONTAINER_NAME" 2>/dev/null || true

podman run -d --name "$CONTAINER_NAME" \
  --restart=unless-stopped \
  -v "${HOST_GIT_DIR}:/home/git:Z" \
  "$IMAGE_NAME"

echo "容器已启动: $CONTAINER_NAME"
echo "进入容器: scripts/enter.sh 或 podman exec -it $CONTAINER_NAME bash"
