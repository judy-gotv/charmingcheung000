#!/bin/bash

# ============================================================
#  mpd-hls 一键安装脚本  |  作者：Go-iptv
# ============================================================

set -e

# 修复 curl|bash 管道模式下 read 无法从终端读取的问题
[ -t 0 ] || exec < /dev/tty

# ── 颜色 & 样式 ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── 常量 ─────────────────────────────────────────────────────
INSTALL_DIR="/opt/mpd-hls"
VAR_DIR="${INSTALL_DIR}/var"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
DEFAULT_PORT=9527
CONTAINER_PORT=9100
AUTHOR="Go-iptv"

LATEST_YML_URL="https://raw.githubusercontent.com/judy-gotv/charmingcheung000/main/latest.yml"
ALPHA_YML_URL="https://raw.githubusercontent.com/judy-gotv/charmingcheung000/main/alpha.yml"

VERSION_TAG=""
VERSION_LABEL=""
VERSION_YML_URL=""

# ── 工具函数 ─────────────────────────────────────────────────
line_cyan()    { echo -e "${CYAN}  ─────────────────────────────────────────────────${NC}"; }
line_green()   { echo -e "${GREEN}  ─────────────────────────────────────────────────${NC}"; }
line_thin()    { echo -e "${DIM}  ·················································${NC}"; }

print_step() {
    local idx="$1"; local title="$2"
    echo ""
    echo -e "${BOLD}${CYAN}  ┌─[ ${WHITE}步骤 ${idx}${CYAN} ]────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}${CYAN}  │  ${WHITE}${title}${NC}"
    echo -e "${BOLD}${CYAN}  └─────────────────────────────────────────────────────${NC}"
}

print_ok()   { echo -e "  ${GREEN}  ✔  ${NC}${WHITE}$1${NC}"; }
print_warn() { echo -e "  ${YELLOW}  ⚠  ${NC}${YELLOW}$1${NC}"; }
print_err()  { echo -e "  ${RED}  ✘  ${NC}${RED}$1${NC}"; }
print_info() { echo -e "  ${CYAN}  ›  ${NC}${DIM}$1${NC}"; }

# ── Banner ───────────────────────────────────────────────────
print_banner() {
    clear
    echo ""
    echo -e "${CYAN}${BOLD}"
    echo "   ███╗   ███╗██████╗ ██████╗       ██╗  ██╗██╗     ███████╗"
    echo "   ████╗ ████║██╔══██╗██╔══██╗      ██║  ██║██║     ██╔════╝"
    echo "   ██╔████╔██║██████╔╝██║  ██║█████╗███████║██║     ███████╗"
    echo "   ██║╚██╔╝██║██╔═══╝ ██║  ██║╚════╝██╔══██║██║     ╚════██║"
    echo "   ██║ ╚═╝ ██║██║     ██████╔╝      ██║  ██║███████╗███████║"
    echo "   ╚═╝     ╚═╝╚═╝     ╚═════╝       ╚═╝  ╚═╝╚══════╝╚══════╝"
    echo -e "${NC}"
    echo -e "${WHITE}${BOLD}  ╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}${BOLD}  ║${NC}        ${CYAN}${BOLD}MPD-HLS 串流服务  •  一键安装脚本${NC}        ${WHITE}${BOLD}      ║${NC}"
    echo -e "${WHITE}${BOLD}  ║${NC}  ${DIM}Docker 自动检测  •  自定义端口  •  多版本选择${NC}  ${WHITE}${BOLD}      ║${NC}"
    echo -e "${WHITE}${BOLD}  ╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${WHITE}${BOLD}  ║${NC}  ${DIM}作者：${NC}${MAGENTA}${BOLD}${AUTHOR}${NC}$(printf '%*s' 40 '')${WHITE}${BOLD}  ║${NC}"
    echo -e "${WHITE}${BOLD}  ╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ── 检查 root ─────────────────────────────────────────────────
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo ""
        print_err "需要 root 权限，请使用：${BOLD}sudo bash install.sh${NC}"
        echo ""
        exit 1
    fi
}

