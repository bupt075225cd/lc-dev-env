# lc-dev-env

基于 Ubuntu 的通用开发环境容器镜像，预装 Go / Python / Node.js / g++ 等工具链。

> 镜像由 GitHub Actions CI 构建、冒烟测试后发布到阿里云 ACR；本机脚本统一从 ACR 拉取启动，并按
> 镜像摘要（digest）钉住版本，保证本地环境可复现、可升级、可回滚。
> 镜像内置 DeepSeek Harness（`dsh`），容器启动后自动运行 `dsh web`，Windows 客户端用浏览器访问。

## 镜像包含的工具链

| 工具 | 版本 | 安装方式 |
|------|------|---------|
| Go | 1.27.4 | 官方二进制 |
| Python | 3.14.4 | apt（系统默认） |
| Node.js | 26.13.1（npm 11.20.0） | 官方二进制 |
| g++ / GCC | 15.2.0 | apt（系统默认） |
| git | 2.53.0 | apt（系统默认） |
| DeepSeek Harness（`dsh`） | npm `latest`（当前 0.2.2-rc.5） | npm 全局安装 |

- Go 模块代理：`https://goproxy.cn,direct`
- Git 身份：`Liu Cong <nonpvirvatemail@163.com>`
- SSH 服务：容器内 22 端口，`root` 密码 `123456`（见文末安全提示）

## 目录结构

```
lc-dev-env/
├── .github/
│   └── workflows/
│       └── ci.yml          # 构建 -> 冒烟测试 -> 轮转 latest/previous -> 发布 -> 复验
├── Dockerfile              # 开发环境镜像（构建源参数化）
├── dev-env.conf            # 默认配置（镜像仓库/容器名/端口/挂载）
├── files/
│   └── entrypoint.sh       # 容器入口：启动 sshd + 守护 dsh web
├── scripts/
│   ├── lib.sh              # 公共库：配置加载、运行时探测、版本钉住
│   ├── build.sh            # 本机构建镜像（内网/阿里云源，本地测试用）
│   ├── run.sh              # 拉取并钉住镜像，后台运行容器
│   ├── rollback.sh         # 查看历史版本并回滚
│   ├── smoke-test.sh       # 冒烟测试：SSH 登录校验工具链/挂载/sshd
│   ├── web-url.sh          # 输出当前 DSH Web GUI 的带 token URL
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

> ACR 登录：二选一——首次运行前手动登录一次，或用环境变量提供凭据：
> ```bash
> podman login crpi-vb458bo8ja2welze.cn-chengdu.personal.cr.aliyuncs.com
> # 或
> export ALIYUN_ACR_USERNAME=xxx ALIYUN_ACR_PASSWORD=xxx
> ```
> 用环境变量时，脚本仅在拉取阶段临时登录，拉取结束（无论成败）后立即登出，凭据不落盘；
> 手动登录的凭据属于你自己的登录状态，脚本**不会**登出它（否则后续 `run.sh --update` 会因缺凭据而失败）。
> 登出失败会打印警告，此时请手动执行 `podman logout <REGISTRY>`。
>
> 挂载说明：宿主机 `/home/lc/cont_data` 挂载到容器 `/home/data`，目录不存在时自动创建；
> DSH 数据保存在其下的 `dsh/` 子目录（容器内 `/home/data/dsh`）。
> `:Z` 用于 SELinux 环境重打标签，非 SELinux 环境无副作用。

### 2. 进入容器

```bash
scripts/enter.sh                      # 交互式 bash
scripts/enter.sh go version           # 在容器内执行命令
scripts/enter.sh -n other-env         # 指定容器名
# 或
podman exec -it lc-devel-env bash     # 容器名见 dev-env.conf 的 CONTAINER_NAME
```

### 3. 从 Windows 访问 Web GUI

容器启动时会自动运行 `dsh web`（[files/entrypoint.sh](files/entrypoint.sh)），监听容器 IP 的 3080，
宿主机按 `WEB_PORT`（默认 3080）发布。`scripts/run.sh` 会打印带一次性 token 的地址：

```
Web GUI:    http://<服务器IP>:3080/?token=...
```

在 Windows 浏览器打开该 URL 即可（token 换 30 天会话 cookie）。容器重启后 token 会变，重新获取：

```bash
scripts/web-url.sh                                        # 在服务器上
ssh user@server /path/to/lc-dev-env/scripts/web-url.sh    # 从 Windows 远程取
```

- `PUBLIC_HOST` 决定 URL 里使用的地址，默认取服务器默认路由的源 IP；多网卡/VPN 环境请显式设置。
- 需要在服务器防火墙/安全组放行 `WEB_PORT`，并保证 Windows 与服务器网络互通。
- 更安全的做法是不对外放行端口，改用 SSH 隧道：

  ```powershell
  # Windows PowerShell
  ssh -L 3080:127.0.0.1:3080 user@server
  ```

  并以 `PUBLIC_HOST=127.0.0.1 scripts/run.sh` 启动，然后打开 `http://127.0.0.1:3080/?token=...`。

