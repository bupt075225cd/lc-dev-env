#!/usr/bin/env bash
# 后台运行开发容器：从阿里云 ACR 拉取 CI 构建的镜像并挂载宿主机 git 目录
# 兼容 podman 与 docker
set -euo pipefail

# 检测容器运行时：优先 podman，回退 docker
if command -v podman >/dev/null 2>&1; then
  RUNTIME=podman
elif command -v docker >/dev/null 2>&1; then
  RUNTIME=docker
else
  echo "错误: 未找到 podman 或 docker，请先安装其一" >&2
  exit 1
fi

REGISTRY="${REGISTRY:-crpi-vb458bo8ja2welze.cn-chengdu.personal.cr.aliyuncs.com}"
IMAGE_NAME="${IMAGE_NAME:-${REGISTRY}/peak2026/lc-dev-env:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-lc-dev-env}"
HOST_GIT_DIR="${HOST_GIT_DIR:-/home/lc/git}"
SSH_PORT="${SSH_PORT:-2228}"

# 若宿主机挂载目录不存在，先创建
mkdir -p "$HOST_GIT_DIR"

# 镜像不存在则从 ACR 拉取（未提供凭据时，依赖已手动 login 的凭据）
if ! "$RUNTIME" image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "本地镜像不存在，从 ACR 拉取: $IMAGE_NAME"
  if [[ -n "${ALIYUN_ACR_USERNAME:-}" && -n "${ALIYUN_ACR_PASSWORD:-}" ]]; then
    echo "$ALIYUN_ACR_PASSWORD" | "$RUNTIME" login "$REGISTRY" -u "$ALIYUN_ACR_USERNAME" --password-stdin
    "$RUNTIME" pull "$IMAGE_NAME"
    # 拉取完成后退出登录，避免残留 ACR 凭据
    "$RUNTIME" logout "$REGISTRY" >/dev/null 2>&1 || true
  else
    "$RUNTIME" pull "$IMAGE_NAME"
  fi
fi

# 清理同名旧容器（若存在）
"$RUNTIME" stop -t 2 "$CONTAINER_NAME" 2>/dev/null || true
"$RUNTIME" rm "$CONTAINER_NAME" 2>/dev/null || true

"$RUNTIME" run -d --name "$CONTAINER_NAME" \
  --restart=unless-stopped \
  -p "${SSH_PORT}:22" \
  -v "${HOST_GIT_DIR}:/home/git:Z" \
  "$IMAGE_NAME"

echo "容器已启动: $CONTAINER_NAME"
echo "SSH 端口映射: 宿主机 ${SSH_PORT} -> 容器 22"
echo "SSH 登录: ssh -p ${SSH_PORT} root@127.0.0.1  (密码 123456)"
echo "进入容器: scripts/enter.sh 或 $RUNTIME exec -it $CONTAINER_NAME bash"
