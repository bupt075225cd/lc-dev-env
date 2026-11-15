# 开发环境基础镜像：Ubuntu 26.04 + Go/Node + Python/g++ 系统版
FROM swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/library/ubuntu:latest

ARG GO_VERSION=1.27.4
ARG NODE_VERSION=26.13.1

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai \
    PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin \
    GOPROXY=https://goproxy.cn,direct

# 1) apt 保持默认源（不改镜像），安装基础工具链
#    g++ -> 系统 GCC 15.2；python3 -> 系统 3.14.4；git -> 系统 2.53
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential gcc g++ make cmake pkg-config \
        python3 python3-pip python3-venv python3-dev \
        git curl wget ca-certificates xz-utils \
        vim bash-completion \
        libssl-dev zlib1g-dev libffi-dev libbz2-dev \
        libreadline-dev libsqlite3-dev libncurses-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2) Go 官方二进制（阿里云镜像，版本写死避免动态解析不稳定）
RUN set -eux; \
    dpkg --print-architecture | grep -q amd64 && GO_ARCH=amd64 || GO_ARCH=arm64; \
    curl -fsSL "https://mirrors.aliyun.com/golang/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -o /tmp/go.tar.gz; \
    tar -C /usr/local -xzf /tmp/go.tar.gz; \
    rm -f /tmp/go.tar.gz

# 3) Node.js 官方二进制（阿里云镜像，版本写死）
RUN set -eux; \
    dpkg --print-architecture | grep -q amd64 && NODE_ARCH=x64 || NODE_ARCH=arm64; \
    curl -fsSL "https://mirrors.aliyun.com/nodejs-release/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" -o /tmp/node.tar.xz; \
    tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1; \
    rm -f /tmp/node.tar.xz

# 4) Git 用户身份配置（固化进镜像）
RUN git config --global user.email "nonpvirvatemail@163.com" \
    && git config --global user.name "Liu Cong"

# 5) root 运行，工作目录为挂载点，后台常驻
WORKDIR /home/git
CMD ["sleep", "infinity"]
