#!/usr/bin/env bash
# 输出当前 DSH Web GUI 的带 token 启动 URL。
# 容器每次重启都会换 token，Windows 客户端请使用这里打印的地址。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

detect_runtime
validate_config

url_file="${DSH_HOST_DIR}/web-url.txt"
if [[ -s "$url_file" ]]; then
  cat "$url_file"
  exit 0
fi

url="$("$RUNTIME" logs "$CONTAINER_NAME" 2>&1 | grep -m1 '^dsh web: http' || true)"
[[ -n "$url" ]] || die "未找到 Web GUI URL：容器未运行或 dsh web 尚未就绪"
printf '%s\n' "${url#dsh web: }"
