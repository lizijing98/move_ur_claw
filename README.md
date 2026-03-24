# OpenClaw 跨服务器迁移手册

> **适用场景：** 将 OpenClaw 从一台服务器迁移到另一台新服务器
> **前提：** 旧服务器已正常运行 OpenClaw，新服务器已准备就绪（建议 OpenCloudOS 9 / Ubuntu 22.04+）
> **迁移方式：** 旧服务器打包 → 传输 → 新服务器还原

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
| 4 | 解压配置 | `sudo tar -xzvf -C /` 覆盖还原 |
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

脚本会自动完成：
- 打包 `~/.openclaw/` 为 `openclaw-config.tar.gz`
- 导出 npm 全局包版本到 `npm-packages.json`
- 复制还原脚本到迁移目录
- 通过 scp 传输到新服务器的 `~/openclaw-migration/`

**3. 关闭旧服务**

打包传输全部完成后，脚本最后一步自动执行 `openclaw gateway stop`。

---

### 第二阶段：新服务器

**1. 执行还原脚本**

```bash
cd $HOME/openclaw-migration
bash migrate-new.sh
```

**2. 脚本自动完成**

- 检查/安装 Node.js（通过 nvm）
- 安装 OpenClaw + 插件（带版本判断）
- 解压配置到系统根目录 `/`
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

# 确认 SSH 端口是 22（默认）
# 如有不同，修改 migrate-old.sh 中的 scp 命令：
#   scp -P <端口号> -r ${MIGRATION_DIR} ...
```

### 新服务器环境

- 建议使用 **OpenCloudOS 9** 或 **Ubuntu 22.04+**
- 需要有 **sudo 权限**（用于解压和 chown）
- 需要能够访问 **GitHub**（部分插件从 GitHub 安装）

### 插件版本

在 `migrate-new.sh` 中修改 `npm_ensure` 调用（第 52-54 行）：

```bash
npm_ensure "openclaw" "版本号"
npm_ensure "@组织/插件名" "版本号"
```

版本号留空则跳过版本检查，直接安装最新版。

---

## 🔧 常见问题

| 问题 | 解决方案 |
|------|----------|
| scp 传输失败 connection refused | 检查新服务器 IP、SSH 端口、防火墙 |
| git clone 失败 Permission denied | 确认 GitHub SSH 公钥已添加到账户 |
| 解压后权限报错 | 手动运行 `sudo chown -R $(whoami) ~/.openclaw/` |
| Gateway 启动后 probe 失败 | 检查端口 18789：`ss -tlnp \| grep 18789` |
| npm 安装很慢 | `npm config set registry https://registry.npmmirror.com` |

---

## 📁 文件说明

```
move_ur_openclaw/
├── migrate-old.sh     # 旧服务器打包脚本
├── migrate-new.sh     # 新服务器还原脚本
└── README.md          # 本手册
```
