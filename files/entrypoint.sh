#!/usr/bin/env bash
# 容器入口：启动 sshd，并以守护方式运行 dsh web（DeepSeek Harness Web GUI）。
# 可通过环境变量调整：DSH_WEB_PORT / DSH_WEB_HOST / DSH_WEB_PUBLIC_URL /
# DSH_WEB_TRUSTED_HOSTS / DSH_ENABLE_WEB / DSH_HOME。
set -euo pipefail

log() { printf '[entrypoint] %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

DSH_HOME_PATH="${DSH_HOME:-/home/data/dsh}"
WEB_PORT="${DSH_WEB_PORT:-3080}"
WEB_HOST="${DSH_WEB_HOST:-}"
PUBLIC_URL="${DSH_WEB_PUBLIC_URL:-}"
TRUSTED_HOSTS="${DSH_WEB_TRUSTED_HOSTS:-}"
ENABLE_WEB="${DSH_ENABLE_WEB:-1}"
LOG_FILE="${DSH_WEB_LOG:-/var/log/dsh-web.log}"
URL_FILE="${DSH_WEB_URL_FILE:-$DSH_HOME_PATH/web-url.txt}"

export DSH_HOME="$DSH_HOME_PATH"
mkdir -p "$DSH_HOME_PATH" "$(dirname "$LOG_FILE")"

# 收到 docker/podman stop 时把信号转给子进程（dsh、tee、sleep）
cleanup() {
  trap - TERM INT
  log "收到终止信号，停止子进程"
  kill 0 2>/dev/null || true
  exit 0
}
trap cleanup TERM INT

ssh-keygen -A
if ! service ssh start; then
  log "sshd 启动失败，继续启动 dsh web"
fi

if [[ "$ENABLE_WEB" != "1" ]]; then
  log "DSH_ENABLE_WEB=$ENABLE_WEB，不启动 dsh web"
  exec sleep infinity
fi

# dsh 拒绝通配监听地址，默认绑定容器自己的 IPv4
if [[ -z "$WEB_HOST" ]]; then
  WEB_HOST="$(hostname -i 2>/dev/null | tr ' ' '\n' | grep -m1 -E '^[0-9]+(\.[0-9]+){3}$' || true)"
  if [[ -z "$WEB_HOST" ]]; then
    log "未获取到容器 IPv4，回退监听 127.0.0.1"
    WEB_HOST=127.0.0.1
  fi
fi

dsh_args=(web --no-open --host "$WEB_HOST" --port "$WEB_PORT")
[[ -n "$PUBLIC_URL" ]] && dsh_args+=(--public-url "$PUBLIC_URL")
if [[ -n "$TRUSTED_HOSTS" ]]; then
  for host in $TRUSTED_HOSTS; do
    dsh_args+=(--trusted-host "$host")
  done
fi

if ! command -v dsh >/dev/null 2>&1; then
  log "未找到 dsh，跳过 Web GUI（请检查镜像构建）"
  exec sleep infinity
fi

log "dsh 版本: $(dsh --version 2>/dev/null || echo 未知)"
log "启动 dsh web: host=$WEB_HOST port=$WEB_PORT public=${PUBLIC_URL:-<未设置>}"

umask 077
while true; do
  : > "$LOG_FILE"
  dsh "${dsh_args[@]}" 2>&1 | tee -a "$LOG_FILE" &
  pipe_pid=$!

  # 提取带 token 的 URL，写到 DSH_HOME 供宿主机 scripts/web-url.sh 读取
  url=""
  for _ in $(seq 1 120); do
    if ! kill -0 "$pipe_pid" 2>/dev/null; then
      break
    fi
    url="$(grep -m1 '^dsh web: http' "$LOG_FILE" 2>/dev/null || true)"
    [[ -n "$url" ]] && break
    sleep 0.5
  done
  if [[ -n "$url" ]]; then
    printf '%s\n' "${url#dsh web: }" > "$URL_FILE"
    log "Web GUI 已就绪: ${url#dsh web: }"
  fi

  rc=0
  wait "$pipe_pid" || rc=$?
  log "dsh web 退出（code=$rc），2 秒后重启"
  sleep 2
done
