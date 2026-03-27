#!/bin/bash
#
# migrate-old.sh — 旧服务器打包脚本
# 使用方法: bash migrate-old.sh [选项]
#
# 选项：
#   --target  <linux|darwin|mac>   目标服务器操作系统类型（默认: linux）
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
      echo "用法: bash migrate-old.sh [--target linux|darwin|mac] [--scp yes|no]"
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
EXPORT_TIME=$(date -Iseconds)

# --- 步骤1：创建打包目录 ---
echo ""
echo "[1/8] 创建打包目录..."
mkdir -p ${MIGRATION_DIR}

# --- 步骤2：打包 .openclaw ---
echo "[2/8] 打包 .openclaw 配置..."
tar -czf ${MIGRATION_DIR}/openclaw-config.tar.gz \
  $HOME/.openclaw/ 2>/dev/null || true
echo "  完成: openclaw-config.tar.gz ($(du -sh ${MIGRATION_DIR}/openclaw-config.tar.gz 2>/dev/null | cut -f1))"

# --- 步骤3：复制还原脚本 ---
echo "[3/8] 复制还原脚本..."
SCRIPT_SRC="$(dirname "$(realpath "$0")")/migrate-new.sh"
if [ -f "$SCRIPT_SRC" ]; then
  cp "$SCRIPT_SRC" ${MIGRATION_DIR}/migrate-new.sh
  echo "  完成"
else
  echo "  警告: 找不到 migrate-new.sh"
fi

# --- 步骤4：生成目标 OS 标识 ---
echo "[4/8] 生成目标平台标识..."
echo "$TARGET_OS" > ${MIGRATION_DIR}/target-os.txt
echo "  目标平台: $TARGET_OS"

# --- 步骤5：导出 npm 全局包版本（纯 Node.js）---
echo "[5/8] 导出 npm 全局包版本..."
node -e "
const { execSync } = require('child_process');
const fs = require('fs');

const list = execSync('npm list -g --depth=0 --json 2>/dev/null', { encoding: 'utf8' });
const data = JSON.parse(list);
const pkgs = {};

Object.entries(data.dependencies || {}).forEach(([name, info]) => {
  if (name.startsWith('openclaw') || name.startsWith('@larksuite/') || 
      name.startsWith('@tencent-') || name.startsWith('clawhub')) {
    pkgs[name] = info.version || 'unknown';
  }
});

fs.writeFileSync('${MIGRATION_DIR}/npm-packages.json', JSON.stringify(pkgs, null, 2));
console.log('  导出完成，共 ' + Object.keys(pkgs).length + ' 个包');
" 2>/dev/null || echo "  npm 导出跳过"
cat ${MIGRATION_DIR}/npm-packages.json 2>/dev/null | head -20 || echo "  (无可用 npm 包)"

