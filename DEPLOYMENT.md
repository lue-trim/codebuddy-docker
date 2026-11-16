# CodeBuddy 常驻 Docker 部署方案

## 1. 方案结论

CodeBuddy Code 有两个容易混淆的入口：

| 入口 | 适用场景 | 容器里是否推荐 |
| --- | --- | --- |
| 会话内 `/gateway`（Remote Control） | 交互式 TUI 里临时起服务，依赖 cloudflared Quick Tunnel，终端退出即断 | 否。它是给本机交互会话用的 |
| `codebuddy --serve`（Web UI / HTTP API） | 常驻 HTTP 服务，自带 Web UI、REST API、ACP，可作为 PID 1 | **是**。这就是官方文档里的 serve 模式，底层是同一个 Gateway 服务 |

因此本方案用 `--serve --host 0.0.0.0 --port 7890` 跑一个长期容器，前面再挂一层 TLS + 鉴权，配置和登录态用 Docker 卷持久化。

> ⚠️ 安全前提：Web UI 包含**内嵌终端**和文件读写能力，等同于一个可通过浏览器操作的远程 shell。不要把它裸奔到公网，不要挂载 `/var/run/docker.sock` 或整个宿主机根目录。

## 2. 架构

```
浏览器 / 手机
      │ HTTPS + 二次鉴权（Caddy / Cloudflare Access / VPN）
      ▼
宿主机 127.0.0.1:7890
      │ docker port mapping
      ▼
┌──────────────────────────────────────┐
│ container: codebuddy-gateway         │
│  entrypoint.sh → codebuddy --serve   │
│  --agent cli --permission-mode default│
│  CODEBUDDY_GATEWAY_AUTH=password     │
└───────────────┬──────────────────────┘
                │
      ┌─────────┴──────────┐
      ▼                    ▼
codebuddy-config 卷      ./workspace 绑定挂载
settings.json / 登录态    Agent 默认工作目录
会话 / 日志 / Skills      （只挂项目目录，别挂根目录）
```

## 3. 文件清单

| 文件 | 作用 |
| --- | --- |
| `Dockerfile` | Node 22 基础镜像 + 固定版本 CLI + 非 root 运行 + 自动更新关闭 |
| `docker-entrypoint.sh` | 首次启动生成随机网关密码、按 PUID/PGID 降权、拼装 serve 参数 |
| `docker-compose.yml` | 长期运行、重启策略、端口映射、卷、健康检查 |
| `.env.example` | 全部可调参数，复制为 `.env` 后使用 |
| `.dockerignore` | 只把构建需要的文件送进构建上下文 |

## 4. 快速开始

### 4.1 准备

```bash
cd /path/to/codebuddy-docker
mkdir -p workspace
cp .env.example .env

# 用宿主机上拥有项目目录的用户 uid/gid 改 .env 里的 PUID / PGID
id -u
id -g
```

### 4.2 首次登录（二选一）

容器需要一份已登录的 CodeBuddy 凭据，保存在 `~/.codebuddy`（容器内为 `/home/cbc/.codebuddy`）。

**方式 A：在容器内交互式登录（推荐）**

```bash
docker compose build
docker compose run --rm -it --entrypoint codebuddy codebuddy
# 进入 TUI 后执行 /login，按提示完成，然后 /exit
```

**方式 B：复用开发机上已登录的配置**

```bash
docker run --rm \
  -v codebuddy-config:/data \
  -v "$HOME/.codebuddy:/src:ro" \
  alpine sh -c 'cp -a /src/. /data/'
```

> 如果复制过来的 `settings.json` 已经包含 `gateway.password`，entrypoint 不会覆盖它；建议先确认里面是一个强密码。

### 4.3 启动

```bash
docker compose up -d --build
docker compose ps
docker compose logs --tail=40 codebuddy
```

首次启动日志里会打印：

```
CodeBuddy Web UI 初始密码: xxxxxxxxxxxx
```

该密码同时写入 `codebuddy-config` 卷的 `settings.json`，重启后沿用。

### 4.4 访问

```bash
curl -I http://127.0.0.1:7890/
```

浏览器打开 `http://<服务器IP>:7890/`，输入上面的密码。API 调用使用同一个密码作为 Bearer Token：

```bash
curl -H "Authorization: Bearer <密码>" http://127.0.0.1:7890/api/openapi.json
```

API 文档：`http://127.0.0.1:7890/api/docs`

## 5. 公网访问（强烈建议加一层）

默认 compose 把端口绑在 `127.0.0.1`，只适合本机或已有安全通道的场景。要“随时随地访问”，按安全性从高到低选一种：