# ── 选择版本 ─────────────────────────────────────────────────
choose_version() {
    print_step "1/6" "选择安装版本"
    echo ""
    echo -e "  ${WHITE}${BOLD}  请选择要安装的版本${NC}"
    echo ""
    echo -e "  ${GREEN}${BOLD}  [ 1 ]${NC}  ${BOLD}Stable  稳定版${NC}  ${DIM}— 经过充分测试，推荐生产使用${NC}"
    echo -e "  ${YELLOW}${BOLD}  [ 2 ]${NC}  ${BOLD}Alpha   尝鲜版${NC}  ${DIM}— 功能最新，可能存在不稳定情况${NC}"
    echo ""
    line_thin

    while true; do
        echo -ne "  ${CYAN}›${NC} 请输入选项 ${DIM}[1/2]${NC}（默认 ${GREEN}1${NC}）：${BOLD} "
        read -r VERSION_CHOICE
        echo -ne "${NC}"
        VERSION_CHOICE=${VERSION_CHOICE:-1}
        case "$VERSION_CHOICE" in
            1)
                VERSION_TAG="latest"
                VERSION_LABEL="稳定版 (latest)"
                VERSION_YML_URL="${LATEST_YML_URL}"
                echo ""
                print_ok "已选择：${GREEN}${BOLD}${VERSION_LABEL}${NC}"
                break
                ;;
            2)
                VERSION_TAG="alpha"
                VERSION_LABEL="尝鲜版 (alpha)"
                VERSION_YML_URL="${ALPHA_YML_URL}"
                echo ""
                print_warn "已选择：${YELLOW}${BOLD}${VERSION_LABEL}${NC}  此版本可能存在不稳定情况"
                break
                ;;
            *)
                print_warn "无效输入，请输入 1 或 2"
                ;;
        esac
    done
}

# ── 检测 / 安装 Docker ────────────────────────────────────────
check_docker() {
    print_step "2/6" "检测 Docker 环境"
    echo ""

    if command -v docker &>/dev/null; then
        DOCKER_VER=$(docker --version | awk '{print $3}' | tr -d ',')
        print_ok "Docker 已安装   版本：${CYAN}${DOCKER_VER}${NC}"
    else
        print_warn "未检测到 Docker，即将自动安装..."
        echo ""
        install_docker
    fi

    if ! docker info &>/dev/null; then
        print_warn "Docker 服务未运行，正在启动..."
        systemctl start docker && systemctl enable docker
        print_ok "Docker 服务已启动并设为开机自启"
    else
        print_ok "Docker 服务运行正常"
    fi
}

install_docker() {
    print_info "正在使用官方脚本安装 Docker..."
    if command -v curl &>/dev/null; then
        curl -fsSL https://get.docker.com | bash
    elif command -v wget &>/dev/null; then
        wget -qO- https://get.docker.com | bash
    else
        if [ -f /etc/debian_version ]; then
            apt-get update -qq && apt-get install -y docker.io
        elif [ -f /etc/redhat-release ]; then
            yum install -y docker
        else
            print_err "无法自动安装 Docker，请手动安装后重新运行此脚本"
            exit 1
        fi
    fi
    systemctl start docker && systemctl enable docker
    DOCKER_VER=$(docker --version | awk '{print $3}' | tr -d ',')
    print_ok "Docker 安装完成   版本：${CYAN}${DOCKER_VER}${NC}"
}

# ── 检测 / 安装 Docker Compose ───────────────────────────────
check_compose() {
    print_step "3/6" "检测 Docker Compose"
    echo ""

    if docker compose version &>/dev/null 2>&1; then
        COMPOSE_VER=$(docker compose version --short 2>/dev/null || echo "v2.x")
        print_ok "Docker Compose (plugin) 已就绪   版本：${CYAN}${COMPOSE_VER}${NC}"
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &>/dev/null; then
        COMPOSE_VER=$(docker-compose --version | awk '{print $3}' | tr -d ',')
        print_ok "docker-compose 已安装   版本：${CYAN}${COMPOSE_VER}${NC}"
        COMPOSE_CMD="docker-compose"
    else
        print_warn "未检测到 Docker Compose，正在安装插件..."
        install_compose_plugin
        COMPOSE_CMD="docker compose"
    fi
}

