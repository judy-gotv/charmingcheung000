#!/usr/bin/env bash

set -euo pipefail

[ -t 0 ] || exec < /dev/tty

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

INSTALL_DIR="/opt/mpd-hls"
VAR_DIR="${INSTALL_DIR}/var"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
NGINX_CONF="/etc/nginx/conf.d/mpd-hls.conf"
DOMAIN_FILE="${INSTALL_DIR}/nginx-domain.txt"
DEFAULT_PORT=9527
CONTAINER_PORT=9100
AUTHOR="Go-iptv"

LATEST_YML_URL="https://raw.githubusercontent.com/judy-gotv/charmingcheung000/main/latest.yml"
ALPHA_YML_URL="https://raw.githubusercontent.com/judy-gotv/charmingcheung000/main/alpha.yml"

VERSION_TAG=""
VERSION_LABEL=""
VERSION_YML_URL=""
USER_PORT="${DEFAULT_PORT}"
DOMAIN_NAME=""
COMPOSE_CMD=""

line() { echo -e "${DIM}------------------------------------------------------------${NC}"; }
ok() { echo -e "${GREEN}[完成 / OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[警告 / WARN]${NC} $*"; }
err() { echo -e "${RED}[错误 / ERR]${NC} $*"; }
info() { echo -e "${CYAN}[信息 / INFO]${NC} $*"; }

step() {
    echo ""
    echo -e "${BOLD}${CYAN}==> $*${NC}"
}

banner() {
    clear || true
    echo -e "${CYAN}${BOLD}"
    echo "MPD-HLS 一键安装脚本 / MPD-HLS one-key installer"
    echo -e "${NC}${DIM}Docker + Compose + Nginx 反向代理 / Docker + Compose + Nginx reverse proxy | ${AUTHOR}${NC}"
    echo ""
}

need_root() {
    if [ "${EUID}" -ne 0 ]; then
        err "请使用 root 权限运行 / Please run as root: sudo bash install.sh"
        exit 1
    fi
}

ensure_download_tool() {
    if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
        return
    fi

    info "正在安装 curl... / Installing curl..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y curl
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y curl
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl
    else
        err "缺少 curl/wget，且未找到支持的包管理器。 / curl/wget is missing and no supported package manager was found."
        exit 1
    fi
}

download_to() {
    local url="$1"
    local out="$2"

    ensure_download_tool
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$out"
    else
        wget -qO "$out" "$url"
    fi
}

choose_action() {
    echo -e "${BOLD}请选择操作 / Choose action:${NC}"
    echo "  1) 安装 / 重装 / Install / reinstall"
    echo "  2) 升级 / Upgrade"
    echo "  3) 卸载 / Uninstall"
    line

    while true; do
        read -r -p "请选择 [1/2/3]（默认: 1）/ Select [1/2/3] (default: 1): " ACTION_CHOICE
        ACTION_CHOICE="${ACTION_CHOICE:-1}"
        case "$ACTION_CHOICE" in
            1|2|3) break ;;
            *) warn "请输入 1、2 或 3。 / Please enter 1, 2, or 3." ;;
        esac
    done
}

choose_version() {
    step "选择版本 / Choose version"
    echo "  1) 稳定版 latest / Stable latest"
    echo "  2) 测试版 alpha / Alpha"
    line

    while true; do
        read -r -p "请选择 [1/2]（默认: 1）/ Select [1/2] (default: 1): " VERSION_CHOICE
        VERSION_CHOICE="${VERSION_CHOICE:-1}"
        case "$VERSION_CHOICE" in
            1)
                VERSION_TAG="latest"
                VERSION_LABEL="稳定版 latest / Stable latest"
                VERSION_YML_URL="${LATEST_YML_URL}"
                ok "已选择 ${VERSION_LABEL} / Selected ${VERSION_LABEL}"
                break
                ;;
            2)
                VERSION_TAG="alpha"
                VERSION_LABEL="测试版 alpha / Alpha"
                VERSION_YML_URL="${ALPHA_YML_URL}"
                warn "已选择 ${VERSION_LABEL} / Selected ${VERSION_LABEL}"
                break
                ;;
            *) warn "请输入 1 或 2。 / Please enter 1 or 2." ;;
        esac
    done
}

install_docker() {
    step "安装 Docker / Install Docker"
    ensure_download_tool

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL https://get.docker.com | sh
    else
        wget -qO- https://get.docker.com | sh
    fi

    systemctl enable --now docker
    ok "Docker 安装完成 / Docker installed: $(docker --version)"
}

