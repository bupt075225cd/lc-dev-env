#!/usr/bin/env bash
# 冒烟测试：验证镜像“能跑”且工具链可用。
#
# 做法：启动一个临时容器，通过 SSH 登录后逐项检查工具链版本、环境变量、
# 挂载可见性、sshd 配置与容器存活状态。CI 与本地均可直接运行。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
用法: smoke-test.sh [镜像引用] [选项]

在临时容器中启动镜像，通过 SSH 登录验证工具链与运行状态。

镜像引用默认取已钉住版本（.state），没有记录时取 <registry>/<image>:<tag>。

选项:
      --no-pull       不拉取镜像（本地必须已有）
      --force-pull    强制从仓库重新拉取
      --port <端口>   指定宿主机端口（默认自动分配）
      --name <名称>   测试容器名（默认 <CONTAINER_NAME>-smoke）
      --keep          保留测试容器与临时目录（排障用）
  -h, --help          显示帮助

环境变量:
  EXPECTED_GO_VERSION / EXPECTED_NODE_VERSION  覆盖预期版本（默认从 Dockerfile 读取）
  SSH_PASSWORD                                 容器 root 密码（默认 123456）

示例:
  scripts/smoke-test.sh
  scripts/smoke-test.sh previous
  scripts/smoke-test.sh repo@sha256:...
EOF
}

