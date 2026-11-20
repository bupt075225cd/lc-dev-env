# lc-dev-env

基于 Ubuntu 的通用开发环境容器镜像，预装 Go / Python / Node.js / g++ 等工具链。

> 镜像由 GitHub Actions CI 构建、冒烟测试后发布到阿里云 ACR；本机脚本统一从 ACR 拉取启动，并按
> 镜像摘要（digest）钉住版本，保证本地环境可复现、可升级、可回滚。

## 镜像包含的工具链

| 工具 | 版本 | 安装方式 |
|------|------|---------|
| Go | 1.27.4 | 官方二进制 |
| Python | 3.14.4 | apt（系统默认） |
| Node.js | 26.13.1（npm 11.20.0） | 官方二进制 |
| g++ / GCC | 15.2.0 | apt（系统默认） |
| git | 2.53.0 | apt（系统默认） |

- Go 模块代理：`https://goproxy.cn,direct`
- Git 身份：`Liu Cong <nonpvirvatemail@163.com>`
- SSH 服务：容器内 22 端口，`root` 密码 `123456`（见文末安全提示）

## 目录结构

```
lc-dev-env/
├── .github/
│   └── workflows/
│       └── ci.yml          # 构建 -> 冒烟测试 -> 发布 ACR -> 按 digest 复验
├── Dockerfile              # 开发环境镜像（构建源参数化）
├── dev-env.conf            # 默认配置（镜像仓库/容器名/端口/挂载）
├── scripts/
│   ├── lib.sh              # 公共库：配置加载、运行时探测、版本钉住
│   ├── build.sh            # 本机构建镜像（内网/阿里云源，本地测试用）
│   ├── run.sh              # 拉取并钉住镜像，后台运行容器
│   ├── rollback.sh         # 查看历史版本并回滚
│   ├── smoke-test.sh       # 冒烟测试：SSH 登录校验工具链/挂载/sshd
│   └── enter.sh            # 进入容器
├── .dockerignore
└── README.md
```

## 快速开始

### 1. 运行容器

```bash
scripts/run.sh
```

首次运行会从 ACR 拉取 `IMAGE_TAG`（默认 `latest`），**记录并钉住其 digest**；之后每次运行都复用该
digest，不再受 `latest` 指向变化影响，因此本机环境是确定的。

> ACR 登录：首次运行前需登录一次，或用环境变量提供凭据（脚本会自动登录并在拉取后登出）：
> ```bash
> podman login crpi-vb458bo8ja2welze.cn-chengdu.personal.cr.aliyuncs.com
> # 或
> export ALIYUN_ACR_USERNAME=xxx ALIYUN_ACR_PASSWORD=xxx
> ```
>
> 挂载说明：宿主机 `/home/lc/git` 挂载到容器 `/home/git`，目录不存在时自动创建。
> `:Z` 用于 SELinux 环境重打标签，非 SELinux 环境无副作用。

### 2. 进入容器

```bash
scripts/enter.sh                      # 交互式 bash
scripts/enter.sh go version           # 在容器内执行命令
scripts/enter.sh -n other-env         # 指定容器名
# 或
podman exec -it lc-dev-env bash       # 容器名见 dev-env.conf 的 CONTAINER_NAME
```

### 3. 升级到新版本

```bash
scripts/run.sh --update        # 重新拉取当前 tag 并钉住新 digest
scripts/run.sh --tag v1.2.0    # 切换到指定 tag 并钉住
```

### 4. 回滚

```bash
scripts/rollback.sh --list     # 列出可回滚版本（1 = 最新）
scripts/rollback.sh 2          # 回滚到序号 2 的版本
scripts/rollback.sh v1.2.0     # 回滚到某个 tag
scripts/rollback.sh sha256:1f2e3d...   # 按镜像摘要回滚
```

也可以直接钉住 CI 输出的摘要运行：

```bash
IMAGE_DIGEST=sha256:1f2e3d... scripts/run.sh
```

### 5. 冒烟测试

```bash
scripts/smoke-test.sh                    # 测试当前钉住的版本
scripts/smoke-test.sh sha-<完整 git sha>  # 测试仓库中的某个版本
scripts/smoke-test.sh --keep             # 保留测试容器，便于排查
```

脚本会启动临时容器、通过 SSH 登录并检查：Go/Node/npm/pnpm/Python/g++/make/cmake/git 可用性与版本、
GOPROXY/时区/locale/git 身份/git 提示符、`/home/git` 挂载读写、sshd 配置与容器存活状态。

### 6. 本机构建镜像（本地验证 Dockerfile）

