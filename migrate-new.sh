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
echo "[2/8] 检查/安装 OpenClaw + 插件..."
# ★ 在此填写需要迁移的插件及版本
npm_ensure "openclaw" ""
npm_ensure "@larksuite/openclaw-lark" ""
npm_ensure "@tencent-weixin/openclaw-weixin" ""
echo "  OpenClaw: $(openclaw --version)"

# --- 步骤3：检查迁移包 ---
echo "[3/8] 检查迁移包..."
if [ ! -d "${MIGRATION_DIR}" ]; then
  echo "  错误：未找到迁移包目录 ${MIGRATION_DIR}"
  echo "  请先在旧服务器执行 migrate-old.sh 并传输迁移包"
  exit 1
fi
echo "  迁移包内容："
ls -lh ${MIGRATION_DIR}/

# --- 步骤4：解压配置 ---
echo "[4/8] 解压配置..."
sudo tar -xzvf ${MIGRATION_DIR}/openclaw-config.tar.gz -C /

# --- 步骤5：修正权限 ---
echo "[5/8] 修正权限..."
sudo chown -R $(whoami):$(id -gn) $HOME/.openclaw/

# --- 步骤6：安装 / 更新 OpenClaw Gateway ---
echo "[6/8] 安装 OpenClaw Gateway..."
openclaw gateway stop 2>/dev/null || true
openclaw gateway install 2>/dev/null || echo "  Gateway 可能已安装，跳过"
openclaw gateway start
sleep 2

# --- 步骤7：启动 Gateway ---
echo "[7/8] 启动 Gateway..."
openclaw gateway start
sleep 2

# --- 步骤8：完整性验证 ---
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
