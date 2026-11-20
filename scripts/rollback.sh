#!/usr/bin/env bash
# 回滚开发容器到历史版本。
#
# 版本记录由 scripts/run.sh 写入 STATE_DIR（默认 .state/），每次钉住新 digest 记一条。
# 回滚即用历史 digest 重新启动容器，因此不受 tag 后续指向变化影响。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
用法: rollback.sh [选项] [目标]

查看或回滚到历史镜像版本。

目标:
  <序号>          历史记录序号（1 = 最新，见 --list）
  <tag>           切换到某个 tag，例如 v1.2.0
  <完整引用>      例如 repo:tag 或 repo@sha256:...
  sha256:...      按摘要回滚

选项:
  -l, --list      列出可回滚的历史版本
      --current   只输出当前钉住的版本
  -h, --help      显示帮助

示例:
  scripts/rollback.sh --list
  scripts/rollback.sh 2
  scripts/rollback.sh sha256:1f2e3d...
EOF
}

detect_runtime
validate_config
state_init

history_file="$STATE_DIR/history.tsv"
current_pinned="$(state_current_pinned)"

print_history() {
  if [[ ! -s "$history_file" ]]; then
    log_info "暂无版本记录（$history_file）"
    return 0
  fi
  local total i=0 ts ref pinned tag marker
  total="$(wc -l < "$history_file")"
  printf '%-4s %-21s %-12s %s\n' "序号" "钉住时间(UTC)" "标签" "钉住引用"
  while IFS=$'\t' read -r ts ref pinned tag; do
    i=$((i + 1))
    [[ -n "${ts:-}" ]] || continue
    marker=""
    if [[ "$pinned" == "$current_pinned" ]]; then
      marker="  <- 当前"
    fi
    printf '%-4s %-21s %-12s %s%s\n' "$((total - i + 1))" "$ts" "${tag:-?}" "$pinned" "$marker"
  done < <(awk '{ line[NR] = $0 } END { for (i = NR; i > 0; i--) print line[i] }' "$history_file")
  printf '\n当前钉住: %s\n' "${current_pinned:-<无>}"
}

case "${1:-}" in
  -l|--list)
    print_history
    exit 0
    ;;
  --current)
    printf '%s\n' "${current_pinned:-}"
    exit 0
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  "")
    print_history
    printf '\n用法: scripts/rollback.sh <序号|tag|sha256:...>\n'
    exit 0
    ;;
esac

target_arg="$1"
shift
[[ $# -eq 0 ]] || die "只能指定一个回滚目标（-h 查看用法）"

if [[ ! -s "$history_file" ]]; then
  die "暂无版本记录，无法回滚（$history_file）"
fi

repo="$(image_repo)"
target=""

if [[ "$target_arg" =~ ^[0-9]+$ ]]; then
  total="$(wc -l < "$history_file")"
  n="$target_arg"
  (( n >= 1 && n <= total )) || die "序号超出范围: $n（可用 1..$total，1 为最新）"
  line="$(awk -v want="$((total - n + 1))" 'NR == want' "$history_file")"
  IFS=$'\t' read -r _ts _ref pinned _tag <<< "$line"
  [[ -n "${pinned:-}" ]] || die "历史记录解析失败: $line"
  target="$pinned"
elif [[ "$target_arg" == sha256:* ]]; then
  target="${repo}@${target_arg}"
elif [[ "$target_arg" == */* ]]; then
  target="$target_arg"
else
  target="${repo}:${target_arg}"
fi

if [[ "$target" == "$current_pinned" ]]; then
  log_info "已经是当前版本: $target"
  exit 0
fi

log_info "回滚到: $target"
exec "$SCRIPT_DIR/run.sh" --ref "$target"