# --- 步骤6：导出 clawhub skills 列表 ---
echo ""
echo "[6/8] 导出 clawhub skills..."
if command -v clawhub &>/dev/null; then
  CLAWHUB_SKILLS="[]"
  if clawhub list &>/dev/null; then
    # 尝试 JSON 输出
    CLAWHUB_SKILLS=$(clawhub list --json 2>/dev/null) || CLAWHUB_SKILLS="[]"
  fi
  # 如果不是有效 JSON，尝试解析文本输出
  if ! echo "$CLAWHUB_SKILLS" | node -e "JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'))" 2>/dev/null; then
    # 降级：从 openclaw skills 目录读取
    CLAWHUB_SKILLS=$(node -e "
const fs = require('fs');
const path = require('path');
const skillsDir = '${HOME}/.openclaw/workspace/skills';
const list = [];
if (fs.existsSync(skillsDir)) {
  fs.readdirSync(skillsDir).forEach(name => {
    const skillJson = path.join(skillsDir, name, 'package.json');
    if (fs.existsSync(skillJson)) {
      try {
        const pkg = JSON.parse(fs.readFileSync(skillJson, 'utf8'));
        list.push({ name: pkg.name, version: pkg.version || 'unknown' });
      } catch(e) {}
    }
  });
}
console.log(JSON.stringify(list));
" 2>/dev/null)
  fi
  echo "$CLAWHUB_SKILLS" > ${MIGRATION_DIR}/clawhub-skills.json
  SKILL_COUNT=$(echo "$CLAWHUB_SKILLS" | node -e "console.log(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).length)" 2>/dev/null || echo "0")
  echo "  导出完成，共 $SKILL_COUNT 个 skills"
else
  echo "  clawhub 未安装，跳过"
  echo "[]" > ${MIGRATION_DIR}/clawhub-skills.json
fi

# --- 步骤7：导出 plugins installs 元数据（纯 Node.js）---
echo ""
echo "[7/8] 导出插件安装元数据..."
node -e "
const fs = require('fs');
const path = require('path');

const configPath = path.join(process.env.HOME || '$HOME', '.openclaw', 'openclaw.json');
let installs = {};

if (fs.existsSync(configPath)) {
  try {
    const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    installs = config.plugins?.installs || {};
  } catch(e) {
    console.error('  解析 openclaw.json 失败:', e.message);
  }
} else {
  console.log('  openclaw.json 不存在，跳过');
}

fs.writeFileSync('${MIGRATION_DIR}/plugin-installs.json', JSON.stringify(installs, null, 2));
console.log('  导出完成，共 ' + Object.keys(installs).length + ' 个插件');
" 2>/dev/null || echo "  插件元数据导出跳过"

# --- 步骤8：生成统一版本清单（versions-manifest.json，纯 Node.js）---
echo ""
echo "[8/8] 生成统一版本清单..."
node -e "
const fs = require('fs');
const { execSync } = require('child_process');

const HOME = process.env.HOME || '$HOME';

// 收集版本信息
const manifest = {
  created_at: '${EXPORT_TIME}',
  target_os: '${TARGET_OS}',
  openclaw_version: 'unknown',
  node_version: 'unknown',
  npm_packages: {},
  clawhub_skills: [],
  plugin_installs: {}
};

// OpenClaw 版本
try {
  const ver = execSync('openclaw --version 2>/dev/null', { encoding: 'utf8' });
  manifest.openclaw_version = ver.match(/\d+\.\d+\.\d+/) ? ver.match(/\d+\.\d+\.\d+/)[0] : ver.trim();
} catch(e) {}

// Node 版本
try {
  manifest.node_version = execSync('node --version 2>/dev/null', { encoding: 'utf8' }).trim().replace('v', '');
} catch(e) {}

// NPM 包
try {
  const npmList = JSON.parse(execSync('npm list -g --depth=0 --json 2>/dev/null', { encoding: 'utf8' }));
  Object.entries(npmList.dependencies || {}).forEach(([name, info]) => {
    if (name.startsWith('openclaw') || name.startsWith('@larksuite/') || 
        name.startsWith('@tencent-') || name.startsWith('clawhub')) {
      manifest.npm_packages[name] = info.version || 'unknown';
    }
  });
} catch(e) {}

// Clawhub Skills
try {
  const skillsFile = path.join(HOME, 'openclaw-migration', 'clawhub-skills.json');
  if (fs.existsSync(skillsFile)) {
    manifest.clawhub_skills = JSON.parse(fs.readFileSync(skillsFile, 'utf8'));
  }
} catch(e) {}

// Plugin Installs
try {
  const installsFile = path.join(HOME, 'openclaw-migration', 'plugin-installs.json');
  if (fs.existsSync(installsFile)) {
    manifest.plugin_installs = JSON.parse(fs.readFileSync(installsFile, 'utf8'));
  }
} catch(e) {}

fs.writeFileSync(path.join(HOME, 'openclaw-migration', 'versions-manifest.json'), JSON.stringify(manifest, null, 2));
console.log('  版本清单已生成: versions-manifest.json');
console.log('  - OpenClaw: ' + manifest.openclaw_version);
console.log('  - Node: v' + manifest.node_version);
console.log('  - NPM 包: ' + Object.keys(manifest.npm_packages).length + ' 个');
console.log('  - Skills: ' + manifest.clawhub_skills.length + ' 个');
console.log('  - 插件: ' + Object.keys(manifest.plugin_installs).length + ' 个');
"

# --- 验证打包结果 ---
echo ""
echo "=========================================="
echo "  打包结果验证"
echo "=========================================="
ls -lh ${MIGRATION_DIR}/
echo ""

# --- 传输 / 关闭 ---
if [ "$DO_SCP" = "yes" ]; then
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
  echo "跳过传输（--scp no）"
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
