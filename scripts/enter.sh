#!/usr/bin/env bash
# 进入运行中的开发容器
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

CONTAINER_NAME="${CONTAINER_NAME:-lc-dev-env}"
"$RUNTIME" exec -it "$CONTAINER_NAME" bash
