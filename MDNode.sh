#!/bin/bash
# Sing-box 服务端部署脚本 for Ubuntu/Debian
# 支持: VLESS+Reality, Hysteria2, Trojan, VMess+WS

export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# 颜色定义
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
blue='\033[0;34m'

# 配置路径
SING_BOX_DIR="/etc/sing-box"
CONFIG_FILE="${SING_BOX_DIR}/config.json"
BINARY_PATH="/usr/local/bin/sing-box"
SERVICE_FILE="/etc/systemd/system/sing-box.service"

# 检查root权限
check_root() {
    [[ $EUID != 0 ]] && echo -e "${red}错误：请使用 root 权限运行此脚本${plain}" && exit 1
}

# 检查系统架构
check_arch() {
    case "$(uname -m)" in
        x86_64|amd64) ARCH="amd64" ;;
        armv8|aarch64) ARCH="arm64" ;;
        armv7l) ARCH="armv7" ;;
        *) echo -e "${red}不支持的架构: $(uname -m)${plain}" && exit 1 ;;
    esac
    echo -e "${green}系统架构: ${ARCH}${plain}"
}

# 获取最新版本
get_latest_version() {
    echo -e "${yellow}正在检查最新版本...${plain}"
    VERSION=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ -z "$VERSION" ]]; then
        echo -e "${red}获取版本失败，使用默认版本 v1.8.0${plain}"
        VERSION="v1.8.0"
    else
        echo -e "${green}最新版本: ${VERSION}${plain}"
    fi
}

# 安装依赖
install_deps() {
    echo -e "${yellow}安装系统依赖...${plain}"
    apt-get update -y
    apt-get install -y curl wget tar gzip openssl jq uuid-runtime qrencode
}

# 下载并安装 sing-box
install_binary() {
    if [[ -f "$BINARY_PATH" ]]; then
        echo -e "${yellow}检测到已安装 sing-box${plain}"
        read -rp "是否重新安装/更新? [y/N]: " confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return
        systemctl stop sing-box 2>/dev/null
    fi

    get_latest_version
    local DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${VERSION}/sing-box-${VERSION}-linux-${ARCH}.tar.gz"
    
    echo -e "${yellow}正在下载 sing-box ${VERSION}...${plain}"
    cd /tmp || exit 1
    
    # 尝试下载
    if ! wget --timeout=30 -q -O sing-box.tar.gz "$DOWNLOAD_URL"; then
        echo -e "${yellow}GitHub 下载失败，尝试镜像...${plain}"
        DOWNLOAD_URL="https://ghproxy.com/${DOWNLOAD_URL}"
        wget --timeout=30 -q -O sing-box.tar.gz "$DOWNLOAD_URL" || {
            echo -e "${red}下载失败！请检查网络${plain}"
            exit 1
        }
    fi

    # 解压安装
    tar -xzf sing-box.tar.gz
    mv sing-box-${VERSION}-linux-${ARCH}/sing-box "$BINARY_PATH"
    chmod +x "$BINARY_PATH"
    rm -rf sing-box*

    # 创建配置目录
    mkdir -p "${SING_BOX_DIR}"
    
    echo -e "${green}sing-box 安装成功${plain}"
    sing-box version
}

# 生成 Reality 密钥对
generate_reality_keys() {
    echo -e "${yellow}生成 Reality 密钥对...${plain}"
    KEYS=$(sing-box generate reality-keypair)
    REALITY_PRIVATE_KEY=$(echo "$KEYS" | grep "PrivateKey" | awk '{print $2}')
    REALITY_PUBLIC_KEY=$(echo "$KEYS" | grep "PublicKey" | awk '{print $2}')
    REALITY_SHORT_ID=$(openssl rand -hex 4)
    echo -e "${green}Private Key: ${REALITY_PRIVATE_KEY}${plain}"
    echo -e "${green}Public Key: ${REALITY_PUBLIC_KEY}${plain}"
    echo -e "${green}Short ID: ${REALITY_SHORT_ID}${plain}"
}

# 生成 UUID
generate_uuid() {
    UUID=$(sing-box generate uuid)
    echo -e "${green}生成 UUID: ${UUID}${plain}"
}

