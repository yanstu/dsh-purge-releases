#!/usr/bin/env bash
set -euo pipefail

BOOT="${HOME}/.dsh-bootstrap"
NODE_HOME="${BOOT}/node"
NPM_PREFIX="${BOOT}/npm"
TGZ="${TMPDIR:-/tmp}/dsh-purge.tgz"
PINNED_NODE=22.20.0
REL=v1.3.5
REPO=yanstu/dsh-purge-releases
REG_CN=https://registry.npmmirror.com
REG_IO=https://registry.npmjs.org

log() { echo "$*"; }
die() { echo "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

refresh_path() {
  export PATH="${NODE_HOME}/bin:${NPM_PREFIX}/bin:/opt/homebrew/bin:/usr/local/bin:${HOME}/.volta/bin:${PATH}"
}

source_version_managers() {
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
    set +u
    # shellcheck disable=SC1091
    . "${NVM_DIR}/nvm.sh"
    set -u
  fi
  if have fnm; then
    set +u
    eval "$(fnm env 2>/dev/null)" || true
    set -u
  fi
}

persist_path() {
  local dir="$1"
  local line="export PATH=\"${dir}:\$PATH\""
  local file="${HOME}/.zprofile"
  if [[ "$(uname -s)" != "Darwin" ]]; then
    file="${HOME}/.profile"
  fi
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if ! grep -F "$dir" "$file" >/dev/null 2>&1; then
    printf '\n%s\n' "$line" >> "$file"
  fi
}

os_arch() {
  local sys arch
  sys="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch=x64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) die "暂不支持的 CPU 架构：$arch" ;;
  esac
  case "$sys" in
    darwin) echo "darwin-${arch}" ;;
    linux) echo "linux-${arch}" ;;
    *) die "暂不支持的系统：$sys" ;;
  esac
}

fetch() {
  local url="$1" dest="$2"
  if have curl; then
    curl -fsSL --connect-timeout 12 --max-time 90 --retry 2 -A dsh-purge-installer -o "$dest" "$url" \
      || curl -fsSL --ipv4 --connect-timeout 12 --max-time 90 --retry 2 -A dsh-purge-installer -o "$dest" "$url"
  elif have wget; then
    wget -q -O "$dest" --timeout=40 --tries=2 "$url"
  else
    return 1
  fi
}

is_gzip() {
  local hex
  hex="$(dd if="$1" bs=1 count=2 2>/dev/null | LC_ALL=C od -An -tx1 | tr -d ' \n')"
  [[ "$hex" == 1f8b ]]
}

node_major() {
  if ! have node; then
    echo 0
    return
  fi
  node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo 0
}

pick_node_version() {
  local plat="$1" idx tmp ver
  tmp="$(mktemp)"
  for idx in \
    https://npmmirror.com/mirrors/node/index.json \
    https://nodejs.org/dist/index.json
  do
    if fetch "$idx" "$tmp"; then
      ver="$(python3 - "$tmp" "$plat" <<'PY' 2>/dev/null || true
import json, sys
plat = sys.argv[2]
tag = "osx-arm64-tar" if plat.startswith("darwin-arm") else (
    "osx-x64-tar" if plat.startswith("darwin-") else (
    "linux-arm64" if plat.endswith("arm64") else "linux-x64"
    )
)
data = json.load(open(sys.argv[1]))
for row in data:
    files = row.get("files") or []
    if row.get("lts") and tag in files:
        print(row["version"].lstrip("v"))
        break
PY
)"
      if [[ -n "${ver:-}" ]]; then
        rm -f "$tmp"
        echo "$ver"
        return
      fi
    fi
  done
  rm -f "$tmp"
  echo "$PINNED_NODE"
}

install_portable_node() {
  local plat ver tarball tmp url
  plat="$(os_arch)"
  ver="$(pick_node_version "$plat")"
  tarball="node-v${ver}-${plat}.tar.gz"
  tmp="$(mktemp)"
  log "未找到可用的 Node.js，正在安装 ${ver}（用户目录，无需管理员）..."
  for url in \
    "https://npmmirror.com/mirrors/node/v${ver}/${tarball}" \
    "https://cdn.npmmirror.com/binaries/node/v${ver}/${tarball}" \
    "https://nodejs.org/dist/v${ver}/${tarball}"
  do
    log "正在下载 $url"
    if fetch "$url" "$tmp" && [[ "$(wc -c < "$tmp" | tr -d ' ')" -ge 1000000 ]]; then
      mkdir -p "$BOOT"
      rm -rf "$NODE_HOME"
      mkdir -p "$NODE_HOME"
      tar -xzf "$tmp" --strip-components=1 -C "$NODE_HOME"
      rm -f "$tmp"
      persist_path "${NODE_HOME}/bin"
      refresh_path
      return
    fi
  done
  rm -f "$tmp"
  if have brew; then
    log "压缩包下载失败，改用 Homebrew 安装 Node.js..."
    brew install node
    refresh_path
    return
  fi
  die "无法下载 Node.js。请稍后重试，或先安装 Node.js 18 及以上再执行同一条命令。"
}

