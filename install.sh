#!/usr/bin/env bash

set -euo pipefail

[ -t 0 ] || exec < /dev/tty

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

INSTALL_DIR="/opt/mpd-hls"
VAR_DIR="${INSTALL_DIR}/var"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
NGINX_CONF="/etc/nginx/conf.d/mpd-hls.conf"
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
ok() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err() { echo -e "${RED}[ERR]${NC} $*"; }
info() { echo -e "${CYAN}[INFO]${NC} $*"; }

step() {
    echo ""
    echo -e "${BOLD}${CYAN}==> $*${NC}"
}

banner() {
    clear || true
    echo -e "${CYAN}${BOLD}"
    echo "MPD-HLS one-key installer"
    echo -e "${NC}${DIM}Docker + Compose + Nginx reverse proxy | ${AUTHOR}${NC}"
    echo ""
}

need_root() {
    if [ "${EUID}" -ne 0 ]; then
        err "Please run as root: sudo bash install.sh"
        exit 1
    fi
}

ensure_download_tool() {
    if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
        return
    fi

    info "Installing curl..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y curl
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y curl
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl
    else
        err "curl/wget is missing and no supported package manager was found."
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
    echo -e "${BOLD}Choose action:${NC}"
    echo "  1) Install / reinstall"
    echo "  2) Upgrade"
    echo "  3) Uninstall"
    line

    while true; do
        read -r -p "Select [1/2/3] (default: 1): " ACTION_CHOICE
        ACTION_CHOICE="${ACTION_CHOICE:-1}"
        case "$ACTION_CHOICE" in
            1|2|3) break ;;
            *) warn "Please enter 1, 2, or 3." ;;
        esac
    done
}

choose_version() {
    step "Choose version"
    echo "  1) Stable latest"
    echo "  2) Alpha"
    line

    while true; do
        read -r -p "Select [1/2] (default: 1): " VERSION_CHOICE
        VERSION_CHOICE="${VERSION_CHOICE:-1}"
        case "$VERSION_CHOICE" in
            1)
                VERSION_TAG="latest"
                VERSION_LABEL="Stable latest"
                VERSION_YML_URL="${LATEST_YML_URL}"
                ok "Selected ${VERSION_LABEL}"
                break
                ;;
            2)
                VERSION_TAG="alpha"
                VERSION_LABEL="Alpha"
                VERSION_YML_URL="${ALPHA_YML_URL}"
                warn "Selected ${VERSION_LABEL}"
                break
                ;;
            *) warn "Please enter 1 or 2." ;;
        esac
    done
}

install_docker() {
    step "Install Docker"
    ensure_download_tool

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL https://get.docker.com | sh
    else
        wget -qO- https://get.docker.com | sh
    fi

    systemctl enable --now docker
    ok "Docker installed: $(docker --version)"
}

check_docker() {
    step "Check Docker"

    if command -v docker >/dev/null 2>&1; then
        ok "Docker found: $(docker --version)"
    else
        warn "Docker not found, installing online..."
        install_docker
    fi

    if ! docker info >/dev/null 2>&1; then
        info "Starting Docker service..."
        systemctl enable --now docker
    fi

    ok "Docker service is ready."
}

install_compose_plugin() {
    step "Install Docker Compose plugin"
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
        *) err "Unsupported architecture for Docker Compose: ${arch}"; exit 1 ;;
    esac

    mkdir -p /usr/local/lib/docker/cli-plugins
    download_to "https://github.com/docker/compose/releases/download/${latest}/docker-compose-linux-${arch}" /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    ok "Docker Compose plugin installed: ${latest}"
}

check_compose() {
    step "Check Docker Compose"

    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
        ok "Docker Compose found: $(docker compose version --short 2>/dev/null || echo v2)"
    elif command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
        ok "docker-compose found: $(docker-compose --version)"
    else
        warn "Docker Compose not found, installing online..."
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
    step "Configure service port"
    info "Default port is ${DEFAULT_PORT}. Press Enter to use it."

    while true; do
        read -r -p "Service port [1-65535] (default: ${DEFAULT_PORT}): " USER_PORT
        USER_PORT="${USER_PORT:-$DEFAULT_PORT}"

        if ! [[ "$USER_PORT" =~ ^[0-9]+$ ]]; then
            warn "Please enter a valid number."
            continue
        fi
        if [ "$USER_PORT" -lt 1 ] || [ "$USER_PORT" -gt 65535 ]; then
            warn "Port must be between 1 and 65535."
            continue
        fi
        if port_in_use "$USER_PORT"; then
            warn "Port ${USER_PORT} is already in use."
            continue
        fi

        ok "Service port: ${USER_PORT}"
        break
    done
}

