#!/usr/bin/env bash
# lc-dev-env 公共库：配置加载、运行时探测、镜像摘要解析、版本钉住记录
#
# 由其它脚本 source，不要直接执行。
# 配置优先级：环境变量 > dev-env.conf > 本文件内置默认值

if [[ -n "${__LC_DEV_ENV_LIB_LOADED:-}" ]]; then
  return 0
fi
__LC_DEV_ENV_LIB_LOADED=1

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
ROOT_DIR="${ROOT_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# 可由 dev-env.conf 配置、但环境变量优先级更高的配置项
DEV_ENV_CONFIG_KEYS=(
  REGISTRY IMAGE_NAME IMAGE_TAG CONTAINER_NAME
  HOST_GIT_DIR SSH_PORT WEB_PORT PUBLIC_HOST DSH_HOME_SUBDIR
  STATE_DIR DEV_ENV_CONFIG
)

# 1) 记录调用方通过环境变量传入的值（最高优先级）
__lc_env_overrides=()
for __lc_key in "${DEV_ENV_CONFIG_KEYS[@]}"; do
  if [[ -n "${!__lc_key-}" ]]; then
    __lc_env_overrides+=("${__lc_key}=${!__lc_key}")
  fi
done
unset __lc_key

# 2) 内置默认值：dev-env.conf 缺失时脚本仍可运行
: "${REGISTRY:=crpi-vb458bo8ja2welze.cn-chengdu.personal.cr.aliyuncs.com}"
: "${IMAGE_NAME:=peak2026/lc-dev-env}"
: "${IMAGE_TAG:=latest}"
: "${CONTAINER_NAME:=lc-dev-env}"
: "${HOST_GIT_DIR:=/home/lc/cont_data}"
: "${SSH_PORT:=2228}"
: "${WEB_PORT:=3080}"
: "${PUBLIC_HOST:=}"
: "${DSH_HOME_SUBDIR:=dsh}"
: "${STATE_DIR:=$ROOT_DIR/.state}"
: "${DEV_ENV_CONFIG:=$ROOT_DIR/dev-env.conf}"

# 3) 加载配置文件
if [[ -f "$DEV_ENV_CONFIG" ]]; then
  # shellcheck disable=SC1090
  source "$DEV_ENV_CONFIG"
fi

# 4) 恢复环境变量的优先级
for __lc_kv in "${__lc_env_overrides[@]}"; do
  export "$__lc_kv"
done
unset __lc_kv __lc_env_overrides

# DSH 数据目录：放在数据卷内，容器路径为 /home/data/<DSH_HOME_SUBDIR>
DSH_HOST_DIR="${HOST_GIT_DIR}/${DSH_HOME_SUBDIR}"

# 状态目录统一转为绝对路径，避免不同工作目录下状态分散
case "$STATE_DIR" in
  /*) ;;
  *) STATE_DIR="$(pwd)/$STATE_DIR" ;;
esac

# ---------- 日志 ----------

log_info() { printf '%s\n' "$*"; }
log_ok()   { printf '[ok]   %s\n' "$*"; }
log_warn() { printf '警告: %s\n' "$*" >&2; }
die()      { printf '错误: %s\n' "$*" >&2; exit 1; }

# ---------- 容器运行时 ----------

detect_runtime() {
  if [[ -n "${RUNTIME:-}" ]]; then
    command -v "$RUNTIME" >/dev/null 2>&1 || die "RUNTIME=$RUNTIME 不可用"
    return 0
  fi
  if command -v podman >/dev/null 2>&1; then
    RUNTIME=podman
  elif command -v docker >/dev/null 2>&1; then
    RUNTIME=docker
  else
    die "未找到 podman 或 docker，请先安装其一"
  fi
}

# ---------- 配置校验 ----------

validate_config() {
  [[ -n "$REGISTRY" ]]     || die "REGISTRY 不能为空"
  [[ -n "$IMAGE_NAME" ]]   || die "IMAGE_NAME 不能为空"
  [[ -n "$IMAGE_TAG" ]]    || die "IMAGE_TAG 不能为空"
  [[ -n "$CONTAINER_NAME" ]] || die "CONTAINER_NAME 不能为空"
  [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || die "SSH_PORT 必须是数字: $SSH_PORT"
  (( SSH_PORT >= 1 && SSH_PORT <= 65535 )) || die "SSH_PORT 超出范围: $SSH_PORT"
  [[ "$WEB_PORT" =~ ^[0-9]+$ ]] || die "WEB_PORT 必须是数字: $WEB_PORT"
  (( WEB_PORT >= 1 && WEB_PORT <= 65535 )) || die "WEB_PORT 超出范围: $WEB_PORT"
  [[ "$HOST_GIT_DIR" == /* ]] || die "HOST_GIT_DIR 必须是绝对路径: $HOST_GIT_DIR"
  [[ -n "$DSH_HOME_SUBDIR" ]] || die "DSH_HOME_SUBDIR 不能为空"
  [[ "$DSH_HOME_SUBDIR" != */* ]] || die "DSH_HOME_SUBDIR 不能包含 /: $DSH_HOME_SUBDIR"
}