# 配置 VLESS + Vision + Reality（推荐）
config_vless_reality() {
    echo -e "${blue}配置 VLESS + Vision + Reality${plain}"
    
    generate_uuid
    generate_reality_keys
    
    read -rp "请输入端口 [默认: 443]: " PORT
    PORT=${PORT:-443}
    
    read -rp "请输入伪装域名 (SNI) [默认: www.google.com]: " SNI
    SNI=${SNI:-www.google.com}
    
    local SERVER_IP=$(curl -s -4 ip.sb || curl -s -4 ifconfig.me)
    
    cat > "$CONFIG_FILE" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${PORT},
      "users": [
        {
          "uuid": "${UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${SNI}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${SNI}",
            "server_port": 443
          },
          "private_key": "${REALITY_PRIVATE_KEY}",
          "short_id": ["${REALITY_SHORT_ID}"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "rules": [
      {
        "geoip": "cn",
        "outbound": "block"
      }
    ]
  }
}
EOF

    echo -e "${green}配置完成！${plain}"
    echo -e "\n${yellow}=== 客户端配置信息 ===${plain}"
    echo -e "协议: VLESS"
    echo -e "地址: ${SERVER_IP}"
    echo -e "端口: ${PORT}"
    echo -e "UUID: ${UUID}"
    echo -e "流控: xtls-rprx-vision"
    echo -e "传输: TCP"
    echo -e "安全: REALITY"
    echo -e "SNI: ${SNI}"
    echo -e "Public Key: ${REALITY_PUBLIC_KEY}"
    echo -e "Short ID: ${REALITY_SHORT_ID}"
    
    # 生成分享链接
    VLESS_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?security=reality&sni=${SNI}&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&flow=xtls-rprx-vision&type=tcp&headerType=none#Reality-${SERVER_IP}"
    echo -e "\n${green}分享链接:${plain}\n${VLESS_LINK}"
    
    # 生成二维码
    echo -e "\n${green}二维码:${plain}"
    qrencode -t ANSIUTF8 "${VLESS_LINK}"
}

