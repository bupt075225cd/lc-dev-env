#!/usr/bin/env bash
# 进入运行中的开发容器。
# 容器名由 dev-env.conf 的 CONTAINER_NAME 决定，run.sh / enter.sh / rollback.sh 共用同一配置。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
用法: enter.sh [选项] [命令...]

进入开发容器。默认打开交互式 bash；给出命令时在容器内执行该命令。

选项:
  -n, --name <名称>   容器名（默认取 dev-env.conf 的 CONTAINER_NAME）
  -h, --help          显示帮助

示例:
  scripts/enter.sh
  scripts/enter.sh -n other-env
  scripts/enter.sh go version
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--name)
      [[ $# -ge 2 ]] || die "--name 需要一个容器名"
      CONTAINER_NAME="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) die "未知参数: $1（-h 查看用法）" ;;
    *) break ;;
  esac
done

detect_runtime
validate_config

if ! "$RUNTIME" container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  printf '错误: 容器不存在: %s\n' "$CONTAINER_NAME" >&2
  printf '提示: 先执行 scripts/run.sh 启动。当前容器列表:\n' >&2
  "$RUNTIME" ps -a --format '{{.Names}}  {{.Status}}' 2>/dev/null | sed 's/^/  /' >&2 || true
  exit 1
fi

running="$("$RUNTIME" inspect --format '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || true)"
if [[ "$running" != "true" ]]; then
  die "容器 $CONTAINER_NAME 未运行，请执行 scripts/run.sh 重新启动"
fi

if [[ $# -eq 0 ]]; then
  exec "$RUNTIME" exec -it "$CONTAINER_NAME" bash
fi
# 有 TTY 时分配交互终端，管道/CI 场景下不传 -t，避免 “not a TTY” 报错
if [[ -t 0 && -t 1 ]]; then
  exec "$RUNTIME" exec -it "$CONTAINER_NAME" "$@"
fi
exec "$RUNTIME" exec "$CONTAINER_NAME" "$@"
