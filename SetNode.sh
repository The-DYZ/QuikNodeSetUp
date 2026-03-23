#!/bin/bash

# ============================================
# ShadowsocksR 完整管理脚本 for Ubuntu/Debian
# 功能：安装 | 配置 | 管理 | 卸载
# ============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# 配置变量
SSR_DIR="/usr/local/shadowsocksr"
SSR_REPO="https://github.com/shadowsocksrr/shadowsocksr.git"
SERVICE_FILE="/etc/systemd/system/shadowsocksr.service"
CONFIG_FILE="/etc/shadowsocksr.json"
INFO_FILE="/root/ssr_info.txt"

# ============================================
# 工具函数
# ============================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误：请使用 root 用户运行此脚本${NC}"
        exit 1
    fi
}

generate_port() {
    shuf -i 10000-65535 -n 1
}

generate_password() {
    tr -dc 'a-zA-Z0-9!@#$%^&*' < /dev/urandom | head -c 16
}

get_server_ip() {
    local ip=$(curl -s https://api.ipify.org 2>/dev/null || curl -s http://ipv4.icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")
    echo "$ip"
}

press_any_key() {
    echo ""
    read -n 1 -s -r -p "按任意键继续..."
    echo ""
}

# ============================================
# 安装相关函数
# ============================================

install_deps() {
    echo -e "${BLUE}正在安装依赖...${NC}"
    apt-get update
    apt-get install -y python3 python3-pip python3-setuptools git curl wget \
        build-essential libsodium-dev openssl libssl-dev
    echo -e "${GREEN}依赖安装完成${NC}"
}

download_ssr() {
    echo -e "${BLUE}正在下载 ShadowsocksR...${NC}"
    
    if [ -d "$SSR_DIR" ]; then
        echo -e "${YELLOW}检测到已存在的SSR目录，正在备份...${NC}"
        mv "$SSR_DIR" "${SSR_DIR}.backup.$(date +%Y%m%d%H%M%S)"
    fi
    
    git clone -b akkariiin/master "$SSR_REPO" "$SSR_DIR" 2>/dev/null || \
        git clone -b master https://github.com/shadowsocksr-backup/shadowsocksr.git "$SSR_DIR"
    
    cd "$SSR_DIR" 2>/dev/null && git checkout akkariiin/master 2>/dev/null || true
    echo -e "${GREEN}ShadowsocksR 下载完成${NC}"
}

create_service() {
    echo -e "${BLUE}正在创建系统服务...${NC}"
    
    cat > "$SERVICE_FILE" << 'EOF'
[Unit]
Description=ShadowsocksR Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/usr/local/shadowsocksr
ExecStart=/usr/bin/python3 /usr/local/shadowsocksr/shadowsocks/server.py -c /etc/shadowsocksr.json
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable shadowsocksr
    echo -e "${GREEN}系统服务创建完成${NC}"
}

install_ssr() {
    echo -e "${GREEN}"
    echo "========================================"
    echo "      正在安装 ShadowsocksR"
    echo "========================================"
    echo -e "${NC}"
    
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}检测到已有SSR配置，是否重新安装？${NC}"
        read -p "继续安装? (y/N): " confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return
    fi
    
    install_deps
    download_ssr
    create_service
    
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}      安装完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "下一步：选择 ${YELLOW}[2] 配置SSR${NC} 进行配置"
}

# ============================================
# 配置相关函数
# ============================================

show_methods() {
    echo -e "${CYAN}可选加密方法：${NC}"
    echo "  1) none              2) aes-256-cfb        3) aes-128-cfb"
    echo "  4) chacha20          5) rc4-md5            6) salsa20"
    echo ""
}

show_protocols() {
    echo -e "${CYAN}可选协议：${NC}"
    echo "  1) origin            2) auth_sha1_v4"
    echo "  3) auth_aes128_md5   4) auth_aes128_sha1"
    echo "  5) auth_chain_a      6) auth_chain_b"
    echo ""
}

show_obfs() {
    echo -e "${CYAN}可选混淆：${NC}"
    echo "  1) plain             2) http_simple"
    echo "  3) http_post         4) tls1.2_ticket_auth"
    echo "  5) tls1.2_ticket_fastauth"
    echo ""
}