# 配置 Hysteria2（UDP 高速协议）
config_hysteria2() {
    echo -e "${blue}配置 Hysteria2${plain}"
    
    read -rp "请输入端口 [默认: 443]: " PORT
    PORT=${PORT:-443}
    
    read -rp "请输入密码 [默认随机生成]: " PASSWORD
    if [[ -z "$PASSWORD" ]]; then
        PASSWORD=$(openssl rand -base64 16)
    fi
    
    # 生成自签名证书（Hysteria2 也可以使用 ACME 证书）
    echo -e "${yellow}生成自签名证书...${plain}"
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout "${SING_BOX_DIR}/server.key" \
        -out "${SING_BOX_DIR}/server.crt" \
        -subj "/CN=bing.com" \
        -days 36500
    
    local SERVER_IP=$(curl -s -4 ip.sb || curl -s -4 ifconfig.me)
    
    cat > "$CONFIG_FILE" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": ${PORT},
      "users": [
        {
          "password": "${PASSWORD}"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "${SING_BOX_DIR}/server.crt",
        "key_path": "${SING_BOX_DIR}/server.key"
      },
      "up_mbps": 1000,
      "down_mbps": 1000
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

    echo -e "${green}配置完成！${plain}"
    echo -e "\n${yellow}=== 客户端配置信息 ===${plain}"
    echo -e "协议: Hysteria2"
    echo -e "地址: ${SERVER_IP}"
    echo -e "端口: ${PORT}"
    echo -e "密码: ${PASSWORD}"
    echo -e "跳过证书验证: True (自签名证书)"
    
    # Hysteria2 URI
    HY2_LINK="hysteria2://${PASSWORD}@${SERVER_IP}:${PORT}?insecure=1&sni=bing.com#Hysteria2-${SERVER_IP}"
    echo -e "\n${green}分享链接:${plain}\n${HY2_LINK}"
    qrencode -t ANSIUTF8 "${HY2_LINK}"
}

# 配置 Trojan
config_trojan() {
    echo -e "${blue}配置 Trojan${plain}"
    
    generate_uuid
    read -rp "请输入端口 [默认: 443]: " PORT
    PORT=${PORT:-443}
    
    read -rp "请输入密码 [默认: ${UUID}]: " PASSWORD
    PASSWORD=${PASSWORD:-$UUID}
    
    # 生成证书（也可以使用现有证书）
    echo -e "${yellow}生成自签名证书...${plain}"
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout "${SING_BOX_DIR}/trojan.key" \
        -out "${SING_BOX_DIR}/trojan.crt" \
        -subj "/CN=www.baidu.com" \
        -days 36500
    
    local SERVER_IP=$(curl -s -4 ip.sb || curl -s -4 ifconfig.me)
    
    cat > "$CONFIG_FILE" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "trojan",
      "tag": "trojan-in",
      "listen": "::",
      "listen_port": ${PORT},
      "users": [
        {
          "password": "${PASSWORD}"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "${SING_BOX_DIR}/trojan.crt",
        "key_path": "${SING_BOX_DIR}/trojan.key"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

    echo -e "${green}配置完成！${plain}"
    echo -e "\n${yellow}=== 客户端配置信息 ===${plain}"
    echo -e "协议: Trojan"
    echo -e "地址: ${SERVER_IP}"
    echo -e "端口: ${PORT}"
    echo -e "密码: ${PASSWORD}"
    echo -e "跳过证书验证: True"
    
    TROJAN_LINK="trojan://${PASSWORD}@${SERVER_IP}:${PORT}?security=tls&insecure=1&sni=www.baidu.com#Trojan-${SERVER_IP}"
    echo -e "\n${green}分享链接:${plain}\n${TROJAN_LINK}"
    qrencode -t ANSIUTF8 "${TROJAN_LINK}"
}

# 创建 systemd 服务
create_service() {
    echo -e "${yellow}创建系统服务...${plain}"
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
Type=simple
ExecStart=${BINARY_PATH} run -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable sing-box
    echo -e "${green}服务已创建并设置开机自启${plain}"
}

# 配置防火墙
configure_firewall() {
    local PORT=$1
    echo -e "${yellow}配置防火墙规则，开放端口 ${PORT}...${plain}"
    
    if command -v ufw &> /dev/null; then
        ufw allow "$PORT/tcp"
        ufw allow "$PORT/udp"
        echo -e "${green}UFW 规则已添加${plain}"
    fi
    
    if command -v iptables &> /dev/null; then
        iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT
        iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
        echo -e "${green}iptables 规则已添加${plain}"
    fi
}

# 启动服务
start_service() {
    echo -e "${yellow}启动 sing-box 服务...${plain}"
    systemctl restart sing-box
    sleep 2
    
    if systemctl is-active --quiet sing-box; then
        echo -e "${green}sing-box 启动成功！${plain}"
        systemctl status sing-box --no-pager
    else
        echo -e "${red}启动失败！查看日志:${plain}"
        journalctl -u sing-box --no-pager -n 50
    fi
}

# 停止服务
stop_service() {
    systemctl stop sing-box
    echo -e "${green}服务已停止${plain}"
}

# 查看状态
status_service() {
    systemctl status sing-box --no-pager
    echo -e "\n${yellow}最近日志:${plain}"
    journalctl -u sing-box --no-pager -n 20
}

# 查看日志
view_logs() {
    journalctl -u sing-box -f
}

# 卸载
uninstall() {
    read -rp "确定要卸载 sing-box 吗? [y/N]: " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return
    
    systemctl stop sing-box
    systemctl disable sing-box
    rm -f "$SERVICE_FILE"
    rm -f "$BINARY_PATH"
    rm -rf "$SING_BOX_DIR"
    systemctl daemon-reload
    
    echo -e "${green}sing-box 已完全卸载${plain}"
}

# 更新二进制
update_binary() {
    echo -e "${yellow}检查更新...${plain}"
    install_binary
    start_service
}

# 主菜单
show_menu() {
    clear
    echo -e "${blue}=================================${plain}"
    echo -e "${green}  Sing-box 服务端管理脚本${plain}"
    echo -e "${blue}=================================${plain}"
    echo -e "  ${green}1.${plain} 安装 sing-box"
    echo -e "  ${green}2.${plain} 配置 VLESS+Reality (推荐)"
    echo -e "  ${green}3.${plain} 配置 Hysteria2 (高速UDP)"
    echo -e "  ${green}4.${plain} 配置 Trojan"
    echo -e "  ${green}5.${plain} 启动服务"
    echo -e "  ${green}6.${plain} 停止服务"
    echo -e "  ${green}7.${plain} 查看状态/日志"
    echo -e "  ${green}8.${plain} 实时日志"
    echo -e "  ${green}9.${plain} 更新 sing-box"
    echo -e "  ${green}10.${plain} 卸载"
    echo -e "  ${green}0.${plain} 退出"
    echo -e "${blue}=================================${plain}"
    
    if systemctl is-active --quiet sing-box 2>/dev/null; then
        echo -e " 状态: ${green}运行中${plain}"
    else
        echo -e " 状态: ${red}未运行${plain}"
    fi
    echo ""
}

# 主程序
main() {
    check_root
    check_arch
    
    # 命令行模式
    if [ $# -gt 0 ]; then
        case "$1" in
            install) install_binary && create_service ;;
            vless) install_binary && create_service && config_vless_reality && start_service ;;
            hysteria2) install_binary && create_service && config_hysteria2 && start_service ;;
            trojan) install_binary && create_service && config_trojan && start_service ;;
            start) start_service ;;
            stop) stop_service ;;
            status) status_service ;;
            log) view_logs ;;
            update) update_binary ;;
            uninstall) uninstall ;;
            *) echo "用法: $0 {install|vless|hysteria2|trojan|start|stop|status|log|update|uninstall}" ;;
        esac
        exit 0
    fi
    
    # 交互式菜单
    while true; do
        show_menu
        read -rp "请输入选项 [0-10]: " num
        case "$num" in
            1) install_binary && create_service ;;
            2) config_vless_reality && start_service ;;
            3) config_hysteria2 && start_service ;;
            4) config_trojan && start_service ;;
            5) start_service ;;
            6) stop_service ;;
            7) status_service ;;
            8) view_logs ;;
            9) update_binary ;;
            10) uninstall ;;
            0) exit 0 ;;
            *) echo -e "${red}请输入正确选项${plain}" ;;
        esac
        echo ""
        read -rp "按回车键继续..." temp
    done
}

main "$@"
