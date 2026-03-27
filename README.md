# OpenClaw 搬家指南 🦞🏠

> 将你的 OpenClaw 从一台主机迁移到另一台，支持 Linux/macOS 之间零差异迁移。

---

## 核心特性

- ✅ **版本清单同步** — 自动导出 npm 包、clawhub skills、插件版本的完整清单
- ✅ **零差异迁移** — 新服务器安装与旧服务器完全一致的版本
- ✅ **纯 Shell + Node.js** — 不依赖 Python，仅需 Node.js 环境
- ✅ **多平台支持** — Linux ↔ Linux、macOS ↔ Linux、macOS ↔ macOS

---

## 迁移流程

### 第一阶段：旧主机打包

| 步骤 | 操作 | 说明 |
|:---:|------|------|
| 1 | 执行 `migrate-old.sh` | 打包配置、导出插件版本、传输到新主机 |
| 2 | 等待脚本完成 | 自动执行 `openclaw gateway stop` |

### 第二阶段：新主机还原

| 步骤 | 操作 | 说明 |
|:---:|------|------|
| 1 | 执行 `migrate-new.sh` | 自动检测系统、安装环境、还原配置 |
| 2 | 验证迁移结果 | 检查版本一致性报告、Gateway 状态 |

---

## 脚本使用说明

### 1️⃣ migrate-old.sh（旧主机执行）

**选项：**

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--target` | 目标系统类型（`linux` / `darwin`） | `linux` |
| `--scp` | 是否通过 scp 传输（`yes` / `no`） | `yes` |

**示例：**

```bash
# 迁移到 Linux 主机并自动传输
bash migrate-old.sh --target linux --scp yes

# 迁移到 macOS 主机，跳过自动传输
bash migrate-old.sh --target darwin --scp no
```

**导出内容：**

| 文件 | 说明 |
|------|------|
| `versions-manifest.json` | 统一版本清单（核心） |
| `npm-packages.json` | npm 全局包版本 |
| `clawhub-skills.json` | clawhub skills 清单 |
| `plugin-installs.json` | 插件安装元数据 |
| `openclaw-config.tar.gz` | .openclaw 目录打包 |
| `migrate-new.sh` | 还原脚本 |
| `target-os.txt` | 目标平台标识 |

### 2️⃣ migrate-new.sh（新主机执行）

**无需参数**，脚本自动完成：
- 读取版本清单（`versions-manifest.json`）
- 检测操作系统（Linux / macOS 自适应）
- 检查/安装 Node.js（通过 nvm）
- 按清单安装 OpenClaw + 插件（版本不一致才覆盖）
- 按清单安装 clawhub skills
- 解压配置文件（OS 自适应）
- 修正权限归属
- 安装并启动 Gateway
- 输出**版本一致性校验报告**

**示例：**

```bash
cd $HOME/openclaw-migration
bash migrate-new.sh
```

---

## 版本清单（versions-manifest.json）

```json
{
  "created_at": "2026-03-27T10:00:00+08:00",
  "target_os": "linux",
  "openclaw_version": "2026.3.13",
  "node_version": "24.14.0",
  "npm_packages": {
    "openclaw": "2026.3.13",
    "@larksuite/openclaw-lark": "2026.3.17",
    "@tencent-weixin/openclaw-weixin": "1.0.2",
    "clawhub": "0.9.0"
  },
  "clawhub_skills": [
    { "name": "baoyu-image-gen", "version": "1.0.0" }
  ],
  "plugin_installs": {
    "openclaw-lark": { "version": "2026.3.17" },
    "openclaw-weixin": { "version": "1.0.2" }
  }
}
```

---

## 使用示例

### 场景：Linux → Linux 迁移

**旧主机：**
```bash
bash migrate-old.sh --target linux --scp yes
# 输入新主机地址（如 192.168.1.100）和密码
```

**新主机（等待传输完成）：**
```bash
bash migrate-new.sh
```

### 场景：macOS → Linux 迁移

**macOS 旧主机：**
```bash
bash migrate-old.sh --target linux --scp yes
```

**Linux 新主机：**
```bash
bash migrate-new.sh
```

---

## 注意事项

### ⚠️ 传输前检查
```bash
# 确认新主机可达
ping -c 1 <新主机IP>
```

### ⚠️ macOS 目标机要求
- 建议 **macOS 12+**
- 需要 **sudo 权限**
- 提前开启「系统设置 → 通用 → 登录项 → 远程登录」

### ⚠️ clawhub skills 安装
- 需要新服务器已安装 `clawhub` CLI
- 如果 clawhub 未安装，skills 清单会记录但跳过安装

### ⚠️ 常见问题

| 问题 | 解决方案 |
|------|----------|
| scp 传输失败 | 检查 SSH 端口、防火墙、远程登录是否开启 |
| 权限报错 | `sudo chown -R $(whoami) ~/.openclaw/` |
| Gateway probe 失败 | 检查端口 18789：`ss -tlnp | grep 18789` |
| npm 安装慢 | `npm config set registry https://registry.npmmirror.com` |
| clawhub 安装 skills 失败 | 确认 clawhub CLI 已安装：`clawhub --version` |

---

## 技术实现

- **Shell** — 流程控制、参数解析、文件操作
- **Node.js** — JSON 解析、版本比对、清单生成（无需 Python）
- **tar** — 配置文件打包/解压
- **npm** — OpenClaw 及插件安装
- **clawhub** — skills 同步（可选）

---

## 文件结构

```
move_ur_openclaw/
├── migrate-old.sh     # 旧主机打包脚本
├── migrate-new.sh     # 新主机还原脚本
└── README.md          # 本文档
```

---

## 迁移包结构

```
~/openclaw-migration/
├── versions-manifest.json    # ★ 统一版本清单（核心）
├── npm-packages.json        # npm 全局包版本
├── clawhub-skills.json      # clawhub skills 清单
├── plugin-installs.json     # 插件安装元数据
├── openclaw-config.tar.gz   # .openclaw 配置包
├── migrate-new.sh          # 还原脚本
└── target-os.txt           # 目标平台标识
```
