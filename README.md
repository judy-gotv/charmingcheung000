# MPD-HLS 一键安装脚本

<p align="center">
  <img src="https://img.shields.io/badge/Docker-Required-2496ED?style=flat-square&logo=docker&logoColor=white"/>
  <img src="https://img.shields.io/badge/Platform-Linux-FCC624?style=flat-square&logo=linux&logoColor=black"/>
  <img src="https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white"/>
  <img src="https://img.shields.io/badge/Author-Go--iptv-blueviolet?style=flat-square"/>
</p>

> 一键部署 MPD-HLS 串流服务，支持 HTTP/HLS 与 RTMP 推流、自定义访问域名、多版本切换、升级与卸载。

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
| 📡 RTMP 推流 | 自动映射并放行固定端口 `1935`，同时检测端口冲突 |
| 🔗 公共访问地址 | 根据 Nginx 域名设置 `MPD_HLS_PUBLIC_BASE_URL`，生成正确的 m3u8、m3u8x、EPG 等资源链接 |
| 🗄️ 数据库迁移 | 1.0.0 自动将旧 JSON 迁移到本地 SQLite，也支持 PostgreSQL |
| 📦 多版本选择 | 支持 `latest` 稳定版 与 `alpha` 尝鲜版 |
| ⬆️ 一键升级 | 保留版本、HTTP 端口和域名，补齐新版部署参数后拉取镜像并重启 |
| 🗑️ 一键卸载 | 移除容器、镜像（latest + alpha）及全部数据目录 |
| 🔥 防火墙自动放行 | 自动兼容 `ufw` 和 `firewalld`；Nginx 未安装时不会放行其 HTTP 端口 |
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

**方式一：（推荐）curl 一行命令**

```bash
curl -fsSL https://raw.githubusercontent.com/judy-gotv/charmingcheung000/main/install.sh | sudo bash
```

**方式二：下载后运行**

```bash
wget -O install.sh https://raw.githubusercontent.com/judy-gotv/charmingcheung000/main/install.sh && chmod +x install.sh && sudo bash install.sh
```

运行后进入交互式主菜单，按提示操作即可。

---

## 菜单说明

脚本启动后显示主菜单：

```
  [ 1 ]  安装 / 重装  — 全新安装或覆盖现有服务
  [ 2 ]  一键升级     — 更新镜像与部署配置，保留端口、域名和数据
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
- `1935` 保留给 RTMP 推流，不能作为 HTTP 服务端口

**③ 选择 Nginx 并确定公共地址**

如果系统尚未安装 Nginx，脚本会先询问是否安装。选择安装后才会要求输入反向代理域名，例如 `stream.example.com`，并生成：

```yaml
MPD_HLS_PUBLIC_BASE_URL=http://stream.example.com
```

选择跳过时则不要求输入域名，公共基础地址自动使用 `http://公网IP:服务端口`。

**④ 自动执行**

脚本将依次完成：检测/安装 Docker → 检测/安装 Compose → 检查 HTTP 与 RTMP 端口 → 询问是否安装并配置 Nginx → 确定公共基础地址 → 整理数据目录 → 生成 Compose 配置 → 拉取镜像 → 放行防火墙

如果系统尚未安装 Nginx，脚本会显示以下确认，直接回车默认跳过：

```text
是否立即安装 Nginx？[y/N] / Install Nginx now? [y/N]:
```

选择 `N` 不会中断 MPD-HLS 服务，脚本会跳过 Nginx 安装、反向代理配置和 `80` 端口放行，并将 `MPD_HLS_PUBLIC_BASE_URL` 设置为 IP 加服务端口。

随后脚本会询问数据库连接地址。直接回车使用本地 SQLite；如需 PostgreSQL，请输入 `postgres://...` 或 `postgresql://...` 连接地址。

**⑤ 安装完成后显示**

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
    RTMP      rtmp://1.2.3.4:1935
    Nginx     http://stream.example.com
    公共基础地址 http://stream.example.com

  常用命令
  ─────────────────────────────────────────────────
    查看日志   docker logs -f mpd-hls
    停止服务   cd /opt/mpd-hls && docker compose down
    重启服务   cd /opt/mpd-hls && docker compose restart
    更新镜像   cd /opt/mpd-hls && docker compose pull && docker compose up -d
