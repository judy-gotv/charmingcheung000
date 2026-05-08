# MPD-HLS 一键安装脚本

<p align="center">
  <img src="https://img.shields.io/badge/Docker-Required-2496ED?style=flat-square&logo=docker&logoColor=white"/>
  <img src="https://img.shields.io/badge/Platform-Linux-FCC624?style=flat-square&logo=linux&logoColor=black"/>
  <img src="https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white"/>
  <img src="https://img.shields.io/badge/Author-Go--iptv-blueviolet?style=flat-square"/>
</p>

> 一键部署 MPD-HLS 串流服务，支持自动安装 Docker、自定义端口、多版本切换、升级与卸载。

---

## 目录

- [功能特性](#功能特性)
- [系统要求](#系统要求)
- [快速开始](#快速开始)
- [菜单说明](#菜单说明)
  - [安装 / 重装](#1-安装--重装)
  - [一键升级](#2-一键升级)
  - [卸载](#3-卸载)
- [目录结构](#目录结构)
- [常用命令](#常用命令)
- [版本说明](#版本说明)
- [常见问题](#常见问题)

---

## 功能特性

| 功能 | 说明 |
|------|------|
| 🐳 自动安装 Docker | 检测到未安装时自动下载官方脚本安装，已安装则直接跳过 |
| 🔧 自动安装 Compose | 优先使用 Docker Compose Plugin（v2），兼容旧版 docker-compose |
| 🎯 自定义端口 | 安装时交互输入端口号，自动检测占用冲突，默认 `9527` |
| 📦 多版本选择 | 支持 `latest` 稳定版 与 `alpha` 尝鲜版 |
| ⬆️ 一键升级 | 自动读取现有端口配置，拉取最新镜像后原地重启，数据完整保留 |
| 🗑️ 一键卸载 | 移除容器、镜像（latest + alpha）及全部数据目录 |
| 🔥 防火墙自动放行 | 自动兼容 `ufw` 和 `firewalld` |
| 🌐 双栈监听 | 同时监听 IPv4（`0.0.0.0`）与 IPv6（`::`） |

---

## 系统要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Debian / Ubuntu / CentOS / RHEL 及其衍生版 |
| 权限 | `root` 或 `sudo` |
| 网络 | 可访问 Docker Hub 与 GitHub |
| 依赖 | `curl` 或 `wget`（二选一即可） |

---

## 快速开始

```bash
# 下载脚本
wget -O install.sh https://raw.githubusercontent.com/judy-gotv/charmingcheung000/main/install.sh

# 赋予执行权限
chmod +x install.sh

# 以 root 权限运行
sudo bash install.sh
```

运行后进入交互式主菜单，按提示操作即可。

---

## 菜单说明

脚本启动后显示主菜单：

```
  [ 1 ]  安装 / 重装  — 全新安装或覆盖现有服务
  [ 2 ]  一键升级     — 拉取最新镜像，保留端口与数据
  [ 3 ]  卸    载     — 移除容器、镜像及全部数据
```

---

### 1. 安装 / 重装

按步骤完成以下交互：

**① 选择版本**
```
  [ 1 ]  Stable  稳定版  — 经过充分测试，推荐生产使用
  [ 2 ]  Alpha   尝鲜版  — 功能最新，可能存在不稳定情况
```

**② 设置端口**
```
  请输入要使用的端口号 [9527]:
```
- 直接回车使用默认端口 `9527`
- 输入自定义端口后脚本会自动检测是否被占用

**③ 自动执行**

脚本将依次完成：检测/安装 Docker → 检测/安装 Compose → 下载配置 → 拉取镜像 → 启动容器 → 放行防火墙

**④ 安装完成后显示**

```
  服务信息
  ─────────────────────────────────────────────────
    镜    像   charmingcheung000/mpd-hls:latest（稳定版）
    容器 ID    a1b2c3d4e5f6
    创建时间   2026-05-09T12:00:00

  访问地址
  ─────────────────────────────────────────────────
    内    网   http://192.168.1.100:9527
    公    网   http://1.2.3.4:9527

  常用命令
  ─────────────────────────────────────────────────
    查看日志   docker logs -f mpd-hls
    停止服务   cd /opt/mpd-hls && docker compose down
    重启服务   cd /opt/mpd-hls && docker compose restart
    更新镜像   cd /opt/mpd-hls && docker compose pull && docker compose up -d
```

---

### 2. 一键升级

升级前脚本自动读取现有 `docker-compose.yml` 中的配置：

- **端口** — 完全保留用户设置的端口，不会被重置
- **版本 Tag** — 保留原来安装的版本（latest / alpha），拉取该 tag 的最新镜像
- **数据目录** — `/opt/mpd-hls/var` 中的数据完整保留，不做任何清理

升级步骤：

```
  步骤 1/3  检测 Docker 环境       已安装则跳过，未安装则自动安装
  步骤 2/3  拉取最新镜像           docker compose pull
  步骤 3/3  重启服务               docker compose up -d --remove-orphans
```

> 若检测到未安装过 mpd-hls 服务，脚本会提示是否转入全新安装流程。

---

### 3. 卸载

卸载前会明确列出将被删除的内容，并要求输入 `YES` 二次确认：

```
  容    器   mpd-hls
  镜    像   charmingcheung000/mpd-hls:latest
             charmingcheung000/mpd-hls:alpha
  数据目录   /opt/mpd-hls  （含所有 CDM 密钥、数据库）

  确认卸载？此操作不可恢复，请输入 YES 确认：
```

输入 `YES` 后依次执行：

```
  步骤 1/3  停止并删除容器    compose down → docker rm -f（兜底）
  步骤 2/3  删除 Docker 镜像  同时删除 latest 和 alpha，清理悬空层
  步骤 3/3  删除安装目录      rm -rf /opt/mpd-hls
```

输入任何非 `YES` 内容则取消退出，不做任何修改。

---

## 目录结构

```
/opt/mpd-hls/
├── docker-compose.yml    # 服务配置文件（自动生成）
└── var/                  # 持久化数据目录（映射至容器 /app/var）
    ├── *.db              # 数据库文件
    └── ...               # CDM 密钥等配置
```

---

## 常用命令

```bash
# 查看实时日志
docker logs -f mpd-hls

# 停止服务
cd /opt/mpd-hls && docker compose down

# 重启服务
cd /opt/mpd-hls && docker compose restart

# 手动更新镜像
cd /opt/mpd-hls && docker compose pull && docker compose up -d

# 查看容器状态
docker ps -a | grep mpd-hls

# 进入容器
docker exec -it mpd-hls bash
```

---

## 版本说明

| Tag | 说明 | 适用场景 |
|-----|------|----------|
| `latest` | 稳定版，经过测试验证 | 生产环境、日常使用 |
| `alpha` | 尝鲜版，包含最新功能 | 测试、体验新特性 |

---

## 常见问题

**Q：安装时提示端口被占用怎么办？**

输入其他未被占用的端口即可，脚本会自动检测并提示重新输入。

**Q：升级后端口变了怎么办？**

不会发生这种情况。升级流程会从 `/opt/mpd-hls/docker-compose.yml` 中自动读取当前端口，原样保留。

**Q：卸载后数据能恢复吗？**

不能。卸载会执行 `rm -rf /opt/mpd-hls`，请在卸载前自行备份 `/opt/mpd-hls/var` 目录中的重要数据。

**Q：支持 ARM 架构（如树莓派）吗？**

Docker 镜像和 Compose 插件均支持 `aarch64` 架构，脚本会自动识别并下载对应版本。

**Q：防火墙没有自动放行怎么办？**

手动执行以下命令（将 `9527` 替换为实际端口）：

```bash
# ufw
ufw allow 9527/tcp

# firewalld
firewall-cmd --permanent --add-port=9527/tcp && firewall-cmd --reload

# iptables
iptables -I INPUT -p tcp --dport 9527 -j ACCEPT
```

---

<p align="center">Powered by <b>Go-iptv</b></p>