resolve_node() {
  refresh_path
  source_version_managers
  refresh_path
  if [[ "$(node_major)" -ge 18 ]] && have npm; then
    return
  fi
  install_portable_node
  refresh_path
  if [[ "$(node_major)" -lt 18 ]] || ! have npm; then
    die "仍未找到 Node.js 18 或更高版本。"
  fi
}

use_user_prefix_if_needed() {
  local pref
  pref="$(npm prefix -g 2>/dev/null || true)"
  if [[ -z "$pref" || ! -w "$pref" ]]; then
    mkdir -p "$NPM_PREFIX"
    export npm_config_prefix="$NPM_PREFIX"
    persist_path "${NPM_PREFIX}/bin"
    refresh_path
    return
  fi
  persist_path "${pref}/bin"
  refresh_path
}

select_registries() {
  REGISTRIES=()
  local tmp
  tmp="$(mktemp)"
  if fetch "${REG_CN}/@deepseek-ai/dsh" "$tmp"; then
    REGISTRIES+=("$REG_CN")
  fi
  if fetch "${REG_IO}/@deepseek-ai/dsh" "$tmp"; then
    REGISTRIES+=("$REG_IO")
  fi
  rm -f "$tmp"
  if [[ ${#REGISTRIES[@]} -eq 0 ]]; then
    REGISTRIES=("$REG_CN" "$REG_IO")
  fi
}

use_registry() {
  export npm_config_registry="$1"
  export PNPM_REGISTRY="$1"
}

npm_install_global() {
  local ok=0 reg
  use_user_prefix_if_needed
  for reg in "${REGISTRIES[@]}"; do
    use_registry "$reg"
    log "正在从 $reg 安装 $* ..."
    if npm install -g "$@" --registry "$reg"; then
      ok=1
      break
    fi
  done
  refresh_path
  [[ "$ok" -eq 1 ]]
}

save_tarball() {
  local url
  for url in \
    "https://dsh.coolhs.com/dsh-purge.tgz" \
    "https://cdn.jsdelivr.net/gh/${REPO}/dsh-purge.tgz" \
    "https://fastly.jsdelivr.net/gh/${REPO}/dsh-purge.tgz" \
    "https://gcore.jsdelivr.net/gh/${REPO}/dsh-purge.tgz" \
    "https://cdn.jsdelivr.net/gh/${REPO}@${REL}/dsh-purge.tgz" \
    "https://gh-proxy.org/https://github.com/${REPO}/releases/download/${REL}/dsh-purge.tgz" \
    "https://ghproxy.net/https://github.com/${REPO}/releases/download/${REL}/dsh-purge.tgz" \
    "https://github.com/${REPO}/releases/download/${REL}/dsh-purge.tgz"
  do
    log "正在下载安装包 $url"
    if fetch "$url" "$TGZ" && [[ "$(wc -c < "$TGZ" | tr -d ' ')" -ge 100000 ]] && is_gzip "$TGZ"; then
      return
    fi
    log "该源不可用，换下一个。"
  done
  die "安装包下载失败。请检查网络后重试同一条命令。"
}

if ! have curl && ! have wget; then
  die "未找到 curl 或 wget。"
fi

mkdir -p "$BOOT"
refresh_path
resolve_node
select_registries
use_registry "${REGISTRIES[0]}"
log "npm 将优先使用 ${REGISTRIES[0]}，失败时自动换源。"

if ! have dsh; then
  npm_install_global @deepseek-ai/dsh || die "npm 安装 @deepseek-ai/dsh 失败。"
fi
if ! have dsh; then
  die "仍未找到 dsh。请新开一个终端后再执行。"
fi

if ! have pnpm; then
  npm_install_global pnpm --allow-scripts=pnpm || npm_install_global pnpm || die "npm 安装 pnpm 失败。"
fi
if ! have pnpm; then
  die "仍未找到 pnpm。请新开一个终端后再执行。"
fi

save_tarball

PROFILE="${1:-}"
if [[ -z "$PROFILE" ]]; then
  dsh plugin --profile web add "$TGZ"
  dsh plugin --profile default add "$TGZ" || true
  log "已写入。请完全退出 dsh web / 桌面客户端后重新打开，再应用补丁或发送 /purge apply。"
  exit 0
fi
dsh plugin --profile "$PROFILE" add "$TGZ"
