#!/bin/bash
#
# migrate-old.sh — 旧服务器打包脚本
# 使用方法: bash migrate-old.sh <新服务器IP或域名>
#
# 执行前请确认：
# 1. 当前是旧服务器（已有 ~/.openclaw 配置）
# 2. 新服务器 SSH 端口为 22（非 22 端口请手动修改 scp 命令）
#

set -e

echo "=========================================="
echo "  OpenClaw 旧服务器打包脚本"
echo "=========================================="

MIGRATION_DIR="$HOME/openclaw-migration"
REMOTE_HOST="${1:-}"

if [ -z "$REMOTE_HOST" ]; then
  echo "用法: bash migrate-old.sh <新服务器IP或域名>"
  echo ""
  echo "示例: bash migrate-old.sh 192.168.1.100"
  echo "      bash migrate-old.sh new-server.example.com"
  exit 1
fi

REMOTE_USER=$(whoami)
echo "当前用户: $REMOTE_USER"
echo "目标服务器: $REMOTE_HOST"

# --- 步骤1：创建打包目录 ---
echo ""
echo "[1/7] 创建打包目录..."
mkdir -p ${MIGRATION_DIR}

# --- 步骤2：打包 .openclaw ---
echo "[2/7] 打包 .openclaw 配置..."
tar -czvf ${MIGRATION_DIR}/openclaw-config.tar.gz \
  $HOME/.openclaw/ 2>/dev/null || true

# --- 步骤3：导出 npm 全局包版本 ---
echo "[3/7] 导出 npm 版本清单..."
npm list -g --depth=0 --json 2>/dev/null | grep -E '"openclaw|clawhub"' > ${MIGRATION_DIR}/npm-packages.json || true

# --- 步骤4：复制还原脚本 ---
echo "[4/7] 复制还原脚本..."
SCRIPT_SRC="$(dirname "$(realpath "$0")")/migrate-new.sh"
if [ -f "$SCRIPT_SRC" ]; then
  cp "$SCRIPT_SRC" ${MIGRATION_DIR}/migrate-new.sh
  echo "  已复制: $SCRIPT_SRC"
else
  echo "  警告: 找不到 migrate-new.sh，请确保两个脚本在同一目录"
fi

# --- 步骤5：验证打包结果 ---
echo "[5/7] 验证打包结果..."
echo ""
ls -lh ${MIGRATION_DIR}/
echo ""

# --- 步骤6：传输到新服务器 ---
echo "[6/7] 传输到新服务器..."
echo "请输入新服务器密码（可能多次）..."
scp -r ${MIGRATION_DIR} ${REMOTE_USER}@${REMOTE_HOST}:$HOME/

# --- 步骤7：关闭 OpenClaw Gateway ---
echo "[7/7] 关闭 OpenClaw Gateway..."
openclaw gateway stop 2>/dev/null || echo "  Gateway 未在运行，跳过"

echo ""
echo "=========================================="
echo "  打包 + 传输完成!"
echo "=========================================="
echo ""
echo "请 SSH 到新服务器，执行以下命令："
echo ""
echo "  cd \$HOME/openclaw-migration"
echo "  bash migrate-new.sh"
echo ""
