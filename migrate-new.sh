#!/bin/bash
#
# migrate-new.sh — 新服务器还原脚本
# 使用方法: bash migrate-new.sh
#
# 执行前请确认：
# 1. migrate-old.sh 已在旧服务器执行完成
# 2. 迁移包已传到新服务器 ~/openclaw-migration/
#

set -e

echo "=========================================="
echo "  OpenClaw 新服务器还原脚本"
echo "=========================================="

MIGRATION_DIR="$HOME/openclaw-migration"

# --- OS 检测 ---
# 优先读取旧服务器指定的 target OS，否则自动检测
if [ -f "${MIGRATION_DIR}/target-os.txt" ]; then
  TARGET_OS="$(cat ${MIGRATION_DIR}/target-os.txt | tr -d '[:space:]')"
  echo "检测到目标平台标记: $TARGET_OS（来自迁移包）"
else
  TARGET_OS="$(uname | tr '[:upper:]' '[:lower:]')"
  echo "未检测到目标平台标记，自动识别: $TARGET_OS"
fi

case "$TARGET_OS" in
  mac|macos)
    TARGET_OS="darwin"
    echo "使用 macOS 解压模式"
    ;;
  linux)
    echo "使用 Linux 解压模式"
    ;;
  darwin)
    echo "使用 macOS 解压模式"
    ;;
  *)
    echo "未知目标平台: $TARGET_OS，将尝试自动检测"
    TARGET_OS="$(uname | tr '[:upper:]' '[:lower:]')"
    ;;
esac

# --- npm 版本检查函数 ---
npm_ensure() {
  PKG="$1"
  EXPECTED="$2"
  if [ -z "$EXPECTED" ]; then
    echo "  [SKIP] $PKG (未指定版本)"
    return
  fi
  CURRENT=$(npm list -g "$PKG" --depth=0 --silent 2>/dev/null | grep "$PKG@" | sed "s/.*$PKG@//" | tr -d ' ' | head -1)
  if [ "$CURRENT" = "$EXPECTED" ]; then
    echo "  [OK] $PKG@$CURRENT 已安装，跳过"
  else
    if [ -n "$CURRENT" ]; then
      echo "  [WARN] $PKG@$CURRENT != $EXPECTED，将覆盖安装"
    else
      echo "  [INFO] $PKG 未安装，开始安装..."
    fi
    npm install -g "$PKG@$EXPECTED"
  fi
}

# --- 步骤1：检查/安装 Node.js ---
echo ""
echo "[1/8] 检查 Node.js..."
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  \. "$NVM_DIR/nvm.sh"
fi

if command -v node &>/dev/null; then
  echo "  Node.js: $(node --version)"
else
  echo "  Node.js 未安装，正在安装 nvm..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  nvm install 24
  nvm use 24
fi

# --- 步骤2：安装 OpenClaw + 插件 ---
echo ""
echo "[2/8] 检查/安装 OpenClaw + 插件..."
# ★ 在此填写需要迁移的插件及版本
npm_ensure "openclaw" ""
npm_ensure "@larksuite/openclaw-lark" ""
npm_ensure "@tencent-weixin/openclaw-weixin" ""
echo "  OpenClaw: $(openclaw --version)"

# --- 步骤3：检查迁移包 ---
echo ""
echo "[3/8] 检查迁移包..."
if [ ! -d "${MIGRATION_DIR}" ]; then
  echo "  错误：未找到迁移包目录 ${MIGRATION_DIR}"
  echo "  请先在旧服务器执行 migrate-old.sh 并传输迁移包"
  exit 1
fi
echo "  迁移包内容："
ls -lh ${MIGRATION_DIR}/

# --- 步骤4：解压配置 ---
echo ""
echo "[4/8] 解压配置..."

if [ "$TARGET_OS" = "darwin" ] || [ "$TARGET_OS" = "macos" ]; then
  # macOS: 解压到 HOME，然后移动 .openclaw 到正确位置
  echo "  [macOS 模式] 解压到 HOME 目录..."
  tar -xzf ${MIGRATION_DIR}/openclaw-config.tar.gz -C $HOME/

  # macOS SIP 可能将 root 目录的文件放在 $HOME/root/ 下
  if [ -d "$HOME/root" ] && [ -d "$HOME/root/.openclaw" ]; then
    echo "  检测到 SIP 隔离目录，移动到正确位置..."
    sudo mv $HOME/root/.openclaw $HOME/
    sudo rm -rf $HOME/root
  fi
else
  # Linux: 直接解压到根目录
  echo "  [Linux 模式] 解压到系统根目录..."
  sudo tar -xzf ${MIGRATION_DIR}/openclaw-config.tar.gz -C /
fi
echo "  解压完成"

# --- 步骤5：修正权限 ---
echo ""
echo "[5/8] 修正权限..."
if [ "$TARGET_OS" = "darwin" ] || [ "$TARGET_OS" = "macos" ]; then
  sudo chown -R $(whoami):$(id -gn) $HOME/.openclaw/ 2>/dev/null || \
    chown -R $(whoami):$(id -gn) $HOME/.openclaw/
else
  sudo chown -R $(whoami):$(id -gn) $HOME/.openclaw/
fi
echo "  权限修正完成"

# --- 步骤6：安装 OpenClaw Gateway ---
echo ""
echo "[6/8] 安装 OpenClaw Gateway..."
openclaw gateway stop 2>/dev/null || true
openclaw gateway install 2>/dev/null || echo "  Gateway 可能已安装或无需额外安装，跳过"

# --- 步骤7：启动 Gateway ---
echo ""
echo "[7/8] 启动 Gateway..."
openclaw gateway start
sleep 2

# --- 步骤8：完整性验证 ---
echo ""
echo "[8/8] 完整性验证..."
echo ""
echo "=== 版本 ==="
openclaw --version
echo ""
echo "=== Gateway 状态 ==="
openclaw gateway status
echo ""
echo "=== RPC Probe ==="
openclaw gateway probe || echo "  probe 失败，请检查"
echo ""
echo "=== 插件列表 ==="
openclaw plugins list 2>/dev/null || echo "(无可用插件命令)"
echo ""
echo "=== 配置文件 ==="
ls $HOME/.openclaw/ 2>/dev/null | head -10
echo ""
echo "=== Cron 任务 ==="
cat $HOME/.openclaw/cron/jobs.json 2>/dev/null || echo "(空)"
echo ""
echo "=== Memory ==="
ls $HOME/.openclaw/memory/ 2>/dev/null || echo "(空)"

echo ""
echo "=========================================="
echo "  还原完成!"
echo "=========================================="