- Web GUI 默认是明文 HTTP（非 loopback 绑定会在启动时警告）。对外暴露请限制在可信内网，
  或前置 HTTPS 反向代理并用 `DSH_WEB_PUBLIC_URL` / `DSH_WEB_TRUSTED_HOSTS` 覆盖公告与信任地址。
- 不需要 Web GUI 时可用 `DSH_ENABLE_WEB=0 scripts/run.sh`，容器只保留 SSH。
- 模型凭据：`DEEPSEEK_API_KEY` 会传入容器；也可在 Web UI 的「设置 → 模型」里填写（保存在 `/home/data/dsh`）。

### 4. 升级到新版本

```bash
scripts/run.sh --update        # 重新拉取 IMAGE_TAG（默认 latest）并钉住新 digest
scripts/run.sh --tag <tag>     # 钉住任意已存在的 tag（如 previous）
```

### 5. 回滚

```bash
scripts/rollback.sh --list     # 列出本地记录的可回滚版本（1 = 最新）
scripts/rollback.sh 2          # 回滚到本地历史序号 2 的版本
scripts/rollback.sh previous   # 回滚到 ACR 中的上一版（CI 轮转出来的标签）
scripts/rollback.sh sha256:1f2e3d...   # 按镜像摘要回滚
```

ACR 中只保留 `latest` 与 `previous` 两个版本，所以跨机器回滚只有一档；
本机 `.state` 会记录最近 50 次钉住的 digest，本地回滚可以更多（前提是镜像在本地，
或 ACR 仍能按该 digest 拉取）。

也可以直接钉住 CI 输出的摘要运行：

```bash
IMAGE_DIGEST=sha256:1f2e3d... scripts/run.sh
```

### 6. 冒烟测试

```bash
scripts/smoke-test.sh                    # 测试当前钉住的版本
scripts/smoke-test.sh previous           # 测试 ACR 中的上一版
scripts/smoke-test.sh --keep             # 保留测试容器，便于排查
```

脚本会启动临时容器、通过 SSH 登录并检查：Go/Node/npm/pnpm/Python/g++/make/cmake/git 可用性与版本、
GOPROXY/时区/locale/git 身份/git 提示符、`dsh` 可用性、`/home/data` 挂载读写、sshd 配置、
`dsh web` 自动启动（URL 已生成）与容器存活状态。

### 7. 本机构建镜像（本地验证 Dockerfile）

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
| `CONTAINER_NAME` | `lc-devel-env` | 容器名，run/enter/rollback/smoke-test 共用 |
| `HOST_GIT_DIR` | `/home/lc/cont_data` | 挂载到容器 `/home/data` 的宿主机数据目录 |
| `SSH_PORT` | `2227` | 宿主机 SSH 端口 -> 容器 22 |
| `WEB_PORT` | `3080` | 宿主机 Web GUI 端口 -> 容器 3080 |
| `PUBLIC_HOST` | 空（自动检测） | 浏览器访问用的服务器地址 |
| `DSH_HOME_SUBDIR` | `dsh` | DSH 数据子目录：容器内 `/home/data/dsh` |
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
- ACR 侧只有 `latest` / `previous` 两个版本：个人版不支持版本保留策略，由 CI 在每次发布时
  把旧 `latest` 轮转为 `previous`，从而把可见版本固定为 2 个。