get_method() {
    show_methods
    read -p "请选择加密方法 [默认: 2]: " choice
    case $choice in
        1) echo "none" ;;
        2|"") echo "aes-256-cfb" ;;
        3) echo "aes-128-cfb" ;;
        4) echo "chacha20" ;;
        5) echo "rc4-md5" ;;
        6) echo "salsa20" ;;
        *) echo "aes-256-cfb" ;;
    esac
}

get_protocol() {
    show_protocols
    read -p "请选择协议 [默认: 3]: " choice
    case $choice in
        1) echo "origin" ;;
        2) echo "auth_sha1_v4" ;;
        3|"") echo "auth_aes128_md5" ;;
        4) echo "auth_aes128_sha1" ;;
        5) echo "auth_chain_a" ;;
        6) echo "auth_chain_b" ;;
        *) echo "auth_aes128_md5" ;;
    esac
}

get_obfs() {
    show_obfs
    read -p "请选择混淆 [默认: 4]: " choice
    case $choice in
        1) echo "plain" ;;
        2) echo "http_simple" ;;
        3) echo "http_post" ;;
        4|"") echo "tls1.2_ticket_auth" ;;
        5) echo "tls1.2_ticket_fastauth" ;;
        *) echo "tls1.2_ticket_auth" ;;
    esac
}

configure_firewall_port() {
    local port=$1
    echo -e "${BLUE}开放端口 $port...${NC}"
    
    if command -v ufw &> /dev/null; then
        ufw allow $port/tcp >/dev/null 2>&1 || true
        ufw allow $port/udp >/dev/null 2>&1 || true
    fi
    
    if command -v iptables &> /dev/null; then
        iptables -I INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null || true
        iptables -I INPUT -p udp --dport $port -j ACCEPT 2>/dev/null || true
    fi
    echo -e "${GREEN}端口 $port 已开放${NC}"
}

generate_config() {
    echo -e "${GREEN}"
    echo "========================================"
    echo "      SSR 配置向导"
    echo "========================================"
    echo -e "${NC}"
    
    # 备份旧配置
    [ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d%H%M%S)"
    
    # 端口
    local random_port=$(generate_port)
    read -p "请输入端口 [随机: $random_port]: " port
    port=${port:-$random_port}
    
    # 密码
    local default_pass=$(generate_password)
    read -p "请输入密码 [默认: $default_pass]: " password
    password=${password:-$default_pass}
    
    # 加密方法
    local method=$(get_method)
    echo ""
    
    # 协议
    local protocol=$(get_protocol)
    echo ""
    
    # 混淆
    local obfs=$(get_obfs)
    echo ""
    
    # 协议参数
    read -p "协议参数 (可选, 直接回车跳过): " protocol_param
    
    # 混淆参数
    local obfs_param=""
    if [[ "$obfs" == "tls1.2_ticket_auth"* ]] || [[ "$obfs" == "http_simple" ]]; then
        read -p "混淆参数 (伪装域名, 可选): " obfs_param
    fi
    
    # DNS
    read -p "DNS服务器 [默认: 1.1.1.1,8.8.8.8]: " dns
    dns=${dns:-"1.1.1.1,8.8.8.8"}
    
    # 创建配置文件
    cat > "$CONFIG_FILE" << EOF
{
    "server": "0.0.0.0",
    "server_ipv6": "::",
    "server_port": $port,
    "local_address": "127.0.0.1",
    "local_port": 1080,
    "password": "$password",
    "method": "$method",
    "protocol": "$protocol",
    "protocol_param": "${protocol_param:-}",
    "obfs": "$obfs",
    "obfs_param": "${obfs_param:-}",
    "speed_limit_per_con": 0,
    "speed_limit_per_user": 0,
    "additional_ports": {},
    "additional_ports_only": false,
    "timeout": 120,
    "udp_timeout": 60,
    "dns_ipv6": false,
    "connect_verbose_info": 1,
    "redirect": "",
    "fast_open": true,
    "workers": 1,
    "prefer_ipv6": false,
    "client_priorities": [],
    "dns_server": ["${dns//,/\",\"}"]
}
EOF

    configure_firewall_port $port
    echo -e "${GREEN}配置文件已生成${NC}"
}