```bash
scripts/build.sh
```

## 配置

配置优先级：**环境变量 > `dev-env.conf` > 脚本内置默认值**。

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `REGISTRY` | `crpi-vb458bo8ja2welze.cn-chengdu.personal.cr.aliyuncs.com` | 镜像仓库 |
| `IMAGE_NAME` | `peak2026/lc-dev-env` | 镜像名 |
| `IMAGE_TAG` | `latest` | 首次安装/`--update` 使用的 tag |
| `CONTAINER_NAME` | `lc-dev-env` | 容器名，run/enter/rollback/smoke-test 共用 |
| `HOST_GIT_DIR` | `/home/lc/git` | 挂载到容器 `/home/git` 的宿主机目录 |
| `SSH_PORT` | `2228` | 宿主机 SSH 端口 -> 容器 22 |
| `STATE_DIR` | `$ROOT_DIR/.state` | 版本钉住与回滚记录目录 |

修改容器名只需改一处（`dev-env.conf`），所有脚本自动生效；也可临时覆盖：

```bash
CONTAINER_NAME=my-env scripts/run.sh
CONTAINER_NAME=my-env scripts/enter.sh
```

`dev-env.conf` 会提交到仓库，**不要写入密码等凭据**；ACR 凭据请用环境变量。

## 版本钉住与回滚机制

- `STATE_DIR/current.tsv`：当前版本（时间、来源引用、钉住引用、tag）。
- `STATE_DIR/history.tsv`：最近 50 条版本记录，`rollback.sh --list` 按此列出。
- 钉住的引用是 `repo@sha256:...`（本地构建且无仓库摘要时退化为镜像 ID），因此回滚目标不可变。
- 每次运行 `run.sh` 时若 digest 与上一条不同才追加历史，避免重复记录。

## CI/CD

`.github/workflows/ci.yml`：

1. **build-and-test**（push 到 `main`、打 `v*` tag、对 `main` 的 PR 均触发）
   - 构建镜像并 `load` 到本地；
   - **冒烟测试**（同 `scripts/smoke-test.sh`）通过后才允许推送；
   - 登录 ACR 推送全部标签，并校验所有标签指向同一摘要；
   - 输出摘要与仓库地址，写入 Job Summary。
2. **verify-published**（仅 push/tag 且发布成功时）
   - 从 ACR 按 **digest** 重新拉取并再跑一遍冒烟测试，验证仓库里的产物本身可用。

| 触发 | 生成的标签 |
|------|-----------|
| push 到 `main` | `latest`、`sha-<完整 git sha>`、`main` |
| 打 `v1.2.3` tag | `1.2.3`、`sha-<完整 git sha>` |

发布地址：`crpi-vb458bo8ja2welze.cn-chengdu.personal.cr.aliyuncs.com/peak2026/lc-dev-env`

需要配置的 GitHub Secrets：

- `ALIYUN_ACR_USERNAME`：阿里云 ACR 登录用户名
- `ALIYUN_ACR_PASSWORD`：阿里云 ACR 登录密码

## 构建源说明

Dockerfile 的构建源已参数化，默认使用公共源（供 GitHub Actions CI 使用），本机构建通过 `build.sh` 自动传入内网 / 阿里云镜像参数：

| 参数 | 默认（CI / 公共源） | 本机（build.sh） |
|------|---------------------|------------------|
| BASE_IMAGE | `docker.io/library/ubuntu:latest` | `swr.cn-north-4...` |
| GO_DL_BASE | `https://go.dev/dl` | `https://mirrors.aliyun.com/golang` |
| NODE_DL_BASE | `https://nodejs.org/dist` | `https://mirrors.aliyun.com/nodejs-release` |

## 说明与已知限制

- 脚本兼容 `podman` 与 `docker`（自动检测，优先 podman，可用 `RUNTIME` 强制指定）。
- 容器以 root 运行，后台常驻（`sleep infinity`），重启策略 `unless-stopped`。
- 基础镜像来自内部 SWR 源（目标机无法直连 Docker Hub），CI 环境使用公共源。
- SSH 会话通过 `SetEnv` 注入 `PATH`/`GOPROXY`/`TZ`/`LANG`（sshd 不继承镜像 ENV），
  `/etc/profile.d/dev-env.sh` 兜底登录 shell。
- 安全提示：`root` 密码固定为 `123456` 且端口映射默认监听所有网卡；请只在可信网络使用，
  或自行改为 SSH key 登录（`-p 127.0.0.1:${SSH_PORT}:22` 可限制仅本机访问）。
- 目前只构建 `linux/amd64` 单架构镜像。