check_docker() {
    step "检测 Docker / Check Docker"

    if command -v docker >/dev/null 2>&1; then
        ok "Docker 已安装 / Docker found: $(docker --version)"
    else
        warn "未检测到 Docker，正在在线安装... / Docker not found, installing online..."
        install_docker
    fi

    if ! docker info >/dev/null 2>&1; then
        info "正在启动 Docker 服务... / Starting Docker service..."
        systemctl enable --now docker
    fi

    ok "Docker 服务已就绪。 / Docker service is ready."
}

install_compose_plugin() {
    step "安装 Docker Compose 插件 / Install Docker Compose plugin"
    ensure_download_tool

    local latest arch release_json
    release_json="$(mktemp)"
    if download_to "https://api.github.com/repos/docker/compose/releases/latest" "${release_json}" >/dev/null 2>&1; then
        latest="$(grep '"tag_name"' "${release_json}" | sed -E 's/.*"([^"]+)".*/\1/' || true)"
    else
        latest=""
    fi
    rm -f "${release_json}"
    latest="${latest:-v2.27.0}"
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        *) err "Docker Compose 不支持当前架构 / Unsupported architecture for Docker Compose: ${arch}"; exit 1 ;;
    esac

    mkdir -p /usr/local/lib/docker/cli-plugins
    download_to "https://github.com/docker/compose/releases/download/${latest}/docker-compose-linux-${arch}" /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    ok "Docker Compose 插件安装完成 / Docker Compose plugin installed: ${latest}"
}

check_compose() {
    step "检测 Docker Compose / Check Docker Compose"

    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
        ok "Docker Compose 已安装 / Docker Compose found: $(docker compose version --short 2>/dev/null || echo v2)"
    elif command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
        ok "docker-compose 已安装 / docker-compose found: $(docker-compose --version)"
    else
        warn "未检测到 Docker Compose，正在在线安装... / Docker Compose not found, installing online..."
        install_compose_plugin
        COMPOSE_CMD="docker compose"
    fi
}

port_in_use() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -tln 2>/dev/null | awk '{print $4}' | grep -Eq "(:|\\])${port}$"
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tln 2>/dev/null | awk '{print $4}' | grep -Eq "(:|\\])${port}$"
    else
        return 1
    fi
}

choose_port() {
    step "配置服务端口 / Configure service port"
    info "默认端口为 ${DEFAULT_PORT}，直接回车使用默认值。 / Default port is ${DEFAULT_PORT}. Press Enter to use it."

    while true; do
        read -r -p "服务端口 [1-65535]（默认: ${DEFAULT_PORT}）/ Service port [1-65535] (default: ${DEFAULT_PORT}): " USER_PORT
        USER_PORT="${USER_PORT:-$DEFAULT_PORT}"

        if ! [[ "$USER_PORT" =~ ^[0-9]+$ ]]; then
            warn "请输入有效数字。 / Please enter a valid number."
            continue
        fi
        if [ "$USER_PORT" -lt 1 ] || [ "$USER_PORT" -gt 65535 ]; then
            warn "端口范围必须在 1 到 65535 之间。 / Port must be between 1 and 65535."
            continue
        fi
        if port_in_use "$USER_PORT"; then
            warn "端口 ${USER_PORT} 已被占用。 / Port ${USER_PORT} is already in use."
            continue
        fi

        ok "服务端口 / Service port: ${USER_PORT}"
        break
    done
}

choose_domain() {
    step "配置 Nginx 域名 / Configure Nginx domain"

    echo -e "${YELLOW}${BOLD}安全提示 / Security notice:${NC}"
    echo -e "${YELLOW}  1. 必须使用自定义令牌作为订阅连接。 / You must use a custom token for subscription links.${NC}"
    echo -e "${YELLOW}  2. 不能使用依赖 ?u=&p= 暴露用户名/密码的订阅连接。 / Do not use subscription URLs that depend on ?u=&p= and expose username/password.${NC}"
    echo ""

    while true; do
        read -r -p "请输入 Nginx 反向代理域名 / Enter your domain for Nginx reverse proxy: " DOMAIN_NAME
        DOMAIN_NAME="$(echo "$DOMAIN_NAME" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

        if [ -z "$DOMAIN_NAME" ]; then
            warn "域名不能为空。 / Domain cannot be empty."
            continue
        fi
        if echo "$DOMAIN_NAME" | grep -Eq '[[:space:]/:]'; then
            warn "请只输入域名，例如 example.com / Please enter only the domain, for example: example.com"
            continue
        fi

        ok "Nginx 域名 / Nginx domain: ${DOMAIN_NAME}"
        break
    done
}

