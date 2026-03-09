#!/bin/bash
# Chrome Proxy Configuration Script for macOS
# Usage: ./chrome-proxy.sh [command] [options]

set -e

NETWORK_SERVICE="Wi-Fi"
CONFIG_FILE="$HOME/.chrome-proxy.conf"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  set <host> <port> [user] [pass]   Save proxy configuration"
    echo "  on                                 Enable proxy (system-wide + launch Chrome)"
    echo "  off                                Disable proxy and restore settings"
    echo "  launch                             Launch Chrome with proxy (no system changes)"
    echo "  status                             Show current proxy status"
    echo "  test                               Test if proxy is working"
    echo ""
    echo "Examples:"
    echo "  $0 set 192.168.1.100 8080"
    echo "  $0 set proxy.example.com 3128 myuser mypass"
    echo "  $0 on"
    echo "  $0 launch"
    echo "  $0 off"
}

save_config() {
    local host="$1"
    local port="$2"
    local user="${3:-}"
    local pass="${4:-}"

    cat > "$CONFIG_FILE" <<EOF
PROXY_HOST=$host
PROXY_PORT=$port
PROXY_USER=$user
PROXY_PASS=$pass
EOF
    chmod 600 "$CONFIG_FILE"
    echo -e "${GREEN}Proxy configuration saved.${NC}"
    echo "  Host: $host"
    echo "  Port: $port"
    [ -n "$user" ] && echo "  User: $user"
}

load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}No proxy configured. Run: $0 set <host> <port>${NC}"
        exit 1
    fi
    source "$CONFIG_FILE"
}

detect_network_service() {
    local active
    active=$(networksetup -listnetworkserviceorder | grep -B1 "$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')" | head -1 | sed 's/^([0-9]*) //' | sed 's/^ *//')
    if [ -n "$active" ]; then
        NETWORK_SERVICE="$active"
    fi
}

enable_system_proxy() {
    load_config
    detect_network_service

    echo -e "${YELLOW}Configuring system proxy on '$NETWORK_SERVICE'...${NC}"

    # Set HTTP proxy
    networksetup -setwebproxy "$NETWORK_SERVICE" "$PROXY_HOST" "$PROXY_PORT"
    networksetup -setwebproxystate "$NETWORK_SERVICE" on

    # Set HTTPS proxy
    networksetup -setsecurewebproxy "$NETWORK_SERVICE" "$PROXY_HOST" "$PROXY_PORT"
    networksetup -setsecurewebproxystate "$NETWORK_SERVICE" on

    # Set authenticated proxy if credentials provided
    if [ -n "$PROXY_USER" ] && [ -n "$PROXY_PASS" ]; then
        networksetup -setwebproxy "$NETWORK_SERVICE" "$PROXY_HOST" "$PROXY_PORT" on "$PROXY_USER" "$PROXY_PASS"
        networksetup -setsecurewebproxy "$NETWORK_SERVICE" "$PROXY_HOST" "$PROXY_PORT" on "$PROXY_USER" "$PROXY_PASS"
    fi

    echo -e "${GREEN}System proxy enabled.${NC}"
}

disable_system_proxy() {
    detect_network_service

    echo -e "${YELLOW}Disabling system proxy on '$NETWORK_SERVICE'...${NC}"

    networksetup -setwebproxystate "$NETWORK_SERVICE" off
    networksetup -setsecurewebproxystate "$NETWORK_SERVICE" off

    echo -e "${GREEN}System proxy disabled.${NC}"
}

launch_chrome() {
    load_config

    local proxy_url
    if [ -n "$PROXY_USER" ] && [ -n "$PROXY_PASS" ]; then
        proxy_url="http://${PROXY_USER}:${PROXY_PASS}@${PROXY_HOST}:${PROXY_PORT}"
    else
        proxy_url="http://${PROXY_HOST}:${PROXY_PORT}"
    fi

    echo -e "${GREEN}Launching Chrome with proxy ${PROXY_HOST}:${PROXY_PORT}...${NC}"

    /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
        --proxy-server="http=${PROXY_HOST}:${PROXY_PORT};https=${PROXY_HOST}:${PROXY_PORT}" \
        --proxy-bypass-list="localhost;127.0.0.1" \
        &>/dev/null &

    echo "Chrome launched (PID: $!)"
}

show_status() {
    detect_network_service

    echo "Network service: $NETWORK_SERVICE"
    echo ""

    echo "HTTP Proxy:"
    networksetup -getwebproxy "$NETWORK_SERVICE"
    echo ""

    echo "HTTPS Proxy:"
    networksetup -getsecurewebproxy "$NETWORK_SERVICE"
    echo ""

    if [ -f "$CONFIG_FILE" ]; then
        echo "Saved config:"
        load_config
        echo "  Host: $PROXY_HOST"
        echo "  Port: $PROXY_PORT"
        [ -n "$PROXY_USER" ] && echo "  User: $PROXY_USER"
    else
        echo "No saved proxy configuration."
    fi
}

test_proxy() {
    load_config

    echo -e "${YELLOW}Testing proxy ${PROXY_HOST}:${PROXY_PORT}...${NC}"

    # Test connectivity
    if nc -z -w 5 "$PROXY_HOST" "$PROXY_PORT" 2>/dev/null; then
        echo -e "${GREEN}Proxy is reachable.${NC}"
    else
        echo -e "${RED}Cannot reach proxy at ${PROXY_HOST}:${PROXY_PORT}${NC}"
        exit 1
    fi

    # Test HTTP through proxy
    echo "Checking external IP via proxy..."
    local ip
    ip=$(curl -s --max-time 10 --proxy "http://${PROXY_HOST}:${PROXY_PORT}" https://api.ipify.org 2>/dev/null)

    if [ -n "$ip" ]; then
        echo -e "${GREEN}Proxy working. External IP: ${ip}${NC}"
    else
        echo -e "${RED}Proxy connected but cannot route traffic.${NC}"
        exit 1
    fi
}

# Main
case "${1:-}" in
    set)
        if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
            echo -e "${RED}Usage: $0 set <host> <port> [user] [pass]${NC}"
            exit 1
        fi
        save_config "$2" "$3" "${4:-}" "${5:-}"
        ;;
    on)
        enable_system_proxy
        launch_chrome
        ;;
    off)
        disable_system_proxy
        ;;
    launch)
        launch_chrome
        ;;
    status)
        show_status
        ;;
    test)
        test_proxy
        ;;
    *)
        print_usage
        ;;
esac
