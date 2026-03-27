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

# --- 版本清单读取函数（纯 Node.js）---
read_manifest() {
  node -e "
const fs = require('fs');
const path = require('path');
const manifestPath = path.join(process.env.HOME || '$HOME', 'openclaw-migration', 'versions-manifest.json');
if (fs.existsSync(manifestPath)) {
  const m = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  console.log(JSON.stringify(m));
} else {
  console.log('null');
}
" 2>/dev/null
}

# --- npm 版本检查函数 ---
npm_ensure() {
  PKG="$1"
  EXPECTED="$2"
  if [ -z "$EXPECTED" ] || [ "$EXPECTED" = "unknown" ]; then
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

# --- 步骤1：读取版本清单 ---
echo ""
echo "[1/9] 读取版本清单..."
MANIFEST_JSON=$(read_manifest)
if [ "$MANIFEST_JSON" = "null" ] || [ -z "$MANIFEST_JSON" ]; then
  echo "  警告: 未找到 versions-manifest.json，将使用默认值"
  MANIFEST_JSON='{}'
fi
echo "  版本清单已加载"

# --- 步骤2：检查/安装 Node.js ---
echo ""
echo "[2/9] 检查 Node.js..."
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

# --- 步骤3：安装 OpenClaw + 插件（按版本清单）---
echo ""
echo "[3/9] 安装 OpenClaw + 插件..."

# 从清单提取版本
NPM_PKGS=$(echo "$MANIFEST_JSON" | node -e "
const fs = require('fs');
const stdin = fs.readFileSync('/dev/stdin', 'utf8');
const m = JSON.parse(stdin);
const pkgs = m.npm_packages || {};
Object.entries(pkgs).forEach(([k,v]) => console.log(k + '|' + v));
" 2>/dev/null)

echo "$NPM_PKGS" | while IFS='|' read -r PKG VER; do
  [ -z "$PKG" ] && continue
  npm_ensure "$PKG" "$VER"
done

# 兜底：如果清单为空或只有 openclaw
if [ -z "$NPM_PKGS" ]; then
  echo "  [INFO] 清单为空，安装默认版本..."
  npm_ensure "openclaw" ""
  npm_ensure "@larksuite/openclaw-lark" ""
  npm_ensure "@tencent-weixin/openclaw-weixin" ""
fi

echo "  OpenClaw: $(openclaw --version 2>/dev/null || echo 'unknown')"

# --- 步骤4：检查迁移包 ---
echo ""
echo "[4/9] 检查迁移包..."
if [ ! -d "${MIGRATION_DIR}" ]; then
  echo "  错误：未找到迁移包目录 ${MIGRATION_DIR}"
  echo "  请先在旧服务器执行 migrate-old.sh 并传输迁移包"
  exit 1
fi
echo "  迁移包内容："
ls -lh ${MIGRATION_DIR}/

# --- 步骤5：解压配置 ---
echo ""
echo "[5/9] 解压配置..."

if [ "$TARGET_OS" = "darwin" ] || [ "$TARGET_OS" = "macos" ]; then
  echo "  [macOS 模式] 解压到 HOME 目录..."
  tar -xzf ${MIGRATION_DIR}/openclaw-config.tar.gz -C $HOME/

  if [ -d "$HOME/root" ] && [ -d "$HOME/root/.openclaw" ]; then
    echo "  检测到 SIP 隔离目录，移动到正确位置..."
    sudo mv $HOME/root/.openclaw $HOME/
    sudo rm -rf $HOME/root
  fi
else
  echo "  [Linux 模式] 解压到系统根目录..."
  sudo tar -xzf ${MIGRATION_DIR}/openclaw-config.tar.gz -C /
fi
echo "  解压完成"

# --- 步骤6：修正权限 ---
echo ""
echo "[6/9] 修正权限..."
if [ "$TARGET_OS" = "darwin" ] || [ "$TARGET_OS" = "macos" ]; then
  sudo chown -R $(whoami):$(id -gn) $HOME/.openclaw/ 2>/dev/null || \
    chown -R $(whoami):$(id -gn) $HOME/.openclaw/
else
  sudo chown -R $(whoami):$(id -gn) $HOME/.openclaw/
fi
echo "  权限修正完成"

# --- 步骤7：安装 clawhub skills（按清单）---
echo ""
echo "[7/9] 安装 clawhub skills..."
if [ -f "${MIGRATION_DIR}/clawhub-skills.json" ]; then
  SKILL_COUNT=$(cat ${MIGRATION_DIR}/clawhub-skills.json | node -e "
const fs = require('fs');
const data = JSON.parse(fs.readFileSync('/dev/stdin', 'utf8'));
console.log(data.length);
" 2>/dev/null || echo "0")
  echo "  清单中共 $SKILL_COUNT 个 skills"

  if command -v clawhub &>/dev/null && [ "$SKILL_COUNT" -gt 0 ]; then
    cat ${MIGRATION_DIR}/clawhub-skills.json | node -e "
const fs = require('fs');
const { execSync } = require('child_process');
const skills = JSON.parse(fs.readFileSync('/dev/stdin', 'utf8'));
skills.forEach(skill => {
  const name = skill.name || skill;
  const ver = skill.version ? '@' + skill.version : '';
  console.log('Installing:', name + ver);
  try {
    execSync('clawhub install ' + name + ver + ' 2>/dev/null', { stdio: 'pipe' });
    console.log('  OK:', name);
  } catch(e) {
    console.log('  SKIP:', name, e.message.slice(0, 50));
  }
});
" 2>/dev/null || echo "  clawhub 安装跳过"
  else
    echo "  clawhub 未安装或清单为空，跳过"
  fi
else
  echo "  未找到 clawhub-skills.json，跳过"
fi

# --- 步骤8：安装 OpenClaw Gateway ---
echo ""
echo "[8/9] 安装 OpenClaw Gateway..."
openclaw gateway stop 2>/dev/null || true
openclaw gateway install 2>/dev/null || echo "  Gateway 可能已安装或无需额外安装，跳过"

# --- 步骤9：启动 Gateway + 完整性验证 ---
echo ""
echo "[9/9] 启动 Gateway + 完整性验证..."
openclaw gateway start
sleep 2

echo ""
echo "=========================================="
echo "  完整性验证报告"
echo "=========================================="
echo ""
echo "=== 版本信息 ==="
openclaw --version
echo ""
echo "=== Gateway 状态 ==="
openclaw gateway status 2>/dev/null || echo "(状态查询失败)"
echo ""
echo "=== 插件列表 ==="
openclaw plugins list 2>/dev/null | grep -E "^│|loaded|disabled" | head -20 || echo "(无可用插件)"
echo ""

# --- 版本一致性校验 ---
echo "=== 版本一致性校验 ==="
MANIFEST_VER=$(echo "$MANIFEST_JSON" | node -e "
const fs = require('fs');
const m = JSON.parse(fs.readFileSync('/dev/stdin', 'utf8'));
console.log(m.openclaw_version || 'unknown');
" 2>/dev/null || echo "unknown")
CURRENT_VER=$(openclaw --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
if [ "$MANIFEST_VER" = "$CURRENT_VER" ]; then
  echo "  [OK] OpenClaw 版本一致: $CURRENT_VER"
else
  echo "  [WARN] OpenClaw 版本不一致 - 清单: $MANIFEST_VER, 当前: $CURRENT_VER"
fi

echo ""
echo "=== NPM 包清单 ==="
if [ -f "${MIGRATION_DIR}/npm-packages.json" ]; then
  cat ${MIGRATION_DIR}/npm-packages.json | node -e "
const fs = require('fs');
const { execSync } = require('child_process');
const pkgs = JSON.parse(fs.readFileSync('/dev/stdin', 'utf8'));
Object.entries(pkgs).forEach(([name, ver]) => {
  try {
    const current = execSync('npm list -g ' + name + ' --depth=0 --silent 2>/dev/null', { encoding: 'utf8' });
    const found = current.match(/@[\w-]+\/[\w-]+@(\d+\.\d+\.\d+)/);
    const status = found && found[1] === ver ? '[OK]' : '[WARN]';
    console.log(status, name + '@' + ver);
  } catch(e) {
    console.log('[??]', name + '@' + ver);
  }
});
" 2>/dev/null || cat ${MIGRATION_DIR}/npm-packages.json
else
  echo "(无可用清单)"
fi

echo ""
echo "=== 配置文件 ==="
ls $HOME/.openclaw/ 2>/dev/null | head -15
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
echo ""
echo "请检查上方核对结果，如有异常请手动排查。"
echo ""