1. **Tailscale / WireGuard（最省心）**：`.env` 里设 `BIND_IP=0.0.0.0`，再用防火墙只放行 VPN 网段（如 `100.64.0.0/10`），不把端口暴露给公网。
2. **Cloudflare Tunnel**：在宿主机跑 `cloudflared tunnel --url http://127.0.0.1:7890`，配合 Cloudflare Access 做邮箱/SSO 鉴权，无需开放入站端口。比 Quick Tunnel 的随机域名更适合长期用。
3. **Caddy 反代 + HTTPS + Basic Auth**（示例）：

   先把 `.env` 设为 `BIND_IP=127.0.0.1`，`CODEBUDDY_CODE_CORS_ORIGINS=https://codebuddy.example.com`，再配置：

   ```caddyfile
   codebuddy.example.com {
     basic_auth {
       admin $2a$14$REPLACE_WITH_caddy_hash_password_OUTPUT
     }
     reverse_proxy 127.0.0.1:7890
     header {
       Strict-Transport-Security "max-age=31536000; includeSubDomains"
       X-Content-Type-Options "nosniff"
       Referrer-Policy "no-referrer"
     }
   }
   ```

   生成密码哈希：`caddy hash-password --plaintext '<你的强密码>'`

   即使用反代，也**保留** CodeBuddy 自身的 `password` 鉴权，两层叠加。

如需挂在子路径（例如 `https://example.com/codebuddy/`），设置 `BASE_PATH=/codebuddy/`，并让反代把该前缀透传给后端；最终以启动日志里的 **Web UI** 地址为准。

## 6. 安全基线

- 永远不要用 `CODEBUDDY_GATEWAY_AUTH=none` 暴露到非隔离网络。
- 只挂载需要的项目目录；禁止挂载 `/`、`/var/run/docker.sock`、可写的 `~/.ssh`。确实需要 git 凭据时只读挂载 `./secrets/ssh:/home/cbc/.ssh:ro`。
- 保持 `AGENT=cli`、`PERMISSION_MODE=default`，在浏览器里逐条批准工具调用。`bypassPermissions` / `fullAccess` 只适合隔离沙箱。
- CodeBuddy 自带登录限流（每分钟 2 次 + 每小时 12 次失败尝试），但不要把它当作唯一防线，反代层再加 IP 限速/封禁。
- 镜像里设置 `DISABLE_AUTOUPDATER=1`，升级走镜像重建，避免容器里偷偷改写自身文件。

## 7. 日常运维

```bash
# 升级：改 .env 的 CODEBUDDY_VERSION，然后重建
docker compose up -d --build

# 查看日志 / 状态
docker compose logs -f --tail=200 codebuddy
docker compose ps

# 重置 Web UI 密码（改完需重启）
docker compose exec codebuddy node -e \
 'const fs=require("fs"),p=process.env.CODEBUDDY_CONFIG_DIR+"/settings.json";const s=JSON.parse(fs.readFileSync(p));s.gateway.password=process.argv[1];fs.writeFileSync(p,JSON.stringify(s,null,2)+"\n")' \
 '新密码'
docker compose restart

# 备份配置卷（含登录态、会话、设置、日志）
mkdir -p backup
docker run --rm \
  -v codebuddy-config:/data \
  -v "$PWD/backup:/backup" \
  alpine tar czf "/backup/codebuddy-$(date +%F).tgz" -C /data .
```

## 8. 故障排查

| 现象 | 处理 |
| --- | --- |
| Web UI 打开后会话报未登录 | 重新执行 4.2 的 `/login`；检查 `codebuddy-config` 卷是否重建过 |
| 登录页密码不对 | 从 `settings.json` 的 `gateway.password` 读取，或按第 7 节重置 |
| API 401 | API 端点不认 `?password=` URL 参数，必须用 `Authorization: Bearer <密码>`；浏览器要先登录拿 Cookie |
| 反代域名下 CORS 报错 | 在 `.env` 的 `CODEBUDDY_CODE_CORS_ORIGINS` 填完整 origin（如 `https://codebuddy.example.com`），重建容器 |
| 容器内写不了项目目录 | 调整 `.env` 的 `PUID`/`PGID` 与宿主机一致后 `docker compose up -d --force-recreate` |
| 子路径访问白屏 | 确认 `BASE_PATH` 以 `/` 开头；反代需透传该前缀；以启动日志中的 Web UI 地址为准 |
| 容器反复重启 | 先看 `docker compose logs`；未登录一般不会阻止 serve 启动，但登录后才能正常跑任务 |
| 构建时报 `groupadd: GID '1000' already exists` | 官方 node 镜像已占用 uid/gid 1000；当前 Dockerfile 已改为复用并重命名其 `node` 用户/组，重新 build 即可 |

## 9. 官方参考

- Web UI / serve 模式：https://www.codebuddy.cn/docs/cli/web-ui
- CLI 参数（`--serve` / `--host` / `--port` / `--auth` / `--base-path`）：https://www.codebuddy.cn/docs/cli/cli-reference
- 远程控制 / Gateway：https://www.codebuddy.ai/docs/zh/cli/remote-control
- 安装与配置目录：https://www.codebuddy.cn/docs/cli/installation