generate_info() {
    local server_ip=$(get_server_ip)
    local server_port=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['server_port'])" 2>/dev/null || echo "未知")
    local password=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['password'])" 2>/dev/null || echo "未知")
    local method=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['method'])" 2>/dev/null || echo "未知")
    local protocol=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['protocol'])" 2>/dev/null || echo "未知")
    local obfs=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['obfs'])" 2>/dev/null || echo "未知")
    local obfs_param=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['obfs_param'])" 2>/dev/null || echo "")
    
    # 生成SSR链接
    local user_info=$(echo -n "$method:$password" | base64 | tr -d '\n' | tr '+/' '-_')
    local params=""
    [ -n "$obfs_param" ] && params="&obfsparam=$(echo -n "$obfs_param" | base64 | tr -d '\n' | tr '+/' '-_')"
    
    local ssr_link="ssr://$(echo -n "$server_ip:$server_port:$protocol:$method:$obfs:$user_info$params" | base64 | tr -d '\n' | tr '+/' '-_')"
    
    # 保存信息
    cat > "$INFO_FILE" << EOF
========== SSR 配置信息 ==========
服务器地址: $server_ip
服务器端口: $server_port
密码: $password
加密方式: $method
协议: $protocol
混淆: $obfs
混淆参数: $obfs_param

SSR链接: $ssr_link

配置文件路径: $CONFIG_FILE
生成时间: $(date)
==================================
EOF
    
    # 显示信息
    echo -e "\n${CYAN}========== 客户端配置信息 ==========${NC}"
    echo -e "${YELLOW}服务器地址:${NC} $server_ip"
    echo -e "${YELLOW}服务器端口:${NC} $server_port"
    echo -e "${YELLOW}密码:${NC} $password"
    echo -e "${YELLOW}加密方式:${NC} $method"
    echo -e "${YELLOW}协议:${NC} $protocol"
    echo -e "${YELLOW}混淆:${NC} $obfs"
    [ -n "$obfs_param" ] && echo -e "${YELLOW}混淆参数:${NC} $obfs_param"
    echo ""
    echo -e "${CYAN}========== SSR 分享链接 ==========${NC}"
    echo -e "${GREEN}$ssr_link${NC}"
    echo ""
    echo -e "${YELLOW}配置信息已保存到: $INFO_FILE${NC}"
}

config_ssr() {
    if [ ! -d "$SSR_DIR" ]; then
        echo -e "${RED}错误：SSR未安装，请先安装 (选项1)${NC}"
        return
    fi
    
    generate_config
    generate_info
    
    echo -e "\n${BLUE}是否立即启动服务？${NC}"
    read -p "启动服务? (Y/n): " start_now
    if [[ "$start_now" != "n" && "$start_now" != "N" ]]; then
        start_service
    fi
}

# ============================================
# 服务管理函数
# ============================================

start_service() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}错误：未找到配置文件，请先配置 (选项2)${NC}"
        return
    fi
    
    echo -e "${BLUE}正在启动 ShadowsocksR...${NC}"
    systemctl restart shadowsocksr
    sleep 2
    
    if systemctl is-active --quiet shadowsocksr; then
        echo -e "${GREEN}服务启动成功！${NC}"
    else
        echo -e "${RED}服务启动失败${NC}"
        echo -e "查看日志: ${YELLOW}journalctl -u shadowsocksr -n 20${NC}"
    fi
}

stop_service() {
    echo -e "${BLUE}正在停止 ShadowsocksR...${NC}"
    systemctl stop shadowsocksr
    echo -e "${GREEN}服务已停止${NC}"
}

restart_service() {
    echo -e "${BLUE}正在重启 ShadowsocksR...${NC}"
    systemctl restart shadowsocksr
    sleep 2
    
    if systemctl is-active --quiet shadowsocksr; then
        echo -e "${GREEN}服务重启成功！${NC}"
    else
        echo -e "${RED}服务重启失败${NC}"
    fi
}