```

如果跳过 Nginx，最终摘要不会显示 Nginx 地址，公共基础地址会显示为：

```text
公共基础地址 / Public base URL: http://1.2.3.4:9527
```

---

### 2. 一键升级

升级前脚本自动读取现有 `docker-compose.yml` 中的配置：

- **端口** — 完全保留用户设置的端口，不会被重置
- **版本 Tag** — 保留原来安装的版本（latest / alpha），拉取该 tag 的最新镜像
- **公共基础地址** — 启用 Nginx 时复用或询问域名；跳过 Nginx 时自动使用公网 IP 和服务端口
- **数据库** — 直接回车使用本地 SQLite；输入 PostgreSQL URL 可切换到 PostgreSQL
- **数据目录** — `/opt/mpd-hls/var` 中的数据完整保留，不做任何清理

升级会先将旧版 JSON 和 `auth_secret` 备份到 `/opt/mpd-hls/backup-时间戳/`，再重新生成 `docker-compose.yml`，自动加入 RTMP `1935` 映射和 `MPD_HLS_PUBLIC_BASE_URL`。旧 Compose 文件会保存为带时间戳的 `.bak` 备份。1.0.0 迁移完成后不再读取旧 JSON 和 `auth_secret`。

升级步骤：

```
  步骤 1/5  检测 Docker 环境       已安装则跳过，未安装则自动安装
  步骤 2/7  检查 RTMP 端口         拒绝其他服务占用 1935
  步骤 3/7  备份旧版数据           保存 JSON 和 auth_secret
  步骤 4/7  配置数据库             默认使用 SQLite，可选 PostgreSQL
  步骤 5/7  整理并保留数据目录     迁移旧字体与录制目录
  步骤 6/7  更新配置并拉取镜像     写入新版 Compose 后执行 pull
  步骤 7/7  重启服务               docker compose up -d --remove-orphans
```

> 若检测到未安装过 mpd-hls 服务，脚本会提示是否转入全新安装流程。

> 升级时若需要配置反向代理但系统没有 Nginx，也会先询问是否安装，默认不会执行安装。

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
    ├── hls/              # 临时推流输出文件
    ├── fonts/            # 字体文件（从旧 var/hls/fonts 自动迁移）
    ├── recordings/       # 录制文件（从旧 var/hls/recordings 自动迁移）
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

直接使用仓库中的 `latest.yml` 或 `alpha.yml` 时，可通过环境变量指定公共地址：

```bash
MPD_HLS_PUBLIC_BASE_URL=https://stream.example.com docker compose -f latest.yml up -d
```

未设置时，Compose 文件默认使用 `http://localhost`。

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

**Q：RTMP 端口可以修改吗？**

一键安装脚本固定使用 `1935`。安装和升级都会检查端口；如果被其他服务占用，脚本会停止并显示错误。

**Q：生成的 m3u8 或 EPG 链接域名不正确怎么办？**

检查 `/opt/mpd-hls/docker-compose.yml` 中的 `MPD_HLS_PUBLIC_BASE_URL`。一键安装会根据 Nginx 域名自动设置；直接使用 Compose 文件时请通过同名环境变量覆盖默认值。

**Q：如何从 0.x 升级到 1.0.0？**

先备份 `/opt/mpd-hls/var`，确认 Docker 可用，然后运行脚本选择“升级”。脚本会额外备份旧 JSON 和 `auth_secret`，并由 1.0.0 自动迁移到 SQLite。迁移后旧 JSON 不再读取。

如需 PostgreSQL，在数据库提示处输入连接地址，例如：

```bash
postgres://user:password@host:5432/database
```

**Q：卸载后数据能恢复吗？**

不能。卸载会执行 `rm -rf /opt/mpd-hls`，请在卸载前自行备份 `/opt/mpd-hls/var` 目录中的重要数据。

**Q：支持 ARM 架构（如树莓派）吗？**

Docker 镜像和 Compose 插件均支持 `aarch64` 架构，脚本会自动识别并下载对应版本。

**Q：防火墙没有自动放行怎么办？**

手动执行以下命令（将 `9527` 替换为实际 HTTP 端口）：

```bash
# ufw
ufw allow 9527/tcp
ufw allow 1935/tcp
ufw allow 80/tcp

# firewalld
firewall-cmd --permanent --add-port=9527/tcp
firewall-cmd --permanent --add-port=1935/tcp
firewall-cmd --permanent --add-service=http
firewall-cmd --reload

# iptables
iptables -I INPUT -p tcp --dport 9527 -j ACCEPT
iptables -I INPUT -p tcp --dport 1935 -j ACCEPT
iptables -I INPUT -p tcp --dport 80 -j ACCEPT
```

---

<p align="center">Powered by <b>Go-iptv</b></p>