choose_domain() {
    step "Configure Nginx domain"

    echo -e "${YELLOW}${BOLD}安全提示 / Security notice:${NC}"
    echo -e "${YELLOW}  1. 必须使用自定义令牌作为订阅连接。 / You must use a custom token for subscription links.${NC}"
    echo -e "${YELLOW}  2. 不能使用依赖 ?u=&p= 暴露用户名/密码的订阅连接。 / Do not use subscription URLs that depend on ?u=&p= and expose username/password.${NC}"
    echo ""

    while true; do
        read -r -p "Enter your domain for Nginx reverse proxy: " DOMAIN_NAME
        DOMAIN_NAME="$(echo "$DOMAIN_NAME" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

        if [ -z "$DOMAIN_NAME" ]; then
            warn "Domain cannot be empty."
            continue
        fi
        if echo "$DOMAIN_NAME" | grep -Eq '[[:space:]/:]'; then
            warn "Please enter only the domain, for example: example.com"
            continue
        fi

        ok "Nginx domain: ${DOMAIN_NAME}"
        break
    done
}

setup_files() {
    step "Download compose file"

    mkdir -p "${VAR_DIR}"
    chmod -R 775 "${INSTALL_DIR}"

    local tmp_yml
    tmp_yml="$(mktemp)"
    download_to "${VERSION_YML_URL}" "${tmp_yml}" || {
        rm -f "${tmp_yml}"
        err "Failed to download compose template."
        exit 1
    }

    sed \
        -e "s|0\.0\.0\.0:[0-9]*:${CONTAINER_PORT}|0.0.0.0:${USER_PORT}:${CONTAINER_PORT}|g" \
        -e "s|\[::\]:[0-9]*:${CONTAINER_PORT}|[::]:${USER_PORT}:${CONTAINER_PORT}|g" \
        -e "s|/opt/mpd-hls/var|${VAR_DIR}|g" \
        "${tmp_yml}" > "${COMPOSE_FILE}"

    rm -f "${tmp_yml}"
    ok "Compose file written: ${COMPOSE_FILE}"
}

start_service() {
    step "Pull image and start service"

    cd "${INSTALL_DIR}"
    ${COMPOSE_CMD} pull
    ${COMPOSE_CMD} up -d --remove-orphans

    ok "Container started."
}

wait_healthy() {
    step "Wait for container"

    local tries=0 status
    while [ "$tries" -lt 20 ]; do
        status="$(docker inspect --format='{{.State.Status}}' mpd-hls 2>/dev/null || echo unknown)"
        if [ "$status" = "running" ]; then
            ok "Container status: running"
            return
        fi
        sleep 2
        tries=$((tries + 1))
    done

    warn "Container is not running yet. Check logs with: docker logs mpd-hls"
}

install_nginx() {
    step "Install Nginx"

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y nginx
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y nginx
    elif command -v yum >/dev/null 2>&1; then
        yum install -y nginx
    else
        err "No supported package manager found. Please install Nginx manually."
        exit 1
    fi

    ok "Nginx installed."
}

check_nginx() {
    step "Check Nginx"

    if command -v nginx >/dev/null 2>&1; then
        ok "Nginx already installed, skip installation: $(nginx -v 2>&1)"
        info "Continue to configure reverse proxy..."
    else
        warn "Nginx not found, installing online..."
        install_nginx
        info "Nginx installation completed, continue to configure reverse proxy..."
    fi
}

