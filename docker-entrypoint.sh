#!/usr/bin/env bash
# 容器内入口：初始化配置/随机密码，降权后启动 CodeBuddy serve 网关。
set -euo pipefail

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
PORT="${PORT:-7890}"
HOST="${HOST:-0.0.0.0}"
AGENT="${AGENT:-cli}"
PERMISSION_MODE="${PERMISSION_MODE:-default}"
BASE_PATH="${BASE_PATH:-}"
AUTH="${CODEBUDDY_GATEWAY_AUTH:-password}"
GATEWAY_PASSWORD="${CODEBUDDY_GATEWAY_PASSWORD:-}"
CONFIG_DIR="${CODEBUDDY_CONFIG_DIR:-/home/cbc/.codebuddy}"

# 允许通过 PUID/PGID 对齐宿主机用户，避免挂载目录读写权限问题
if [ "$(id -u)" -eq 0 ]; then
  groupmod -o -g "$PGID" cbc >/dev/null 2>&1 || true
  usermod -o -u "$PUID" cbc >/dev/null 2>&1 || true
  chown -R cbc:cbc /home/cbc 2>/dev/null || true
fi

# 首次启动写入 settings.json：固定 gateway 密码，避免每次重启密码变化。
# 若用户已自己放了 settings.json，则完全不覆盖。
SETTINGS="$CONFIG_DIR/settings.json"
if [ ! -f "$SETTINGS" ]; then
  mkdir -p "$CONFIG_DIR"
  if [ "$AUTH" = "none" ]; then
    printf '%s\n' 'WARNING: CODEBUDDY_GATEWAY_AUTH=none — 仅限隔离内网/CI，公网环境务必使用 password。'
    GATEWAY_PASSWORD=""
  elif [ -z "$GATEWAY_PASSWORD" ]; then
    GATEWAY_PASSWORD="$(node -e 'process.stdout.write(require("crypto").randomBytes(24).toString("base64url"))')"
    printf '\n============================================================\n'
    printf 'CodeBuddy Web UI 初始密码: %s\n' "$GATEWAY_PASSWORD"
    printf '已写入 %s，重启后会继续沿用。\n' "$SETTINGS"
    printf '============================================================\n\n'
  fi
  node - "$SETTINGS" "$AUTH" "$GATEWAY_PASSWORD" <<'NODE'
const fs = require('fs');
const [file, auth, password] = process.argv.slice(2);
const gateway = { auth };
if (auth === 'password') gateway.password = password;
fs.writeFileSync(file, JSON.stringify({ gateway }, null, 2) + '\n', { mode: 0o600 });
NODE
  chown cbc:cbc "$SETTINGS" 2>/dev/null || true
fi

# 无参数：启动 serve 网关；带参数：直接执行传入的命令（便于首次 /login）
if [ "$#" -gt 0 ]; then
  CMD=("$@")
else
  CMD=(codebuddy --serve --host "$HOST" --port "$PORT" --agent "$AGENT" --permission-mode "$PERMISSION_MODE")
  if [ -n "$BASE_PATH" ]; then
    CMD+=(--base-path "$BASE_PATH")
  fi
  if [ "$AUTH" = "none" ]; then
    CMD+=(--auth none)
  fi
  if [ -n "${EXTRA_ARGS:-}" ]; then
    read -r -a extra <<< "$EXTRA_ARGS"
    CMD+=("${extra[@]}")
  fi
fi

if [ "$(id -u)" -eq 0 ]; then
  exec gosu cbc "${CMD[@]}"
fi
exec "${CMD[@]}"