## DSH 版本与升级

- 镜像构建时按 `Dockerfile` 的 `ARG DSH_VERSION` 安装（默认 `latest`，即 npm 上最新版本）。
- 升级：重新构建镜像后 `scripts/run.sh --update` 拉取新镜像并重建容器。

  ```bash
  scripts/build.sh                     # 本机构建，装 npm 上最新的 dsh
  DSH_VERSION=0.2.3 scripts/build.sh   # 固定版本构建
  scripts/run.sh --update              # 使用 CI 构建的新镜像升级
  ```

- 查看当前版本：`scripts/enter.sh dsh --version`（容器启动日志里也会打印）。
- 会话、设置、凭据都在 `${HOST_GIT_DIR}/dsh`（容器内 `/home/data/dsh`），升级镜像不会丢；跨大版本升级前
  建议先看镜像内的 `/usr/local/lib/node_modules/@deepseek-ai/dsh/docs/upgrade-guide/`。
- 如果 web profile 因升级出现异常，可停止容器后删除 `${HOST_GIT_DIR}/dsh/profiles/web`，下次启动会按
  模板重新初始化（自定义配置会丢失）。

## CI/CD

`.github/workflows/ci.yml`：

1. **build-and-test**（push 到 `main`、打 `v*` tag、对 `main` 的 PR 均触发）
   - 用 `docker build` 构建到本地镜像库，并校验镜像确实存在；
   - **冒烟测试**（同 `scripts/smoke-test.sh`）通过后才允许推送；
   - 登录 ACR 后先把当前 `latest` 轮转为 `previous`，再把本次构建推为新的 `latest`；
   - 输出两个版本的 digest 与仓库地址，写入 Job Summary。
2. **verify-published**（仅 push/tag 且发布成功时）
   - 按 **digest** 从 ACR 重新拉取并再跑一遍冒烟测试，验证仓库里的产物本身可用。

| 触发 | ACR 中的变化 |
|------|-------------|
| push 到 `main` / 打 `v*` tag | `latest` 更新为本次构建，`previous` 指向上一版 |
| Pull Request | 只构建 + 冒烟测试，不推送 |

> ACR 个人版不支持版本保留策略（官方文档：只能到控制台手动删除），因此这里用
> `latest` + `previous` 两个滚动标签，把 ACR 中可引用的版本固定在 2 个。
> 更早的 manifest 会失去标签引用，是否回收由 ACR 决定；需要保留更多历史时，
> 可升级企业版并使用保留策略，或手动在控制台保留。

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
| NPM_REGISTRY | `https://registry.npmjs.org` | `https://registry.npmmirror.com` |
| DSH_VERSION | `latest` | `latest`（可用 `DSH_VERSION=x.y.z` 固定） |

## 说明与已知限制

- 脚本兼容 `podman` 与 `docker`（自动检测，优先 podman，可用 `RUNTIME` 强制指定）。
- 容器以 root 运行，后台常驻（`sleep infinity`），重启策略 `unless-stopped`。
- 基础镜像来自内部 SWR 源（目标机无法直连 Docker Hub），CI 环境使用公共源。
- SSH 会话通过 `SetEnv` 注入 `PATH`/`GOPROXY`/`TZ`/`LANG`（sshd 不继承镜像 ENV），
  `/etc/profile.d/dev-env.sh` 兜底登录 shell。
- 安全提示：`root` 密码固定为 `123456` 且端口映射默认监听所有网卡；请只在可信网络使用，
  或自行改为 SSH key 登录（`-p 127.0.0.1:${SSH_PORT}:22` 可限制仅本机访问）。
- 目前只构建 `linux/amd64` 单架构镜像。
- 容器内 `dsh` 以 root 身份运行，agent 的 shell 工作目录是 `/home/data`；Web GUI 打印的带 token
  URL 等同于完整访问权限，只应发给预期用户。
- Web GUI 默认明文 HTTP 且监听容器网卡地址；请用防火墙限制 `WEB_PORT`，或只通过 SSH 隧道访问。
- ACR 个人版不支持版本保留策略，因此仓库里始终只有 `latest` / `previous` 两个版本；
  需要更长的版本历史时请改用企业版保留策略或手动维护。