# ---------- 镜像引用与摘要 ----------

image_repo() { printf '%s/%s' "$REGISTRY" "$IMAGE_NAME"; }

image_exists() {
  [[ -n "${1:-}" ]] && "$RUNTIME" image inspect "$1" >/dev/null 2>&1
}

# 返回仓库摘要引用（repo@sha256:...），本地构建的镜像可能为空
image_repo_digest() {
  local out=""
  out="$("$RUNTIME" image inspect \
    --format '{{if .RepoDigests}}{{index .RepoDigests 0}}{{end}}' "$1" 2>/dev/null || true)"
  out="${out//$'\r'/}"
  out="${out//$'\n'/}"
  printf '%s' "$out"
}

# 返回镜像自身摘要（sha256:...），docker 的 inspect 不支持该字段时为空
image_digest() {
  local out=""
  out="$("$RUNTIME" image inspect --format '{{.Digest}}' "$1" 2>/dev/null || true)"
  out="${out//$'\r'/}"
  out="${out//$'\n'/}"
  printf '%s' "$out"
}

image_id() {
  local out=""
  out="$("$RUNTIME" image inspect --format '{{.Id}}' "$1" 2>/dev/null || true)"
  out="${out//$'\r'/}"
  out="${out//$'\n'/}"
  printf '%s' "$out"
}

# 把任意镜像引用解析为不可变引用：优先 repo@sha256:...，其次镜像 ID
immutable_ref_for() {
  local ref="$1" repo_digest digest id
  repo_digest="$(image_repo_digest "$ref")"
  if [[ -n "$repo_digest" ]]; then
    printf '%s' "$repo_digest"
    return 0
  fi
  digest="$(image_digest "$ref")"
  if [[ -n "$digest" ]]; then
    printf '%s@%s' "$(image_repo)" "$digest"
    return 0
  fi
  id="$(image_id "$ref")"
  if [[ -n "$id" ]]; then
    printf '%s' "$id"
    return 0
  fi
  printf '%s' "$ref"
}

# ---------- 仓库登录（凭据仅从环境变量读取，不落盘） ----------

registry_login() {
  if [[ -n "${ALIYUN_ACR_USERNAME:-}" && -n "${ALIYUN_ACR_PASSWORD:-}" ]]; then
    if printf '%s' "$ALIYUN_ACR_PASSWORD" \
        | "$RUNTIME" login "$REGISTRY" -u "$ALIYUN_ACR_USERNAME" --password-stdin >/dev/null 2>&1; then
      __lc_logged_in=1
    else
      log_warn "ACR 登录失败，继续尝试拉取（可能已有本地凭据）"
    fi
  fi
  return 0
}

registry_logout() {
  if [[ "${__lc_logged_in:-0}" -eq 1 ]]; then
    "$RUNTIME" logout "$REGISTRY" >/dev/null 2>&1 || true
    __lc_logged_in=0
  fi
  return 0
}

# 拉取镜像，成功返回 0
pull_image() {
  local ref="$1" rc=0
  registry_login
  "$RUNTIME" pull "$ref" >&2 || rc=1
  registry_logout
  return "$rc"
}

# ---------- 版本钉住状态 ----------
#
# current.tsv / history.tsv 的列：时间 来源引用 钉住引用 标签
#   来源引用：本次实际拉取/使用的引用（如 repo:latest）
#   钉住引用：不可变引用（repo@sha256:... 或镜像 ID），下次默认直接复用

state_init() {
  mkdir -p "$STATE_DIR" || die "无法创建状态目录: $STATE_DIR"
  [[ -f "$STATE_DIR/history.tsv" ]] || : > "$STATE_DIR/history.tsv"
}

state_current_field() {
  local field="$1"
  if [[ -f "$STATE_DIR/current.tsv" ]]; then
    cut -f"$field" "$STATE_DIR/current.tsv"
  fi
}

state_current_pinned() { state_current_field 3; }

state_pin() {
  local ref="$1" pinned="$2" tag="$3"
  local ts last=""
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$STATE_DIR"
  printf '%s\t%s\t%s\t%s\n' "$ts" "$ref" "$pinned" "$tag" > "$STATE_DIR/current.tsv"

  if [[ -s "$STATE_DIR/history.tsv" ]]; then
    last="$(tail -n 1 "$STATE_DIR/history.tsv" | cut -f3)"
  fi
  if [[ "$pinned" != "$last" ]]; then
    printf '%s\t%s\t%s\t%s\n' "$ts" "$ref" "$pinned" "$tag" >> "$STATE_DIR/history.tsv"
    if [[ "$(wc -l < "$STATE_DIR/history.tsv")" -gt 50 ]]; then
      tail -n 50 "$STATE_DIR/history.tsv" > "$STATE_DIR/history.tsv.tmp" \
        && mv "$STATE_DIR/history.tsv.tmp" "$STATE_DIR/history.tsv"
    fi
  fi
}
