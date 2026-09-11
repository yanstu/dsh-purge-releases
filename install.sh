#!/usr/bin/env bash
set -euo pipefail
VER=v1.3.5
TGZ="${TMPDIR:-/tmp}/dsh-purge.tgz"
URLS=(
  "https://cdn.jsdelivr.net/gh/yanstu/dsh-purge-releases@${VER}/dsh-purge.tgz"
  "https://gh-proxy.org/https://github.com/yanstu/dsh-purge-releases/releases/download/${VER}/dsh-purge.tgz"
  "https://github.com/yanstu/dsh-purge-releases/releases/download/${VER}/dsh-purge.tgz"
)

if ! command -v node >/dev/null 2>&1; then
  echo "未找到 Node.js。请先安装 Node.js 18 或更高版本。" >&2
  exit 1
fi

if ! command -v dsh >/dev/null 2>&1; then
  echo "正在安装 dsh..."
  npm install -g @deepseek-ai/dsh
fi
if ! command -v dsh >/dev/null 2>&1; then
  echo "仍未找到 dsh。请新开一个终端后再运行。" >&2
  exit 1
fi

if ! command -v pnpm >/dev/null 2>&1; then
  echo "正在安装 pnpm..."
  npm install -g pnpm --allow-scripts=pnpm 2>/dev/null || npm install -g pnpm
  export PATH="$(npm prefix -g)/bin:$PATH"
fi
if ! command -v pnpm >/dev/null 2>&1; then
  echo "仍未找到 pnpm。请新开一个终端后再运行。" >&2
  exit 1
fi

ok=0
for url in "${URLS[@]}"; do
  echo "正在下载 $url"
  if curl -fsSL --retry 2 --connect-timeout 20 -o "$TGZ" "$url"; then
    ok=1
    break
  fi
done
if [[ "$ok" -ne 1 ]]; then
  echo "安装包下载失败。不要使用 GitHub 源码 zip，dsh plugin add 只接受 .tgz。" >&2
  exit 1
fi
size=$(wc -c < "$TGZ" | tr -d ' ')
if [[ "$size" -lt 100000 ]]; then
  echo "下载到的文件无效。" >&2
  exit 1
fi

PROFILE="${1:-}"
if [[ -z "$PROFILE" ]]; then
  dsh plugin --profile web add "$TGZ"
  dsh plugin --profile default add "$TGZ" || true
  echo "已写入。请完全退出 dsh web / 桌面客户端后重新打开，再应用补丁或发送 /purge apply。"
  exit 0
fi
dsh plugin --profile "$PROFILE" add "$TGZ"