REF=""
NO_PULL=0
FORCE_PULL=0
KEEP=0
SMOKE_PORT=""
SMOKE_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-pull)    NO_PULL=1; shift ;;
    --force-pull) FORCE_PULL=1; shift ;;
    --keep)       KEEP=1; shift ;;
    --port)
      [[ $# -ge 2 ]] || die "--port 需要一个端口号"
      SMOKE_PORT="$2"; shift 2 ;;
    --name)
      [[ $# -ge 2 ]] || die "--name 需要一个容器名"
      SMOKE_NAME="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) die "未知参数: $1（-h 查看用法）" ;;
    *)
      if [[ -n "$REF" ]]; then
        die "只能指定一个镜像引用"
      fi
      REF="$1"; shift ;;
  esac
done

detect_runtime
validate_config
state_init

if [[ -n "$SMOKE_PORT" ]]; then
  [[ "$SMOKE_PORT" =~ ^[0-9]+$ ]] || die "--port 必须是数字: $SMOKE_PORT"
  (( SMOKE_PORT >= 1 && SMOKE_PORT <= 65535 )) || die "--port 超出范围: $SMOKE_PORT"
fi

if [[ -z "$REF" ]]; then
  REF="$(state_current_pinned)"
  if [[ -z "$REF" ]]; then
    REF="$(image_repo):${IMAGE_TAG}"
  fi
fi
[[ -n "$SMOKE_NAME" ]] || SMOKE_NAME="${CONTAINER_NAME}-smoke"

# 预期版本：优先环境变量，其次 Dockerfile 中的 ARG
EXPECTED_GO="${EXPECTED_GO_VERSION:-}"
EXPECTED_NODE="${EXPECTED_NODE_VERSION:-}"
if [[ -z "$EXPECTED_GO" && -f "$ROOT_DIR/Dockerfile" ]]; then
  EXPECTED_GO="$(sed -n 's/^ARG GO_VERSION=//p' "$ROOT_DIR/Dockerfile" | head -n 1)"
fi
if [[ -z "$EXPECTED_NODE" && -f "$ROOT_DIR/Dockerfile" ]]; then
  EXPECTED_NODE="$(sed -n 's/^ARG NODE_VERSION=//p' "$ROOT_DIR/Dockerfile" | head -n 1)"
fi

# 镜像准备
if image_exists "$REF"; then
  if [[ $FORCE_PULL -eq 1 ]]; then
    log_info "强制拉取镜像: $REF"
    pull_image "$REF" || die "拉取镜像失败: $REF"
  else
    log_info "使用本地镜像: $REF"
  fi
else
  if [[ $NO_PULL -eq 1 ]]; then
    die "本地没有镜像 $REF（运行时: $RUNTIME，--no-pull 时不会拉取）"
  fi
  log_info "拉取镜像: $REF"
  pull_image "$REF" || die "拉取镜像失败: $REF"
fi

TMP_DIR="$(mktemp -d)"
SSH_KEY="$TMP_DIR/id_ed25519"
HOST_PORT=""
PASS=0
FAIL=0

cleanup() {
  local rc=$?
  if [[ $KEEP -eq 1 ]]; then
    log_warn "已保留测试容器 $SMOKE_NAME 与临时目录 $TMP_DIR"
  else
    "$RUNTIME" rm -f "$SMOKE_NAME" >/dev/null 2>&1 || true
    rm -rf "$TMP_DIR"
  fi
  exit "$rc"
}
trap cleanup EXIT

# 启动临时容器
"$RUNTIME" rm -f "$SMOKE_NAME" >/dev/null 2>&1 || true
mkdir -p "$TMP_DIR/mnt"
printf 'smoke-host-ok\n' > "$TMP_DIR/mnt/host-check.txt"

if [[ -n "$SMOKE_PORT" ]]; then
  port_args=(-p "127.0.0.1:${SMOKE_PORT}:22")
else
  port_args=(-p "127.0.0.1::22")
fi

log_info "启动测试容器: $SMOKE_NAME"
if ! "$RUNTIME" run -d --name "$SMOKE_NAME" \
      --cap-add AUDIT_WRITE \
      "${port_args[@]}" \
      -v "$TMP_DIR/mnt:/home/data:Z" \
      "$REF" >/dev/null; then
  die "容器启动失败: $REF"
fi

container_running() {
  [[ "$("$RUNTIME" inspect --format '{{.State.Running}}' "$SMOKE_NAME" 2>/dev/null || true)" == "true" ]]
}

dump_logs() {
  printf '%s\n' '--- 容器日志（末尾 40 行）---' >&2
  "$RUNTIME" logs "$SMOKE_NAME" 2>&1 | tail -n 40 >&2 || true
}

if [[ -n "$SMOKE_PORT" ]]; then
  HOST_PORT="$SMOKE_PORT"
else
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    HOST_PORT="$("$RUNTIME" port "$SMOKE_NAME" 22/tcp 2>/dev/null | head -n 1 | sed 's/.*://' || true)"
    if [[ -n "$HOST_PORT" ]]; then
      break
    fi
    sleep 1
  done
fi
if [[ -z "$HOST_PORT" ]]; then
  dump_logs
  die "无法获取 22 端口的宿主机映射"
fi

# 等待 sshd 监听
wait_for_port() {
  local deadline=$((SECONDS + 90))
  while (( SECONDS < deadline )); do
    if (exec 3<>"/dev/tcp/127.0.0.1/${HOST_PORT}") 2>/dev/null; then
      return 0
    fi
    if ! container_running; then
      return 1
    fi
    sleep 1
  done
  return 1
}

if ! wait_for_port; then
  dump_logs
  die "等待 SSH 端口超时（127.0.0.1:${HOST_PORT}）"
fi

# SSH 登录方式：用镜像文档里的 root 密码登录（验证 PermitRootLogin / PasswordAuthentication
# 与 PAM 配置），没有 ssh 客户端时退化为 exec 执行检查。
SSH_MODE=1
if ! command -v ssh >/dev/null 2>&1; then
  SSH_MODE=0
  log_warn "未找到 ssh 客户端，改用 exec 执行检查（跳过 SSH 登录校验）"
fi

SSH_PASSWORD="${SSH_PASSWORD:-123456}"
ASKPASS_SCRIPT="$TMP_DIR/askpass.sh"

ssh_run() {
  local cmd="$1"
  local ssh_args=(
    -p "$HOST_PORT"
    -o PreferredAuthentications=password
    -o PubkeyAuthentication=no
    -o NumberOfPasswordPrompts=1
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
    -o ConnectTimeout=15
    root@127.0.0.1 "$cmd"
  )
  # setsid 脱离终端，保证 ssh 走 SSH_ASKPASS（本地有 TTY 时也能非交互登录）
  if command -v setsid >/dev/null 2>&1; then
    SSH_ASKPASS="$ASKPASS_SCRIPT" SSH_ASKPASS_REQUIRE=force DISPLAY=:0 \
      setsid -w ssh "${ssh_args[@]}"
  else
    SSH_ASKPASS="$ASKPASS_SCRIPT" SSH_ASKPASS_REQUIRE=force DISPLAY=:0 \
      ssh "${ssh_args[@]}"
  fi
}

if [[ $SSH_MODE -eq 1 ]]; then
  cat > "$ASKPASS_SCRIPT" <<EOF
#!/bin/sh
printf '%s\\n' '$SSH_PASSWORD'
EOF
  chmod +x "$ASKPASS_SCRIPT"

  ssh_ready=0
  ssh_err=""
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if ssh_err="$(ssh_run true 2>&1)"; then
      ssh_ready=1
      break
    fi
    sleep 1
  done
  if [[ $ssh_ready -ne 1 ]]; then
    printf '%s\n' '--- ssh 客户端输出 ---' "$ssh_err" >&2
    "$RUNTIME" exec "$SMOKE_NAME" sh -c \
      "sshd -T 2>/dev/null | grep -iE '^(permitrootlogin|passwordauthentication|pubkeyauthentication|usepam|kbdinteractiveauthentication)'" >&2 || true
    dump_logs
    die "SSH 登录失败（root@127.0.0.1:${HOST_PORT}，密码登录）"
  fi
fi

remote() {
  if [[ $SSH_MODE -eq 1 ]]; then
    ssh_run "$1"
  else
    "$RUNTIME" exec "$SMOKE_NAME" sh -c "$1"
  fi
}

check() {
  local desc="$1" cmd="$2" out
  if out="$(remote "$cmd" 2>&1)"; then
    PASS=$((PASS + 1))
    printf '  [ok]   %s\n' "$desc"
  else
    FAIL=$((FAIL + 1))
    printf '  [FAIL] %s\n' "$desc"
    printf '         %s\n' "$(printf '%s' "$out" | tail -n 3 | tr '\n' ' ')"
  fi
}

log_info ""
log_info "镜像:   $REF"
log_info "容器:   $SMOKE_NAME"
log_info "登录:   127.0.0.1:${HOST_PORT}（$([[ $SSH_MODE -eq 1 ]] && echo ssh || echo exec)）"
log_info ""
log_info "工具链:"

if [[ -n "$EXPECTED_GO" ]]; then
  check "Go ${EXPECTED_GO}" "go version | grep -q 'go${EXPECTED_GO}'"
else
  check "Go 可用" 'go version'
fi
if [[ -n "$EXPECTED_NODE" ]]; then
  check "Node.js v${EXPECTED_NODE}" "node -v | grep -q '^v${EXPECTED_NODE}'"
else
  check "Node.js 可用" 'node -v'
fi
check "npm 可用"            'npm -v'
check "pnpm 可用"           'pnpm -v'
check "Python3 可用"        'python3 --version'
check "pip 可用"            'python3 -m pip --version'
check "g++ 可用"            'g++ --version'
check "make 可用"           'make --version'
check "cmake 可用"          'cmake --version'
check "git 可用"            'git --version'
check "dsh 可用"            'dsh --version'

log_info ""
log_info "开发配置:"
check "GOPROXY 指向国内代理"  'printf "%s" "$GOPROXY" | grep -q goproxy\.cn'
check "git 全局身份已配置"    'test -n "$(git config --global user.name)" && test -n "$(git config --global user.email)"'
check "UTF-8 语言环境"        'printf "%s" "$LANG" | grep -qi utf-8'
check "时区为 Asia/Shanghai"  'test "$(date +%Z)" = "CST"'
check "git 分支提示符已启用"  'grep -q __git_ps1 /root/.bashrc && test -f /root/git-prompt.sh'
check "PATH 包含 Go/Node"     'printf "%s" "$PATH" | grep -q /usr/local/go/bin && printf "%s" "$PATH" | grep -q /usr/local/bin'

log_info ""
log_info "运行状态:"
check "工作目录 /home/data 可写"       'touch /home/data/.smoke-write && rm -f /home/data/.smoke-write'
check "宿主机挂载内容可见"             'grep -q smoke-host-ok /home/data/host-check.txt'
check "sshd 允许 root 登录（配置）"    'sshd -T 2>/dev/null | grep -qi "^permitrootlogin yes"'

# dsh web 由容器入口自动启动；URL 文件出现即说明 web 已就绪
dsh_ready=0
for _ in $(seq 1 60); do
  if "$RUNTIME" exec "$SMOKE_NAME" sh -c 'grep -q "token=" /home/data/dsh/web-url.txt' >/dev/null 2>&1; then
    dsh_ready=1
    break
  fi
  sleep 1
done
if [[ $dsh_ready -eq 1 ]]; then
  PASS=$((PASS + 1))
  printf '  [ok]   dsh web 已自动启动\n'
else
  FAIL=$((FAIL + 1))
  printf '  [FAIL] dsh web 未在 60 秒内就绪\n'
fi

if ! container_running; then
  dump_logs
  FAIL=$((FAIL + 1))
  printf '  [FAIL] 容器在测试过程中退出\n'
fi

log_info ""
if (( FAIL > 0 )); then
  log_warn "冒烟测试失败：通过 $PASS 项，失败 $FAIL 项（镜像 $REF）"
  exit 1
fi
log_info "冒烟测试通过：$PASS 项检查全部通过（镜像 $REF）"
if [[ $KEEP -eq 1 ]]; then
  log_info "测试容器保留为 $SMOKE_NAME，可执行：$RUNTIME exec -it $SMOKE_NAME bash"
fi