install_compose_plugin() {
    COMPOSE_LATEST=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest \
        | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    COMPOSE_LATEST=${COMPOSE_LATEST:-v2.27.0}
    ARCH=$(uname -m)
    [ "$ARCH" = "aarch64" ] && ARCH="aarch64" || ARCH="x86_64"

    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_LATEST}/docker-compose-linux-${ARCH}" \
        -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    print_ok "Docker Compose 插件安装完成   版本：${CYAN}${COMPOSE_LATEST}${NC}"
}

# ── 自定义端口 ────────────────────────────────────────────────
choose_port() {
    print_step "4/6" "配置监听端口"
    echo ""
    print_info "默认端口 ${BOLD}${DEFAULT_PORT}${NC}，直接回车使用默认值"
    echo ""
    line_thin

    while true; do
        echo -ne "  ${CYAN}›${NC} 请输入端口号 ${DIM}[1-65535]${NC}（默认 ${GREEN}${DEFAULT_PORT}${NC}）：${BOLD} "
        read -r USER_PORT
        echo -ne "${NC}"
        USER_PORT=${USER_PORT:-$DEFAULT_PORT}

        if ! [[ "$USER_PORT" =~ ^[0-9]+$ ]]; then
            print_warn "请输入有效数字"; continue
        fi
        if [ "$USER_PORT" -lt 1 ] || [ "$USER_PORT" -gt 65535 ]; then
            print_warn "端口范围应在 1~65535 之间"; continue
        fi
        if ss -tlnp 2>/dev/null | grep -q ":${USER_PORT} " || \
           netstat -tlnp 2>/dev/null | grep -q ":${USER_PORT} "; then
            print_warn "端口 ${USER_PORT} 已被占用，请换一个"; continue
        fi

        echo ""
        print_ok "监听端口：${CYAN}${BOLD}${USER_PORT}${NC}"
        break
    done
}

# ── 下载 compose 并替换端口 ───────────────────────────────────
setup_files() {
    print_step "5/6" "下载配置文件并初始化目录"
    echo ""

    mkdir -p "${VAR_DIR}"
    print_ok "数据目录：${DIM}${VAR_DIR}${NC}"

    print_info "正在下载 ${VERSION_LABEL} 配置模板..."
    local TMP_YML
    TMP_YML=$(mktemp)

    if command -v curl &>/dev/null; then
        curl -fsSL "${VERSION_YML_URL}" -o "${TMP_YML}" || {
            print_err "下载失败，请检查网络连接"
            rm -f "${TMP_YML}"; exit 1
        }
    else
        wget -qO "${TMP_YML}" "${VERSION_YML_URL}" || {
            print_err "下载失败，请检查网络连接"
            rm -f "${TMP_YML}"; exit 1
        }
    fi

    sed \
        -e "s|0\.0\.0\.0:[0-9]*:${CONTAINER_PORT}|0.0.0.0:${USER_PORT}:${CONTAINER_PORT}|g" \
        -e "s|\[::\]:[0-9]*:${CONTAINER_PORT}|[::]:${USER_PORT}:${CONTAINER_PORT}|g" \
        -e "s|/opt/mpd-hls/var|${VAR_DIR}|g" \
        "${TMP_YML}" > "${COMPOSE_FILE}"

    rm -f "${TMP_YML}"
    print_ok "配置文件已写入：${DIM}${COMPOSE_FILE}${NC}"
}

# ── 启动服务 ──────────────────────────────────────────────────
start_service() {
    print_step "6/6" "拉取镜像 & 启动服务"
    echo ""
    print_info "正在拉取镜像，首次可能需要几分钟，请耐心等待..."
    echo ""

    cd "${INSTALL_DIR}"
    $COMPOSE_CMD pull
    echo ""
    $COMPOSE_CMD up -d

    print_ok "容器已成功启动"
}

