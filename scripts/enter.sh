#!/usr/bin/env bash
# 进入运行中的开发容器
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-lc-dev-env}"
podman exec -it "$CONTAINER_NAME" bash
