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
OS_TYPE="$(uname)"
if [ "$OS_TYPE" = "Darwin" ]; then
  echo "检测到 macOS，将使用适合 macOS 的解压方式"
elif [ "$OS_TYPE" = "Linux" ]; then
  echo "检测到 Linux，将使用适合 Linux 的解压方式"
else
  echo "检测到未知系统: $OS_TYPE"
  echo "继续执行，如有问题请手动调整"
fi

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

# 检测是否有 GNU tar（Linux 常用）或 BSD tar（macOS 自带）
TAR_HAS_WARNING=0
tar --version &>/dev/null && TAR_HAS_WARNING=1

if [ "$OS_TYPE" = "Darwin" ]; then
  # macOS: 解压到 HOME，然后移动 .openclaw 到正确位置
  echo "  [macOS 模式] 解压到 HOME 目录..."
  tar -xzvf ${MIGRATION_DIR}/openclaw-config.tar.gz -C $HOME/ 2>/dev/null || \
    tar -xzvf ${MIGRATION_DIR}/openclaw-config.tar.gz -C $HOME/

  # macOS SIP 可能将 root 目录的文件放在 $HOME/root/ 下
  if [ -d "$HOME/root" ] && [ -d "$HOME/root/.openclaw" ]; then
    echo "  检测到 SIP 隔离目录，移动到正确位置..."
    sudo mv $HOME/root/.openclaw $HOME/
    sudo rm -rf $HOME/root
  fi
elif [ "$OS_TYPE" = "Linux" ]; then
  # Linux: 直接解压到根目录
  echo "  [Linux 模式] 解压到系统根目录..."
  if [ $TAR_HAS_WARNING -eq 1 ]; then
    sudo tar --warning=no-file-changed -xzvf ${MIGRATION_DIR}/openclaw-config.tar.gz -C / 2>/dev/null || \
      sudo tar -xzvf ${MIGRATION_DIR}/openclaw-config.tar.gz -C /
  else
    sudo tar -xzvf ${MIGRATION_DIR}/openclaw-config.tar.gz -C / 2>/dev/null || \
      sudo tar -xzvf ${MIGRATION_DIR}/openclaw-config.tar.gz -C /
  fi
else
  echo "  [兼容模式] 解压到 HOME 目录..."
  tar -xzvf ${MIGRATION_DIR}/openclaw-config.tar.gz -C $HOME/
fi

# --- 步骤5：修正权限 ---
echo ""
echo "[5/8] 修正权限..."
if [ "$OS_TYPE" = "Darwin" ]; then
  # macOS 上 Homebrew 等通常不依赖系统 /usr/local 的权限
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
