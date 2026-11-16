# syntax=docker/dockerfile:1

# CodeBuddy Code 常驻网关镜像：--serve 模式（Web UI + REST API + ACP）
# 官方文档：https://www.codebuddy.cn/docs/cli/web-ui
ARG NODE_IMAGE=node:22-bookworm-slim
FROM ${NODE_IMAGE}

LABEL org.opencontainers.image.title="CodeBuddy Code Gateway" \
      org.opencontainers.image.description="CodeBuddy Code CLI in --serve mode (Web UI / HTTP API)" \
      org.opencontainers.image.source="https://cnb.cool/codebuddy/codebuddy-code"

# 固定版本可复现；升级时改这里或 .env 里的 CODEBUDDY_VERSION
ARG CODEBUDDY_VERSION=2.184.0

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/cbc \
    CODEBUDDY_CONFIG_DIR=/home/cbc/.codebuddy \
    DISABLE_AUTOUPDATER=1 \
    TZ=Asia/Shanghai \
    PORT=7890 \
    HOST=0.0.0.0 \
    AGENT=cli \
    PERMISSION_MODE=default \
    CODEBUDDY_GATEWAY_AUTH=password

# git / ssh / ca-certs 是 Agent 在容器内干活的基本依赖；gosu 用于运行时降权
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      git \
      gosu \
      openssh-client \
      procps \
      tzdata \
 && git config --system --add safe.directory '*' \
 && rm -rf /var/lib/apt/lists/*

RUN --mount=type=cache,target=/root/.npm \
    npm install -g --no-audit --no-fund "@tencent-ai/codebuddy-code@${CODEBUDDY_VERSION}" \
 && codebuddy --version \
 && npm cache clean --force

RUN groupadd -g 1000 cbc \
 && useradd -m -d /home/cbc -s /bin/bash -u 1000 -g cbc cbc \
 && mkdir -p /home/cbc/.codebuddy /workspace \
 && chown -R cbc:cbc /home/cbc /workspace

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh \
 && sed -i 's/\r$//' /usr/local/bin/docker-entrypoint.sh

EXPOSE 7890

ENTRYPOINT ["docker-entrypoint.sh"]
# 默认由 entrypoint 拼出 serve 参数；也可 docker run image bash 进容器做首次登录
CMD []