setup_files() {
    step "下载 Compose 配置文件 / Download compose file"

    mkdir -p "${VAR_DIR}"
    chmod -R 775 "${INSTALL_DIR}"

    local tmp_yml
    tmp_yml="$(mktemp)"
    download_to "${VERSION_YML_URL}" "${tmp_yml}" || {
        rm -f "${tmp_yml}"
        err "下载 Compose 模板失败。 / Failed to download compose template."
        exit 1
    }

    sed \
        -e "s|0\.0\.0\.0:[0-9]*:${CONTAINER_PORT}|0.0.0.0:${USER_PORT}:${CONTAINER_PORT}|g" \
        -e "s|\[::\]:[0-9]*:${CONTAINER_PORT}|[::]:${USER_PORT}:${CONTAINER_PORT}|g" \
        -e "s|/opt/mpd-hls/var|${VAR_DIR}|g" \
        "${tmp_yml}" > "${COMPOSE_FILE}"

    rm -f "${tmp_yml}"
    ok "Compose 配置已写入 / Compose file written: ${COMPOSE_FILE}"
}

start_service() {
    step "拉取镜像并启动服务 / Pull image and start service"

    cd "${INSTALL_DIR}"
    ${COMPOSE_CMD} pull
    ${COMPOSE_CMD} up -d --remove-orphans

    ok "容器已启动。 / Container started."
}

wait_healthy() {
    step "等待容器运行 / Wait for container"

    local tries=0 status
    while [ "$tries" -lt 20 ]; do
        status="$(docker inspect --format='{{.State.Status}}' mpd-hls 2>/dev/null || echo unknown)"
        if [ "$status" = "running" ]; then
            ok "容器状态：running / Container status: running"
            return
        fi
        sleep 2
        tries=$((tries + 1))
    done

    warn "容器暂未进入 running 状态，请查看日志：docker logs mpd-hls / Container is not running yet. Check logs with: docker logs mpd-hls"
}

install_nginx() {
    step "安装 Nginx / Install Nginx"

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y nginx
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y nginx
    elif command -v yum >/dev/null 2>&1; then
        yum install -y nginx
    else
        err "未找到支持的包管理器，请手动安装 Nginx。 / No supported package manager found. Please install Nginx manually."
        exit 1
    fi

    ok "Nginx 安装完成。 / Nginx installed."
}

check_nginx() {
    step "检测 Nginx / Check Nginx"

    if command -v nginx >/dev/null 2>&1; then
        ok "Nginx 已安装，跳过安装 / Nginx already installed, skip installation: $(nginx -v 2>&1)"
        info "继续配置反向代理... / Continue to configure reverse proxy..."
    else
        warn "未检测到 Nginx，正在在线安装... / Nginx not found, installing online..."
        install_nginx
        info "Nginx 安装完成，继续配置反向代理... / Nginx installation completed, continue to configure reverse proxy..."
    fi
}

