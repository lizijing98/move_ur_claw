#!/bin/bash
#
# migrate-old.sh — 旧服务器打包脚本
# 使用方法: bash migrate-old.sh [选项]
#
# 选项：
#   --target  <linux|darwin>   目标服务器操作系统类型（默认: linux）
#   --scp     <yes|no>         是否通过 scp 传输到新服务器（默认: yes）
#
# 示例：
#   bash migrate-old.sh --target linux --scp yes
#   bash migrate-old.sh --target darwin --scp no
#

set -e

# --- 参数解析 ---
TARGET_OS="linux"
DO_SCP="yes"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET_OS="$2"
      shift 2
      ;;
    --scp)
      DO_SCP="$2"
      shift 2
      ;;
    *)
      echo "未知参数: $1"
      echo "用法: bash migrate-old.sh [--target linux|darwin] [--scp yes|no]"
      exit 1
      ;;
  esac
done

echo "=========================================="
echo "  OpenClaw 旧服务器打包脚本"
echo "=========================================="
echo "  目标系统: $TARGET_OS"
echo "  传输方式: $([ "$DO_SCP" = "yes" ] && echo "scp" || echo "手动")"
echo "=========================================="

MIGRATION_DIR="$HOME/openclaw-migration"

# --- 步骤1：创建打包目录 ---
echo ""
echo "[1/7] 创建打包目录..."
mkdir -p ${MIGRATION_DIR}

# --- 步骤2：打包 .openclaw ---
echo "[2/7] 打包 .openclaw 配置..."
tar -czf ${MIGRATION_DIR}/openclaw-config.tar.gz \
  $HOME/.openclaw/ 2>/dev/null || true
echo "  完成: openclaw-config.tar.gz ($(du -sh ${MIGRATION_DIR}/openclaw-config.tar.gz 2>/dev/null | cut -f1))"

# --- 步骤3：导出 npm 全局包版本 ---
echo "[3/7] 导出 npm 版本清单..."
npm list -g --depth=0 --json 2>/dev/null | grep -E '"openclaw|clawhub"' > ${MIGRATION_DIR}/npm-packages.json || true
echo "  完成"

# --- 步骤4：复制还原脚本 ---
echo "[4/7] 复制还原脚本..."
SCRIPT_SRC="$(dirname "$(realpath "$0")")/migrate-new.sh"
if [ -f "$SCRIPT_SRC" ]; then
  cp "$SCRIPT_SRC" ${MIGRATION_DIR}/migrate-new.sh
  echo "  完成"
else
  echo "  警告: 找不到 migrate-new.sh，请确保两个脚本在同一目录"
fi

# --- 步骤5：生成目标 OS 标识 ---
echo "[5/7] 生成目标平台标识..."
echo "$TARGET_OS" > ${MIGRATION_DIR}/target-os.txt
echo "  目标平台: $TARGET_OS"

# --- 步骤6：验证打包结果 ---
echo "[6/7] 验证打包结果..."
echo ""
ls -lh ${MIGRATION_DIR}/
echo ""

# --- 步骤7：传输 / 关闭 ---
if [ "$DO_SCP" = "yes" ]; then
  echo "[7/7] 传输到新服务器..."
  echo "请输入新服务器地址（IP 或域名）："
  read -r REMOTE_HOST
  if [ -z "$REMOTE_HOST" ]; then
    echo "  地址为空，跳过传输。请手动复制 ${MIGRATION_DIR} 目录到新服务器"
  else
    REMOTE_USER=$(whoami)
    echo "  正在传输到 ${REMOTE_USER}@${REMOTE_HOST}:$HOME/ ..."
    scp -r ${MIGRATION_DIR} ${REMOTE_USER}@${REMOTE_HOST}:$HOME/
    echo "  传输完成"
  fi
else
  echo "[7/7] 跳过传输（--scp no）"
  echo "  请手动复制 ${MIGRATION_DIR} 目录到新服务器"
fi

echo ""
echo "[完成] 关闭 OpenClaw Gateway..."
openclaw gateway stop 2>/dev/null || echo "  Gateway 未在运行"

echo ""
echo "=========================================="
echo "  打包完成!"
echo "=========================================="
echo ""
if [ "$DO_SCP" = "yes" ] && [ -n "$REMOTE_HOST" ]; then
  echo "请 SSH 到新服务器，执行以下命令："
  echo ""
  echo "  cd \$HOME/openclaw-migration"
  echo "  bash migrate-new.sh"
else
  echo "迁移包位于: ${MIGRATION_DIR}"
  echo "请将其复制到新服务器后，执行："
  echo ""
  echo "  cd \$HOME/openclaw-migration"
  echo "  bash migrate-new.sh"
fi
echo ""
