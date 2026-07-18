#!/bin/bash
set -euo pipefail

REPOSITORY="aibo204/codex-usage-orb"
ARCHIVE_URL="https://github.com/${REPOSITORY}/archive/refs/heads/main.tar.gz"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-orb.XXXXXX")"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Codex Usage Orb 目前只支持 macOS。"
  exit 1
fi

if ! xcode-select -p >/dev/null 2>&1 || ! xcrun swiftc --version >/dev/null 2>&1; then
  echo "首次安装需要 Apple 命令行工具，系统即将弹出安装窗口。"
  xcode-select --install 2>/dev/null || true
  echo "安装完成后，请再次运行刚才的命令。"
  exit 1
fi

echo "正在下载 Codex Usage Orb…"
curl -fsSL --retry 3 "$ARCHIVE_URL" -o "$TEMP_DIR/source.tar.gz"
tar -xzf "$TEMP_DIR/source.tar.gz" -C "$TEMP_DIR"

SOURCE_DIR="$TEMP_DIR/codex-usage-orb-main"
echo "正在本机编译，不会上传任何 Codex 数据…"
chmod +x "$SOURCE_DIR/build-app.sh"
"$SOURCE_DIR/build-app.sh" >/dev/null

SOURCE_APP="$SOURCE_DIR/dist/Codex Usage Orb.app"
INSTALL_DIR="$HOME/Applications"
INSTALL_APP="$INSTALL_DIR/Codex Usage Orb.app"

mkdir -p "$INSTALL_DIR"
pkill -x CodexUsageOrb 2>/dev/null || true
ditto "$SOURCE_APP" "$INSTALL_APP"
open "$INSTALL_APP"

echo ""
echo "✅ 安装完成，悬浮球已经启动。"
echo "应用位置：$INSTALL_APP"