configure_nginx() {
    step "写入 Nginx 反向代理 / Write Nginx reverse proxy"

    mkdir -p /etc/nginx/conf.d
    mkdir -p "${INSTALL_DIR}"
    if [ -f "${NGINX_CONF}" ]; then
        cp -f "${NGINX_CONF}" "${NGINX_CONF}.bak.$(date +%Y%m%d%H%M%S)"
    fi

    cat > "${NGINX_CONF}" <<EOF
server {
    listen 80;
    server_name ${DOMAIN_NAME};

    location ~ ^/l/([A-Za-z0-9_-]+)/(video/)?index\\.m3u8$ {
        proxy_pass http://127.0.0.1:${USER_PORT};

        proxy_set_header Host \$host;
        proxy_set_header Accept-Encoding "";

        proxy_hide_header Content-Type;
        add_header Content-Type "application/vnd.apple.mpegurl" always;

        sub_filter_types *;
        sub_filter_once off;
        sub_filter ".ts" ".jpeg";

        add_header Access-Control-Allow-Origin "*" always;
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
    }

    location ~ ^/l/([A-Za-z0-9_-]+)/video/([0-9]+)\\.jpeg$ {
        proxy_pass http://127.0.0.1:${USER_PORT}/l/\$1/video/\$2.ts;

        proxy_set_header Host \$host;

        proxy_hide_header Content-Type;
        add_header Content-Type "image/jpeg" always;

        add_header Access-Control-Allow-Origin "*" always;
        add_header Cache-Control "public, max-age=86400, immutable" always;
    }

    location ~ ^/l/([A-Za-z0-9_-]+)/video/([0-9]+)\\.ts$ {
        proxy_pass http://127.0.0.1:${USER_PORT}/l/\$1/video/\$2.ts;

        proxy_set_header Host \$host;

        proxy_hide_header Content-Type;
        add_header Content-Type "image/jpeg" always;

        add_header Access-Control-Allow-Origin "*" always;
        add_header Cache-Control "public, max-age=86400, immutable" always;
    }

    location / {
        proxy_pass http://127.0.0.1:${USER_PORT};

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    printf '%s\n' "${DOMAIN_NAME}" > "${DOMAIN_FILE}"

    info "正在测试 Nginx 配置... / Testing Nginx configuration..."
    nginx -t

    info "正在启动并设置 Nginx 开机自启... / Starting and enabling Nginx service..."
    systemctl enable --now nginx

    info "正在重载 Nginx 使反向代理生效... / Reloading Nginx to apply reverse proxy configuration..."
    systemctl reload nginx || systemctl restart nginx

    ok "Nginx 反向代理已生效 / Nginx reverse proxy is active: ${NGINX_CONF}"
}

setup_nginx() {
    choose_domain
    check_nginx
    configure_nginx
}

open_firewall() {
    step "放行防火墙端口 / Open firewall ports"

    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${USER_PORT}/tcp" >/dev/null 2>&1 || true
        ufw allow 80/tcp >/dev/null 2>&1 || true
        ok "ufw 已放行 ${USER_PORT}/tcp 和 80/tcp / ufw allowed ${USER_PORT}/tcp and 80/tcp"
    fi

    if command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port="${USER_PORT}/tcp" >/dev/null 2>&1 || true
        firewall-cmd --permanent --add-service=http >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
        ok "firewalld 已放行 ${USER_PORT}/tcp 和 http / firewalld allowed ${USER_PORT}/tcp and http"
    fi
}

get_ip() {
    LOCAL_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
    PUBLIC_IP="$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || curl -s --max-time 5 http://ip.sb 2>/dev/null || echo unknown)"
}

read_current_port() {
    local current=""
    if [ -f "${COMPOSE_FILE}" ]; then
        current="$(grep -oE '0\.0\.0\.0:[0-9]+:' "${COMPOSE_FILE}" 2>/dev/null | head -1 | cut -d: -f2 || true)"
    fi
    echo "${current:-$DEFAULT_PORT}"
}

read_current_domain() {
    local current=""
    if [ -f "${DOMAIN_FILE}" ]; then
        current="$(tr -d '[:space:]' < "${DOMAIN_FILE}" 2>/dev/null || true)"
    fi
    if [ -z "${current}" ] && [ -f "${NGINX_CONF}" ]; then
        current="$(awk '/server_name/ {gsub(/;/, "", $2); print $2; exit}' "${NGINX_CONF}" 2>/dev/null || true)"
    fi
    echo "$current"
}

detect_existing_nginx_proxy() {
    local port="$1"
    local paths=(
        /etc/nginx/conf.d
        /etc/nginx/sites-enabled
        /etc/nginx/sites-available
    )
    local dir file

    for dir in "${paths[@]}"; do
        [ -d "${dir}" ] || continue
        while IFS= read -r -d '' file; do
            if grep -Eq "proxy_pass[[:space:]]+http://127\.0\.0\.1:${port}" "${file}" 2>/dev/null || \
               grep -Eq "server_name[[:space:]]+[^;]+" "${file}" 2>/dev/null; then
                echo "${file}"
                return 0
            fi
        done < <(find "${dir}" -maxdepth 1 -type f \( -name '*.conf' -o -name '*' \) -print0 2>/dev/null)
    done

    return 1
}

print_summary() {
    get_ip

    local container_id created
    container_id="$(docker inspect --format='{{.Id}}' mpd-hls 2>/dev/null | cut -c1-12 || echo unknown)"
    created="$(docker inspect --format='{{.Created}}' mpd-hls 2>/dev/null | cut -c1-19 || echo unknown)"

    echo ""
    echo -e "${GREEN}${BOLD}安装完成。 / Install completed.${NC}"
    line
    echo "镜像 / Image: charmingcheung000/mpd-hls:${VERSION_TAG:-unknown}"
    echo "容器 ID / Container ID: ${container_id}"
    echo "创建时间 / Created: ${created}"
    echo "内网地址 / Local URL: http://${LOCAL_IP}:${USER_PORT}"
    echo "公网地址 / Public URL: http://${PUBLIC_IP}:${USER_PORT}"
    if [ -n "${DOMAIN_NAME}" ]; then
        echo "Nginx 地址 / Nginx URL: http://${DOMAIN_NAME}"
    fi
    echo "数据目录 / Data dir: ${VAR_DIR}"
    echo "Compose 文件 / Compose file: ${COMPOSE_FILE}"
    echo "Nginx 配置 / Nginx conf: ${NGINX_CONF}"
    echo ""
    echo "常用命令 / Useful commands:"
    echo "  docker logs -f mpd-hls"
    echo "  cd ${INSTALL_DIR} && ${COMPOSE_CMD} restart"
    echo "  cd ${INSTALL_DIR} && ${COMPOSE_CMD} down"
}

do_install() {
    choose_version
    check_docker
    check_compose
    choose_port
    setup_files
    start_service
    wait_healthy
    setup_nginx
    open_firewall
    print_summary
}

do_upgrade() {
    step "升级 / Upgrade"

    USER_PORT="$(read_current_port)"
    DOMAIN_NAME="$(read_current_domain)"
    local existing_nginx_conf=""
    existing_nginx_conf="$(detect_existing_nginx_proxy "${USER_PORT}" 2>/dev/null || true)"

    if ! docker inspect mpd-hls >/dev/null 2>&1 && [ ! -f "${COMPOSE_FILE}" ]; then
        warn "未检测到已安装的 mpd-hls 服务。 / Existing mpd-hls installation was not found."
        read -r -p "是否立即执行全新安装？[Y/n] / Run a fresh install now? [Y/n]: " GO_INSTALL
        GO_INSTALL="${GO_INSTALL:-Y}"
        if [[ "$GO_INSTALL" =~ ^[Yy]$ ]]; then
            do_install
        fi
        return
    fi

    info "当前服务端口 / Current service port: ${USER_PORT}"
    read -r -p "确认升级并重启服务？[Y/n] / Upgrade and restart service? [Y/n]: " UP_CONFIRM
    UP_CONFIRM="${UP_CONFIRM:-Y}"
    if [[ ! "$UP_CONFIRM" =~ ^[Yy]$ ]]; then
        warn "已取消升级。 / Upgrade cancelled."
        exit 0
    fi

    check_docker
    check_compose

    cd "${INSTALL_DIR}"
    ${COMPOSE_CMD} pull
    ${COMPOSE_CMD} up -d --remove-orphans
    wait_healthy

    if [ -n "${existing_nginx_conf}" ]; then
        ok "检测到现有 Nginx 配置，跳过域名输入和反代重写 / Existing Nginx config detected, skip domain prompt and reverse-proxy rewrite: ${existing_nginx_conf}"
        if command -v nginx >/dev/null 2>&1; then
            nginx -t && systemctl reload nginx || systemctl restart nginx || true
        fi
    elif [ -n "${DOMAIN_NAME}" ]; then
        check_nginx
        configure_nginx
    else
        info "未找到现成的 Nginx 反向代理配置，跳过反向代理更新。 / No existing Nginx reverse proxy config found, skip update."
    fi

    open_firewall
    VERSION_TAG="$(grep -oE 'mpd-hls:[^[:space:]]+' "${COMPOSE_FILE}" 2>/dev/null | head -1 | cut -d: -f2 || echo unknown)"
    print_summary
}

do_uninstall() {
    step "卸载 / Uninstall"
    echo "这将删除 mpd-hls 容器、镜像、数据目录和 Nginx 站点配置。 / This will remove the mpd-hls container, images, data directory, and Nginx site config."
    read -r -p "请输入 YES 确认继续 / Type YES to continue: " CONFIRM
    if [ "$CONFIRM" != "YES" ]; then
        warn "已取消卸载。 / Uninstall cancelled."
        exit 0
    fi

    check_docker || true
    check_compose || true

    if [ -f "${COMPOSE_FILE}" ]; then
        ${COMPOSE_CMD} -f "${COMPOSE_FILE}" down --remove-orphans || true
    fi

    docker rm -f mpd-hls >/dev/null 2>&1 || true
    docker rmi -f charmingcheung000/mpd-hls:latest >/dev/null 2>&1 || true
    docker rmi -f charmingcheung000/mpd-hls:alpha >/dev/null 2>&1 || true

    rm -rf "${INSTALL_DIR}"
    rm -f "${NGINX_CONF}"
    rm -f "${DOMAIN_FILE}"

    if command -v nginx >/dev/null 2>&1; then
        nginx -t && systemctl reload nginx || true
    fi

    ok "卸载完成。 / Uninstall completed."
}

main() {
    banner
    need_root
    choose_action

    case "$ACTION_CHOICE" in
        1) do_install ;;
        2) do_upgrade ;;
        3) do_uninstall ;;
    esac
}

main "$@"
