#!/usr/bin/env bash
# 后台运行开发容器。
#
# 默认行为：复用上一次钉住的镜像摘要（digest），不会因为 tag 指向变化而漂移。
#   - 首次运行：拉取 IMAGE_TAG，记录其 digest 并钉住
#   - 后续运行：直接复用钉住的 digest（本地没有时才按 digest 拉取）
#   - 升级：scripts/run.sh --update
#   - 回滚：scripts/rollback.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
用法: run.sh [选项]

启动（或重建）开发容器。默认复用已钉住的镜像版本，不随 tag 变动而漂移。

选项:
  -t, --tag <tag>     指定镜像 tag（首次安装或显式切换版本通道）
      --ref <ref>     直接指定完整镜像引用（repo:tag 或 repo@sha256:...）
  -n, --name <name>   容器名（默认取 dev-env.conf 的 CONTAINER_NAME）
  -u, --update        重新拉取当前 tag 并更新钉住的版本
      --no-pull       不拉取镜像，只使用本地已有镜像
  -h, --help          显示帮助

环境变量: 见 dev-env.conf，例如 IMAGE_TAG、CONTAINER_NAME、HOST_GIT_DIR、SSH_PORT
          也支持 IMAGE_DIGEST=sha256:... 直接钉住某个摘要

示例:
  scripts/run.sh                   # 首次安装，或复用已钉住版本
  scripts/run.sh --update          # 升级到当前 tag 的最新版本
  scripts/run.sh --tag v1.2.0      # 切换并钉住到 v1.2.0
  scripts/rollback.sh --list       # 查看可回滚版本
EOF
}

UPDATE=0
NO_PULL=0
TAG_EXPLICIT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--tag)
      [[ $# -ge 2 ]] || die "--tag 需要一个 tag 值"
      IMAGE_TAG="$2"; TAG_EXPLICIT=1; shift 2 ;;
    --ref)
      [[ $# -ge 2 ]] || die "--ref 需要一个镜像引用"
      IMAGE_REF="$2"; shift 2 ;;
    -n|--name)
      [[ $# -ge 2 ]] || die "--name 需要一个容器名"
      CONTAINER_NAME="$2"; shift 2 ;;
    -u|--update) UPDATE=1; shift ;;
    --no-pull)   NO_PULL=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) die "未知参数: $1（-h 查看用法）" ;;
  esac
done

detect_runtime
validate_config
state_init

repo="$(image_repo)"

# 决定本次使用哪个引用：显式引用 > 指定摘要 > 已钉住版本 > tag
ref=""
mode=""
if [[ -n "${IMAGE_REF:-}" ]]; then
  ref="$IMAGE_REF"
  mode="指定引用"
elif [[ -n "${IMAGE_DIGEST:-}" ]]; then
  ref="${repo}@${IMAGE_DIGEST}"
  mode="指定摘要"
elif [[ $UPDATE -eq 0 && $TAG_EXPLICIT -eq 0 ]]; then
  pinned="$(state_current_pinned)"
  if [[ -n "$pinned" ]]; then
    ref="$pinned"
    mode="已钉住版本"
  fi
fi
if [[ -z "$ref" ]]; then
  ref="${repo}:${IMAGE_TAG}"
  mode="标签 ${IMAGE_TAG}"
fi

# 是否需要拉取：digest 引用本地已有时不拉；tag 引用在 --update/--tag 时强制刷新
pull_needed=0
if [[ $NO_PULL -eq 1 ]]; then
  if ! image_exists "$ref"; then
    die "本地没有镜像 $ref（--no-pull 不允许拉取）"
  fi
elif image_exists "$ref"; then
  if [[ "$ref" != *@sha256:* ]] && { [[ $UPDATE -eq 1 ]] || [[ $TAG_EXPLICIT -eq 1 ]]; }; then
    pull_needed=1
  fi
else
  pull_needed=1
fi

if [[ $pull_needed -eq 1 ]]; then
  log_info "拉取镜像: $ref"
  if ! pull_image "$ref"; then
    if image_exists "$ref"; then
      log_warn "拉取失败，回退使用本地镜像 $ref"
    else
      die "拉取镜像失败且本地无可用镜像: $ref"
    fi
  fi
else
  log_info "复用本地镜像: $ref"
fi

# 记录不可变引用，作为下次运行的默认版本
pinned_ref="$(immutable_ref_for "$ref")"
[[ -n "$pinned_ref" ]] || pinned_ref="$ref"

tag_for_state="$IMAGE_TAG"
case "$ref" in
  "${repo}:"*) tag_for_state="${ref#"${repo}:"}" ;;