view_status() {
    echo -e "${CYAN}========== 服务状态 ==========${NC}"
    systemctl status shadowsocksr --no-pager
    
    if systemctl is-active --quiet shadowsocksr; then
        echo -e "\n${GREEN}当前连接数：${NC}"
        ss -ant | grep -c "$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['server_port'])" 2>/dev/null)" || echo "0"
    fi
}

view_logs() {
    echo -e "${CYAN}========== 实时日志 (按 Ctrl+C 退出) ==========${NC}"
    journalctl -u shadowsocksr -f --no-hostname
}

view_config() {
    if [ -f "$INFO_FILE" ]; then
        cat "$INFO_FILE"
    elif [ -f "$CONFIG_FILE" ]; then
        generate_info
    else
        echo -e "${RED}未找到配置文件${NC}"
    fi
}

# ============================================
# 卸载函数
# ============================================

uninstall_ssr() {
    echo -e "${RED}"
    echo "========================================"
    echo "      警告：这将完全删除 ShadowsocksR"
    echo "========================================"
    echo -e "${NC}"
    
    read -p "确定要卸载吗? 请输入 'yes' 确认: " confirm
    if [ "$confirm" != "yes" ]; then
        echo -e "${YELLOW}已取消卸载${NC}"
        return
    fi
    
    echo -e "${BLUE}停止并禁用服务...${NC}"
    systemctl stop shadowsocksr 2>/dev/null || true
    systemctl disable shadowsocksr 2>/dev/null || true
    
    echo -e "${BLUE}删除文件...${NC}"
    rm -rf "$SSR_DIR"
    rm -f "$CONFIG_FILE"
    rm -f "$SERVICE_FILE"
    rm -f "$INFO_FILE"
    
    systemctl daemon-reload
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}      ShadowsocksR 已完全卸载${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# ============================================
# 主菜单
# ============================================

show_menu() {
    clear
    echo -e "${PURPLE}"
    echo "╔════════════════════════════════════════════════╗"
    echo "║                                                ║"
    echo "║        ShadowsocksR 管理脚本 v2.0              ║"
    echo "║                                                ║"
    echo "╚════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # 显示当前状态
    if [ -d "$SSR_DIR" ]; then
        if systemctl is-active --quiet shadowsocksr 2>/dev/null; then
            echo -e "${GREEN}● 服务状态: 运行中${NC}"
        else
            echo -e "${RED}● 服务状态: 已停止${NC}"
        fi
        
        if [ -f "$CONFIG_FILE" ]; then
            local port=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['server_port'])" 2>/dev/null || echo "-")
            echo -e "${CYAN}  端口: $port${NC}"
        fi
    else
        echo -e "${YELLOW}● 未安装${NC}"
    fi
    
    echo ""
    echo -e "  ${CYAN}[1]${NC} 安装 SSR"
    echo -e "  ${CYAN}[2]${NC} 配置 SSR"
    echo -e "  ${CYAN}[3]${NC} 启动服务"
    echo -e "  ${CYAN}[4]${NC} 停止服务"
    echo -e "  ${CYAN}[5]${NC} 重启服务"
    echo -e "  ${CYAN}[6]${NC} 查看状态"
    echo -e "  ${CYAN}[7]${NC} 查看日志"
    echo -e "  ${CYAN}[8]${NC} 查看配置信息"
    echo -e "  ${CYAN}[9]${NC} 卸载 SSR"
    echo -e "  ${CYAN}[0]${NC} 退出"
    echo ""
    echo -e "${PURPLE}════════════════════════════════════════════════${NC}"
}

main() {
    check_root
    
    while true; do
        show_menu
        read -p "请输入选项 [0-9]: " choice
        echo ""
        
        case $choice in
            1) install_ssr ;;
            2) config_ssr ;;
            3) start_service ;;
            4) stop_service ;;
            5) restart_service ;;
            6) view_status ;;
            7) view_logs ;;
            8) view_config ;;
            9) uninstall_ssr; press_any_key ;;
            0) echo -e "${GREEN}再见！${NC}"; exit 0 ;;
            *) echo -e "${RED}无效选项${NC}" ;;
        esac
        
        [ "$choice" != "7" ] && [ "$choice" != "0" ] && press_any_key
    done
}

# 运行主函数
main
