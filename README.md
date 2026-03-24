# OpenClaw 跨服务器迁移手册

> **适用场景：** 将 OpenClaw 从一台服务器迁移到另一台新服务器
> **支持平台：** Linux → Linux / Mac → Linux / Mac → Mac / Linux → Mac
> **前提：** 旧服务器已正常运行 OpenClaw，新服务器已准备就绪（建议 OpenCloudOS 9 / Ubuntu 22.04+ / macOS 12+）
> **迁移方式：** 旧服务器打包 → 传输 → 新服务器还原

---

## 支持的迁移路径

| 方向 | 支持状态 | 说明 |
|------|----------|------|
| Linux → Linux | ✅ 完全支持 | 当前方案，原生适配 |
| Mac → Linux | ✅ 完全支持 | 脚本自动识别 macOS 并调整解压方式 |
| Mac → Mac | ✅ 完全支持 | 直接复制配置文件即可 |
| Linux → Mac | ✅ 完全支持 | 脚本自动识别并调整解压方式 |

---

## 流程总览

### 第一阶段：旧服务器打包

| # | 操作 | 说明 |
|---|------|------|
| 1 | 创建迁移目录 | `~/openclaw-migration/` |
| 2 | 打包 `.openclaw/` | 配置文件、插件数据、workspace、memory |
| 3 | 导出 npm 版本 | 记录 OpenClaw + 插件版本 |
| 4 | 复制还原脚本 | 将 `migrate-new.sh` 纳入迁移包 |
| 5 | 验证打包结果 | 检查文件完整性 |
| 6 | 传输到新服务器 | `scp` 推送 |
| 7 | 关闭 OpenClaw Gateway | `openclaw gateway stop` |

### 第二阶段：新服务器还原

| # | 操作 | 说明 |
|---|------|------|
| 1 | 检查/安装 Node.js | 通过 nvm 安装（默认 v24） |
| 2 | 安装 OpenClaw + 插件 | **带版本判断**，版本一致则跳过 |
| 3 | 检查迁移包 | 确认打包文件到位 |
| 4 | 解压配置 | **自动识别 OS**，适配 Linux / macOS 不同解压方式 |
| 5 | 修正权限 | `chown` 将配置归属当前用户 |
| 6 | 安装 OpenClaw Gateway | `openclaw gateway install` |
| 7 | 启动 Gateway | `openclaw gateway start` |
| 8 | 完整性验证 | 版本/Gateway状态/RPC/插件/配置/memory |

---

## 详细步骤

### 第一阶段：旧服务器

**1. 执行打包脚本**

```bash
# 参数为新服务器 IP 或域名
bash migrate-old.sh <新服务器IP或域名>
```

脚本执行过程中会要求输入新服务器密码（scp 传输时需要）。

**2. 确认打包内容**

- 打包 `~/.openclaw/` 为 `openclaw-config.tar.gz`
- 导出 npm 全局包版本到 `npm-packages.json`
- 复制还原脚本到迁移目录
- 通过 scp 传输到新服务器的 `~/openclaw-migration/`

**3. 关闭旧服务**

打包传输全部完成后，脚本**最后一步**自动执行 `openclaw gateway stop`。

---

### 第二阶段：新服务器

**1. 执行还原脚本**

```bash
cd $HOME/openclaw-migration
bash migrate-new.sh
```

脚本会自动检测目标系统类型（Linux 或 macOS），并应用对应的解压和权限处理方式。

**2. 脚本自动完成**

- 检测操作系统类型（Linux / macOS）
- 检查/安装 Node.js（通过 nvm）
- 安装 OpenClaw + 插件（带版本判断）
- 解压配置（OS 自适应）：
  - **Linux**：直接 `tar -C /` 解压到根目录
  - **macOS**：解压到 `$HOME`，自动处理 SIP 隔离目录
- 修正权限归属
- 安装并启动 OpenClaw Gateway
- 完整性验证并输出结果

**3. 验证结果**

脚本末尾会输出验证报告，重点检查：

| 检查项 | 预期 |
|--------|------|
| `openclaw --version` | 显示版本号 |
| `openclaw gateway status` | running |
| `openclaw gateway probe` | ok |
| 配置文件 | `~/.openclaw/` 有内容 |
| memory | `~/.openclaw/memory/` 有数据库 |
| 定时任务 | `~/.openclaw/cron/jobs.json` 正常 |

---

## ⚠️ 注意事项

### 传输前检查

```bash
# 确认新服务器 IP 可达
ping -c 1 <新服务器IP>
```

### macOS 目标机额外要求

- 建议使用 **macOS 12+**
- 需要 **sudo 权限**
- 如通过 SSH 远程操作，需先在「系统设置 → 通用 → 登录项 → 远程登录」开启 SSH 服务
- macOS SIP（系统完整性保护）会隔离解压路径，脚本会自动处理

### 插件版本

在 `migrate-new.sh` 第 52-54 行修改：

```bash
npm_ensure "openclaw" "版本号"
npm_ensure "@组织/插件名" "版本号"
```

留空则安装最新版。

---

## 🔧 常见问题

| 问题 | 解决方案 |
|------|----------|
| scp 传输失败 | 检查新服务器 IP、SSH 端口（macOS 需开启远程登录）、防火墙 |
| 解压后权限报错 | Linux：`sudo chown -R $(whoami) ~/.openclaw/`；macOS：脚本自动处理 |
| Gateway probe 失败 | 检查端口 18789：`ss -tlnp \| grep 18789`（Linux）或 `lsof -i :18789`（macOS） |
| npm 安装很慢 | `npm config set registry https://registry.npmmirror.com` |

---

## 📁 文件说明

```
move_ur_openclaw/
├── migrate-old.sh     # 旧服务器打包脚本
├── migrate-new.sh     # 新服务器还原脚本（Linux / macOS 自适应）
└── README.md          # 本手册
```