esac

# 重建同名容器
mkdir -p "$HOST_GIT_DIR" || die "无法创建宿主机目录: $HOST_GIT_DIR"
mkdir -p "$DSH_HOME_DIR" || die "无法创建 DSH 数据目录: $DSH_HOME_DIR"
rm -f "${DSH_HOME_DIR}/web-url.txt"

# 浏览器访问地址：优先 PUBLIC_HOST，否则取默认路由的源地址（Windows 客户端用）
web_host="${PUBLIC_HOST}"
if [[ -z "$web_host" ]]; then
  web_host="$(ip route get 1.1.1.1 2>/dev/null \
    | awk '{ for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }' || true)"
fi
if [[ -z "$web_host" ]]; then
  web_host="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
fi
[[ -n "$web_host" ]] || die "无法自动检测服务器 IP，请在 dev-env.conf 设置 PUBLIC_HOST"
web_public_url="${DSH_WEB_PUBLIC_URL:-http://${web_host}:${WEB_PORT}}"
web_trusted_hosts="${DSH_WEB_TRUSTED_HOSTS:-${web_host}:${WEB_PORT}}"

run_env=(
  -e "DSH_WEB_PORT=3080"
  -e "DSH_WEB_PUBLIC_URL=${web_public_url}"
  -e "DSH_WEB_TRUSTED_HOSTS=${web_trusted_hosts}"
)
[[ -n "${DEEPSEEK_API_KEY:-}" ]] && run_env+=(-e "DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY}")
[[ -n "${DSH_WEB_HOST:-}" ]] && run_env+=(-e "DSH_WEB_HOST=${DSH_WEB_HOST}")
[[ -n "${DSH_ENABLE_WEB:-}" ]] && run_env+=(-e "DSH_ENABLE_WEB=${DSH_ENABLE_WEB}")

if "$RUNTIME" container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  log_info "清理同名旧容器: $CONTAINER_NAME"
  "$RUNTIME" stop -t 2 "$CONTAINER_NAME" >/dev/null 2>&1 || true
  "$RUNTIME" rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
fi

log_info "启动容器: $CONTAINER_NAME（$RUNTIME）"
"$RUNTIME" run -d --name "$CONTAINER_NAME" \
  --restart=unless-stopped \
  --cap-add AUDIT_WRITE \
  -p "${SSH_PORT}:22" \
  -p "${WEB_PORT}:3080" \
  -v "${HOST_GIT_DIR}:/home/git:Z" \
  -v "${DSH_HOME_DIR}:/root/.dsh:Z" \
  "${run_env[@]}" \
  "$ref" >/dev/null

# 容器启动成功后才钉住版本，启动失败时保持上一次的钉住记录
state_pin "$ref" "$pinned_ref" "$tag_for_state"

# 等 dsh web 打印带 token 的 URL（超时不算失败，后续可用 scripts/web-url.sh 查看）
web_url=""
if [[ "${DSH_ENABLE_WEB:-1}" != "0" ]]; then
  for _ in $(seq 1 30); do
    if [[ -s "${DSH_HOME_DIR}/web-url.txt" ]]; then
      web_url="$(cat "${DSH_HOME_DIR}/web-url.txt")"
      break
    fi
    sleep 1
  done
fi

cat <<EOF

容器已启动: $CONTAINER_NAME
运行时:     $RUNTIME
镜像引用:   $ref（$mode）
版本钉住:   $pinned_ref
挂载:       $HOST_GIT_DIR -> /home/git
SSH:        ssh -p ${SSH_PORT} root@127.0.0.1  (密码 123456)
Web GUI:    ${web_url:-（尚未就绪，执行 scripts/web-url.sh 查看）}
DSH 数据:   ${DSH_HOME_DIR} -> /root/.dsh
进入容器:   scripts/enter.sh
升级版本:   scripts/run.sh --update
查看历史:   scripts/rollback.sh --list

提示: 后续运行默认复用已钉住的版本；tag 指向变化不会影响本机环境。
EOF