# ── 等待容器就绪 ──────────────────────────────────────────────
wait_healthy() {
    echo ""
    print_info "等待容器进入运行状态..."
    local tries=0
    while [ $tries -lt 20 ]; do
        STATUS=$(docker inspect --format='{{.State.Status}}' mpd-hls 2>/dev/null || echo "unknown")
        if [ "$STATUS" = "running" ]; then
            print_ok "容器状态：${GREEN}${BOLD}running${NC}"
            return
        fi
        sleep 2
        tries=$((tries + 1))
    done
    print_warn "容器尚未进入 running 状态，请手动检查：docker logs mpd-hls"
}

# ── 防火墙放行 ────────────────────────────────────────────────
open_firewall() {
    echo ""
    print_info "尝试自动放行防火墙端口 ${USER_PORT}..."
    if command -v ufw &>/dev/null; then
        ufw allow "${USER_PORT}/tcp" &>/dev/null && print_ok "ufw 已放行 ${USER_PORT}/tcp"
    fi
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port="${USER_PORT}/tcp" &>/dev/null
        firewall-cmd --reload &>/dev/null
        print_ok "firewalld 已放行 ${USER_PORT}/tcp"
    fi
}

# ── 获取 IP ───────────────────────────────────────────────────
get_ip() {
    LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
                curl -s --max-time 5 http://ip.sb    2>/dev/null || \
                echo "无法获取")
}

# ── 安装摘要 ──────────────────────────────────────────────────
print_summary() {
    get_ip
    CONTAINER_ID=$(docker inspect --format='{{.Id}}'      mpd-hls 2>/dev/null | cut -c1-12 || echo "unknown")
    CREATED=$(     docker inspect --format='{{.Created}}' mpd-hls 2>/dev/null | cut -c1-19 || echo "unknown")

    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║                                                          ║"
    echo "  ║        ✅   安 装 成 功 ！  服 务 已 启 动              ║"
    echo "  ║                                                          ║"
    echo "  ╠══════════════════════════════════════════════════════════╣"
    echo -e "${NC}"

    echo -e "  ${BOLD}${WHITE}  服务信息${NC}"
    line_cyan
    echo -e "  ${DIM}  镜    像${NC}  ${CYAN}charmingcheung000/mpd-hls:${VERSION_TAG}${NC}  ${DIM}（${VERSION_LABEL}）${NC}"
    echo -e "  ${DIM}  容器 ID${NC}  ${WHITE}${CONTAINER_ID}${NC}"
    echo -e "  ${DIM}  创建时间${NC}  ${WHITE}${CREATED}${NC}"
    echo ""

    echo -e "  ${BOLD}${WHITE}  访问地址${NC}"
    line_cyan
    echo -e "  ${DIM}  内    网${NC}  ${GREEN}${BOLD}http://${LOCAL_IP}:${USER_PORT}${NC}"
    echo -e "  ${DIM}  公    网${NC}  ${GREEN}${BOLD}http://${PUBLIC_IP}:${USER_PORT}${NC}"
    echo ""

    echo -e "  ${BOLD}${WHITE}  目录 & 配置${NC}"
    line_cyan
    echo -e "  ${DIM}  数据目录${NC}  ${WHITE}${VAR_DIR}${NC}"
    echo -e "  ${DIM}  配置文件${NC}  ${WHITE}${COMPOSE_FILE}${NC}"
    echo -e "  ${DIM}  时    区${NC}  ${WHITE}Asia/Shanghai${NC}"
    echo -e "  ${DIM}  重启策略${NC}  ${WHITE}unless-stopped${NC}"
    echo ""

    echo -e "  ${BOLD}${WHITE}  常用命令${NC}"
    line_cyan
    echo -e "  ${DIM}  查看日志${NC}  ${YELLOW}docker logs -f mpd-hls${NC}"
    echo -e "  ${DIM}  停止服务${NC}  ${YELLOW}cd ${INSTALL_DIR} && ${COMPOSE_CMD} down${NC}"
    echo -e "  ${DIM}  重启服务${NC}  ${YELLOW}cd ${INSTALL_DIR} && ${COMPOSE_CMD} restart${NC}"
    echo -e "  ${DIM}  更新镜像${NC}  ${YELLOW}cd ${INSTALL_DIR} && ${COMPOSE_CMD} pull && ${COMPOSE_CMD} up -d${NC}"
    echo ""

    echo -e "${GREEN}${BOLD}  ╚══════════════════════════════════════════════════════════╝${NC}"
    echo -e "${DIM}                         Powered by ${MAGENTA}${BOLD}${AUTHOR}${NC}"
    echo ""
}

