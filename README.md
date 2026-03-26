# OpenClaw 搬家指南 🦞🏠

> 将你的 OpenClaw 从一台主机迁移到另一台，支持 Linux/Mac 之间相互迁移。

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
| 2 | 验证迁移结果 | 检查 Gateway 状态、插件、记忆文件 |

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

### 2️⃣ migrate-new.sh（新主机执行）

**无需参数**，脚本自动完成：
- 检测操作系统（Linux / macOS 自适应）
- 检查/安装 Node.js（通过 nvm）
- 安装 OpenClaw + 插件（带版本判断）
- 解压配置文件（OS 自适应）
- 修正权限归属
- 安装并启动 Gateway
- 输出完整性验证报告

**示例：**

```bash
cd $HOME/openclaw-migration
bash migrate-new.sh
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

### ⚠️ 插件版本
如需固定版本，在 `migrate-new.sh` 第 52-54 行修改：
```bash
npm_ensure "openclaw" "版本号"
npm_ensure "@组织/插件名" "版本号"
```
留空则安装最新版。

### ⚠️ 常见问题

| 问题 | 解决方案 |
|------|----------|
| scp 传输失败 | 检查 SSH 端口、防火墙、远程登录是否开启 |
| 权限报错 | `sudo chown -R $(whoami) ~/.openclaw/` |
| Gateway probe 失败 | 检查端口 18789：`ss -tlnp \| grep 18789` |
| npm 安装慢 | `npm config set registry https://registry.npmmirror.com` |

---

## 文件结构

```
move_ur_openclaw/
├── migrate-old.sh     # 旧主机打包脚本
├── migrate-new.sh     # 新主机还原脚本
└── README.md          # 本文档
```

---

## 迁移包内容

```
~/openclaw-migration/
├── openclaw-config.tar.gz   # 配置文件包
├── npm-packages.json        # npm 插件版本记录
├── migrate-new.sh           # 还原脚本
└── target-os.txt           # 目标系统标识
```
