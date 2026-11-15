# lc-dev-env

基于 Ubuntu 的通用开发环境容器镜像，预装 Go / Python / Node.js / g++ 等工具链。

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

## 目录结构

```
lc-dev-env/
├── .github/
│   └── workflows/
│       └── ci.yml          # GitHub Actions：构建并发布镜像到阿里云 ACR
├── Dockerfile              # 构建开发环境镜像（构建源参数化）
├── scripts/
│   ├── build.sh            # 构建镜像（本机用内网/阿里云源）
│   ├── run.sh              # 后台运行容器（挂载宿主机 git 目录）
│   └── enter.sh            # 进入容器
├── .dockerignore
└── README.md
```

## 使用方法

### 1. 构建镜像

本机构建（自动使用内网 / 阿里云镜像源）：

```bash
scripts/build.sh
```

公共源构建（用于 GitHub Actions CI）：

```bash
podman build -f Dockerfile -t lc-ubuntu-dev:latest .
```

### 2. 运行容器

```bash
scripts/run.sh
```

> 挂载说明：宿主机 `/home/lc/git` 挂载到容器 `/home/git`。
> 若宿主机 `/home/lc/git` 不存在，`run.sh` 会自动创建。
> `:Z` 用于 SELinux 环境下重打标签，非 SELinux 环境可省略。

### 3. 进入容器

```bash
scripts/enter.sh
# 或
podman exec -it lc-dev-env bash
```

## CI/CD

- 推送到 GitHub 后，`.github/workflows/ci.yml` 会在 push 到 `main` 或打 `v*` tag 时自动构建镜像并发布到阿里云 ACR。
- 发布地址：`crpi-vb458bo8ja2welze.cn-chengdu.personal.cr.aliyuncs.com`
- 需要配置的 GitHub Secrets：
  - `ALIYUN_ACR_USERNAME`：阿里云 ACR 登录用户名
  - `ALIYUN_ACR_PASSWORD`：阿里云 ACR 登录密码

## 构建源说明

Dockerfile 的构建源已参数化，默认使用公共源（供 GitHub Actions CI 使用），本机构建通过 `build.sh` 自动传入内网 / 阿里云镜像参数：

| 参数 | 默认（CI / 公共源） | 本机（build.sh） |
|------|---------------------|------------------|
| BASE_IMAGE | `docker.io/library/ubuntu:latest` | `swr.cn-north-4...` |
| GO_DL_BASE | `https://go.dev/dl` | `https://mirrors.aliyun.com/golang` |
| NODE_DL_BASE | `https://nodejs.org/dist` | `https://mirrors.aliyun.com/nodejs-release` |

## 说明

- 容器以 root 运行，后台常驻（`sleep infinity`），重启策略 `unless-stopped`。
- 基础镜像来自内部 SWR 源（因目标机无法直连 Docker Hub），CI 环境使用公共源。