# ── 主菜单 ────────────────────────────────────────────────────
choose_action() {
    echo -e "  ${WHITE}${BOLD}  请选择操作${NC}"
    echo ""
    echo -e "  ${GREEN}${BOLD}  [ 1 ]${NC}  ${BOLD}安装 / 重装${NC}  ${DIM}— 全新安装或覆盖现有服务${NC}"
    echo -e "  ${CYAN}${BOLD}  [ 2 ]${NC}  ${BOLD}一键升级${NC}    ${DIM}— 拉取最新镜像，保留端口与数据${NC}"
    echo -e "  ${RED}${BOLD}  [ 3 ]${NC}  ${BOLD}卸    载${NC}      ${DIM}— 移除容器、镜像及全部数据${NC}"
    echo ""
    line_thin

    while true; do
        echo -ne "  ${CYAN}›${NC} 请输入选项 ${DIM}[1/2/3]${NC}（默认 ${GREEN}1${NC}）：${BOLD} "
        read -r ACTION_CHOICE
        echo -ne "${NC}"
        ACTION_CHOICE=${ACTION_CHOICE:-1}
        case "$ACTION_CHOICE" in
            1|2|3) break ;;
            *) print_warn "请输入 1、2 或 3" ;;
        esac
    done
}

# ── 卸载流程 ──────────────────────────────────────────────────
do_uninstall() {
    echo ""
    echo -e "${RED}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║                                                          ║"
    echo "  ║      ⚠   卸 载 将 删 除 以 下 全 部 内 容              ║"
    echo "  ║                                                          ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "  ${DIM}  容    器${NC}  ${WHITE}mpd-hls${NC}"
    echo -e "  ${DIM}  镜    像${NC}  ${WHITE}charmingcheung000/mpd-hls:latest${NC}"
    echo -e "  ${DIM}           ${NC}  ${WHITE}charmingcheung000/mpd-hls:alpha${NC}"
    echo -e "  ${DIM}  数据目录${NC}  ${RED}${BOLD}${INSTALL_DIR}${NC}  ${RED}（含所有 CDM 密钥、数据库）${NC}"
    echo ""
    line_thin
    echo ""
    echo -ne "  ${RED}${BOLD}›${NC} 确认卸载？此操作${RED}${BOLD}不可恢复${NC}，请输入 ${BOLD}YES${NC} 确认：${BOLD} "
    read -r CONFIRM
    echo -ne "${NC}"

    if [ "${CONFIRM}" != "YES" ]; then
        echo ""
        print_warn "已取消卸载，未做任何更改"
        echo ""
        exit 0
    fi

    echo ""

    # ── 停止并删除容器 ──
    print_step "1/3" "停止并删除容器"
    echo ""
    if docker inspect mpd-hls &>/dev/null; then
        # 优先用 compose down（同时移除网络）
        if [ -f "${COMPOSE_FILE}" ]; then
            if docker compose version &>/dev/null 2>&1; then
                docker compose -f "${COMPOSE_FILE}" down --remove-orphans 2>/dev/null && \
                    print_ok "Compose 服务已停止并移除" || true
            elif command -v docker-compose &>/dev/null; then
                docker-compose -f "${COMPOSE_FILE}" down --remove-orphans 2>/dev/null && \
                    print_ok "Compose 服务已停止并移除" || true
            fi
        fi
        # 强制兜底删除容器
        if docker inspect mpd-hls &>/dev/null; then
            docker rm -f mpd-hls 2>/dev/null && print_ok "容器 mpd-hls 已强制删除"
        fi
    else
        print_info "未发现正在运行的 mpd-hls 容器，跳过"
    fi

    # ── 删除镜像 ──
    print_step "2/3" "删除 Docker 镜像"
    echo ""
    local removed_any=0
    for tag in latest alpha; do
        IMG="charmingcheung000/mpd-hls:${tag}"
        if docker image inspect "${IMG}" &>/dev/null; then
            docker rmi -f "${IMG}" 2>/dev/null && \
                print_ok "镜像已删除：${CYAN}${IMG}${NC}" && removed_any=1
        fi
    done
    # 同时清理可能残留的悬空层
    docker image prune -f &>/dev/null || true
    [ "$removed_any" -eq 0 ] && print_info "未发现相关镜像，跳过"

    # ── 删除数据目录 ──
    print_step "3/3" "删除安装目录"
    echo ""
    if [ -d "${INSTALL_DIR}" ]; then
        rm -rf "${INSTALL_DIR}"
        print_ok "目录已彻底删除：${RED}${INSTALL_DIR}${NC}"
    else
        print_info "目录不存在，跳过：${INSTALL_DIR}"
    fi

    # ── 卸载完成 ──
    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║                                                          ║"
    echo "  ║        ✅   卸 载 完 成 ！  已 清 理 全 部 内 容       ║"
    echo "  ║                                                          ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${DIM}                         Powered by ${MAGENTA}${BOLD}${AUTHOR}${NC}"
    echo ""
}

