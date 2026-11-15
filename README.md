# lc-dev-env

基于 Ubuntu 的通用开发环境容器镜像，预装 Go / Python / Node.js / g++ 等工具链。

## 镜像包含的工具链

| 工具 | 版本 | 安装方式 |
|------|------|---------|
| Go | 1.27.4 | 官方二进制（阿里云镜像） |
| Python | 3.14.4 | apt（系统默认） |
| Node.js | 26.13.1（npm 11.20.0） | 官方二进制（阿里云镜像） |
| g++ / GCC | 15.2.0 | apt（系统默认） |
| git | 2.53.0 | apt（系统默认） |

- Go 模块代理：`https://goproxy.cn,direct`
- Git 身份：`Liu Cong <nonpvirvatemail@163.com>`

## 目录结构

```
lc-dev-env/
├── Dockerfile          # 构建开发环境镜像
├── scripts/
│   ├── build.sh        # 构建镜像
│   ├── run.sh          # 后台运行容器（挂载宿主机 git 目录）
│   └── enter.sh        # 进入容器
└── README.md
```

## 使用方法

### 1. 构建镜像

```bash
scripts/build.sh
# 或
podman build -f Dockerfile -t lc-ubuntu-dev:latest .
```

### 2. 运行容器

```bash
scripts/run.sh
# 或
podman run -d --name lc-dev-env --restart=unless-stopped \
  -v /home/lc/git:/home/git:Z \
  lc-ubuntu-dev:latest
```

> 挂载说明：宿主机 `/home/lc/git` 挂载到容器 `/home/git`。
> `:Z` 用于 SELinux 环境下重打标签，非 SELinux 环境可省略。

### 3. 进入容器

```bash
scripts/enter.sh
# 或
podman exec -it lc-dev-env bash
```

## 说明

- 容器以 root 运行，后台常驻（`sleep infinity`），重启策略 `unless-stopped`。
- 基础镜像来自内部 SWR 源（因目标机无法直连 Docker Hub）。
- Go / Node 二进制使用国内镜像下载。