configure_nginx() {
    step "Write Nginx reverse proxy"

    mkdir -p /etc/nginx/conf.d
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

    info "Testing Nginx configuration..."
    nginx -t

    info "Starting and enabling Nginx service..."
    systemctl enable --now nginx

    info "Reloading Nginx to apply reverse proxy configuration..."
    systemctl reload nginx || systemctl restart nginx

    ok "Nginx reverse proxy is active: ${NGINX_CONF}"
}

setup_nginx() {
    choose_domain
    check_nginx
    configure_nginx
}

open_firewall() {
    step "Open firewall ports"

    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${USER_PORT}/tcp" >/dev/null 2>&1 || true
        ufw allow 80/tcp >/dev/null 2>&1 || true
        ok "ufw allowed ${USER_PORT}/tcp and 80/tcp"
    fi

    if command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port="${USER_PORT}/tcp" >/dev/null 2>&1 || true
        firewall-cmd --permanent --add-service=http >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
        ok "firewalld allowed ${USER_PORT}/tcp and http"
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
    if [ -f "${NGINX_CONF}" ]; then
        current="$(awk '/server_name/ {gsub(/;/, "", $2); print $2; exit}' "${NGINX_CONF}" 2>/dev/null || true)"
    fi
    echo "$current"
}

print_summary() {
    get_ip

    local container_id created
    container_id="$(docker inspect --format='{{.Id}}' mpd-hls 2>/dev/null | cut -c1-12 || echo unknown)"
    created="$(docker inspect --format='{{.Created}}' mpd-hls 2>/dev/null | cut -c1-19 || echo unknown)"

    echo ""
    echo -e "${GREEN}${BOLD}Install completed.${NC}"
    line
    echo "Image: charmingcheung000/mpd-hls:${VERSION_TAG:-unknown}"
    echo "Container ID: ${container_id}"
    echo "Created: ${created}"
    echo "Local URL: http://${LOCAL_IP}:${USER_PORT}"
    echo "Public URL: http://${PUBLIC_IP}:${USER_PORT}"
    if [ -n "${DOMAIN_NAME}" ]; then
        echo "Nginx URL: http://${DOMAIN_NAME}"
    fi
    echo "Data dir: ${VAR_DIR}"
    echo "Compose file: ${COMPOSE_FILE}"
    echo "Nginx conf: ${NGINX_CONF}"
    echo ""
    echo "Useful commands:"
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
    step "Upgrade"

    USER_PORT="$(read_current_port)"
    DOMAIN_NAME="$(read_current_domain)"

    if ! docker inspect mpd-hls >/dev/null 2>&1 && [ ! -f "${COMPOSE_FILE}" ]; then
        warn "Existing mpd-hls installation was not found."
        read -r -p "Run a fresh install now? [Y/n]: " GO_INSTALL
        GO_INSTALL="${GO_INSTALL:-Y}"
        if [[ "$GO_INSTALL" =~ ^[Yy]$ ]]; then
            do_install
        fi
        return
    fi

    info "Current service port: ${USER_PORT}"
    read -r -p "Upgrade and restart service? [Y/n]: " UP_CONFIRM
    UP_CONFIRM="${UP_CONFIRM:-Y}"
    if [[ ! "$UP_CONFIRM" =~ ^[Yy]$ ]]; then
        warn "Upgrade cancelled."
        exit 0
    fi

    check_docker
    check_compose

    cd "${INSTALL_DIR}"
    ${COMPOSE_CMD} pull
    ${COMPOSE_CMD} up -d --remove-orphans
    wait_healthy

    if [ -z "${DOMAIN_NAME}" ]; then
        setup_nginx
    else
        check_nginx
        configure_nginx
    fi

    open_firewall
    VERSION_TAG="$(grep -oE 'mpd-hls:[^[:space:]]+' "${COMPOSE_FILE}" 2>/dev/null | head -1 | cut -d: -f2 || echo unknown)"
    print_summary
}

do_uninstall() {
    step "Uninstall"
    echo "This will remove the mpd-hls container, images, data directory, and Nginx site config."
    read -r -p "Type YES to continue: " CONFIRM
    if [ "$CONFIRM" != "YES" ]; then
        warn "Uninstall cancelled."
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

    if command -v nginx >/dev/null 2>&1; then
        nginx -t && systemctl reload nginx || true
    fi

    ok "Uninstall completed."
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