# ── 升级流程 ──────────────────────────────────────────────────
do_upgrade() {
    # ── 读取当前端口 ──
    local CURRENT_PORT=""
    if [ -f "${COMPOSE_FILE}" ]; then
        # 从 compose 文件中提取宿主机端口（取第一条 0.0.0.0:XXXX: 规则）
        CURRENT_PORT=$(grep -oP '0\.0\.0\.0:\K[0-9]+(?=:[0-9]+)' "${COMPOSE_FILE}" 2>/dev/null | head -1)
    fi
    CURRENT_PORT=${CURRENT_PORT:-${DEFAULT_PORT}}

    # ── 读取当前版本 tag ──
    local CURRENT_TAG=""
    if [ -f "${COMPOSE_FILE}" ]; then
        CURRENT_TAG=$(grep -oP 'mpd-hls:\K\S+' "${COMPOSE_FILE}" 2>/dev/null | head -1)
    fi
    CURRENT_TAG=${CURRENT_TAG:-latest}

    # ── 显示升级信息 ──
    echo ""
    echo -e "  ${BOLD}${WHITE}  当前安装信息${NC}"
    line_cyan
    echo -e "  ${DIM}  版本 Tag${NC}  ${CYAN}${BOLD}${CURRENT_TAG}${NC}"
    echo -e "  ${DIM}  监听端口${NC}  ${CYAN}${BOLD}${CURRENT_PORT}${NC}  ${DIM}（升级后保持不变）${NC}"
    echo -e "  ${DIM}  数据目录${NC}  ${WHITE}${VAR_DIR}${NC}  ${DIM}（升级后保持不变）${NC}"
    echo ""

    # ── 检测是否已安装 ──
    if ! docker inspect mpd-hls &>/dev/null && [ ! -f "${COMPOSE_FILE}" ]; then
        print_warn "未检测到已安装的 mpd-hls 服务"
        echo ""
        echo -ne "  ${CYAN}›${NC} 是否直接进行全新安装？${DIM}[Y/n]${NC}：${BOLD} "
        read -r GO_INSTALL
        echo -ne "${NC}"
        GO_INSTALL=${GO_INSTALL:-Y}
        if [[ "${GO_INSTALL}" =~ ^[Yy]$ ]]; then
            do_install
        fi
        return
    fi

    # ── 确认升级 ──
    line_thin
    echo ""
    echo -ne "  ${CYAN}›${NC} 确认升级？将拉取最新 ${CYAN}${BOLD}:${CURRENT_TAG}${NC} 镜像并重启服务 ${DIM}[Y/n]${NC}：${BOLD} "
    read -r UP_CONFIRM
    echo -ne "${NC}"
    UP_CONFIRM=${UP_CONFIRM:-Y}
    if [[ ! "${UP_CONFIRM}" =~ ^[Yy]$ ]]; then
        echo ""
        print_warn "已取消升级，未做任何更改"
        echo ""
        exit 0
    fi

    # ── 步骤 1：检测 Docker & Compose ──
    print_step "1/3" "检测 Docker 环境"
    echo ""
    check_docker
    check_compose

    # ── 步骤 2：拉取最新镜像 ──
    print_step "2/3" "拉取最新镜像"
    echo ""
    print_info "正在拉取 charmingcheung000/mpd-hls:${CURRENT_TAG}，请稍候..."
    echo ""

    cd "${INSTALL_DIR}"
    $COMPOSE_CMD pull

    # ── 步骤 3：重启容器（保留端口与数据） ──
    print_step "3/3" "重启服务"
    echo ""
    $COMPOSE_CMD up -d --remove-orphans
    print_ok "容器已使用新镜像重启"

    wait_healthy

    # ── 升级摘要 ──
    get_ip
    NEW_IMAGE_ID=$(docker inspect --format='{{.Image}}' mpd-hls 2>/dev/null | cut -c1-20 || echo "unknown")
    CONTAINER_ID=$(docker inspect --format='{{.Id}}'    mpd-hls 2>/dev/null | cut -c1-12 || echo "unknown")

    echo ""
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║                                                          ║"
    echo "  ║        ✅   升 级 完 成 ！  服 务 已 重 启              ║"
    echo "  ║                                                          ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "  ${BOLD}${WHITE}  升级信息${NC}"
    line_cyan
    echo -e "  ${DIM}  镜    像${NC}  ${CYAN}charmingcheung000/mpd-hls:${CURRENT_TAG}${NC}  ${DIM}（已更新至最新）${NC}"
    echo -e "  ${DIM}  容器 ID${NC}  ${WHITE}${CONTAINER_ID}${NC}"
    echo ""

    echo -e "  ${BOLD}${WHITE}  访问地址${NC}"
    line_cyan
    echo -e "  ${DIM}  内    网${NC}  ${GREEN}${BOLD}http://${LOCAL_IP}:${CURRENT_PORT}${NC}"
    echo -e "  ${DIM}  公    网${NC}  ${GREEN}${BOLD}http://${PUBLIC_IP}:${CURRENT_PORT}${NC}"
    echo ""

    echo -e "  ${BOLD}${WHITE}  数据目录${NC}"
    line_cyan
    echo -e "  ${DIM}  路    径${NC}  ${WHITE}${VAR_DIR}${NC}  ${DIM}（数据完整保留）${NC}"
    echo ""

    echo -e "${CYAN}${BOLD}  ╚══════════════════════════════════════════════════════════╝${NC}"
    echo -e "${DIM}                         Powered by ${MAGENTA}${BOLD}${AUTHOR}${NC}"
    echo ""
}

# ── 安装流程 ──────────────────────────────────────────────────
do_install() {
    choose_version
    check_docker
    check_compose
    choose_port
    setup_files
    start_service
    wait_healthy
    open_firewall
    print_summary
}

# ── 主流程 ────────────────────────────────────────────────────
main() {
    print_banner
    check_root
    choose_action

    case "$ACTION_CHOICE" in
        1) do_install   ;;
        2) do_upgrade   ;;
        3) do_uninstall ;;
    esac
}

main "$@"
