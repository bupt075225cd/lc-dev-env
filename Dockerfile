# ===== 开发环境基础镜像（构建源参数化）=====
# 默认使用公共源，适用于 GitHub Actions CI 构建；
# 本机构建时由 build.sh 传入内网 SWR / 阿里云镜像参数。

ARG BASE_IMAGE=docker.io/library/ubuntu:latest
ARG GO_VERSION=1.27.4
ARG NODE_VERSION=26.13.1
ARG GO_DL_BASE=https://go.dev/dl
ARG NODE_DL_BASE=https://nodejs.org/dist

FROM ${BASE_IMAGE}

# FROM 之后需重新声明要在 RUN 中使用的 ARG
ARG GO_VERSION
ARG NODE_VERSION
ARG GO_DL_BASE
ARG NODE_DL_BASE

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin \
    GOPROXY=https://goproxy.cn,direct

# 1) apt 保持默认源，安装基础工具链
#    g++ -> 系统 GCC 15.2；python3 -> 系统 3.14.4；git -> 系统 2.53
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential gcc g++ make cmake pkg-config \
        python3 python3-pip python3-venv python3-dev \
        git curl wget ca-certificates xz-utils \
        vim bash-completion \
        libssl-dev zlib1g-dev libffi-dev libbz2-dev \
        libreadline-dev libsqlite3-dev libncurses-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2) Go 官方二进制（下载源由 GO_DL_BASE 决定）
RUN set -eux; \
    dpkg --print-architecture | grep -q amd64 && GO_ARCH=amd64 || GO_ARCH=arm64; \
    curl -fsSL "${GO_DL_BASE}/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -o /tmp/go.tar.gz; \
    tar -C /usr/local -xzf /tmp/go.tar.gz; \
    rm -f /tmp/go.tar.gz

# 3) Node.js 官方二进制（下载源由 NODE_DL_BASE 决定）
RUN set -eux; \
    dpkg --print-architecture | grep -q amd64 && NODE_ARCH=x64 || NODE_ARCH=arm64; \
    curl -fsSL "${NODE_DL_BASE}/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" -o /tmp/node.tar.xz; \
    tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1; \
    rm -f /tmp/node.tar.xz

# 4) Git 用户身份配置（固化进镜像）
RUN git config --global user.email "nonpvirvatemail@163.com" \
    && git config --global user.name "Liu Cong"

# 5) 安装 SSH 服务，允许 root 密码登录（密码 123456）
#    root 密码登录默认被限制，通过 sshd_config.d 覆盖为允许密码登录
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server \
    && echo 'root:123456' | chpasswd \
    && mkdir -p /run/sshd /etc/ssh/sshd_config.d \
    && printf 'PermitRootLogin yes\nPasswordAuthentication yes\n' > /etc/ssh/sshd_config.d/00-dev-env.conf \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

EXPOSE 22

# 6) bash 提示符：启用 git 分支显示
#    构建时将 files/ 下的官方 git-prompt.sh 复制到 /root，source 它提供 __git_ps1
COPY files/git-prompt.sh /root/git-prompt.sh
RUN printf '%s\n' 'source ~/git-prompt.sh' \
                  'export PS1='"'"'[\u@\h \W\[\033[32m\]$(__git_ps1 " (%s)")\[\033[0m\]]\$ '"'"'' \
        >> /root/.bashrc

# 7) root 运行，工作目录为挂载点，启动 SSH 并后台常驻
WORKDIR /home/git
CMD ["sh", "-c", "ssh-keygen -A && service ssh start && sleep infinity"]
