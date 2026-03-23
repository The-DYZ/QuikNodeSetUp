#!/bin/bash
# ShadowsocksR 一键部署管理脚本 for Ubuntu/Debian
# 支持: 安装/配置/启动/停止/卸载/加密依赖自动检查

export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# 颜色定义
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
blue='\033[0;34m'

# 变量定义
ssr_dir="/usr/local/shadowsocksr"
config_file="${ssr_dir}/config.json"
service_file="/etc/systemd/system/shadowsocksr.service"
libsodium_version="1.0.18"
shadowsocksr_url="https://github.com/shadowsocksr-backup/shadowsocksr/archive/refs/heads/manyuser.zip"
backup_url="https://ghproxy.com/https://github.com/shadowsocksr-backup/shadowsocksr/archive/refs/heads/manyuser.zip"

# 检查root权限
check_root() {
    [[ $EUID != 0 ]] && echo -e "${red}错误：请使用 root 权限运行此脚本${plain}" && exit 1
}

# 检查系统
check_system() {
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif grep -qi "ubuntu" /etc/issue; then
        release="ubuntu"
    elif grep -qi "debian" /etc/issue; then
        release="debian"
    elif grep -qi "ubuntu" /proc/version; then
        release="ubuntu"
    elif grep -qi "debian" /proc/version; then
        release="debian"
    else
        echo -e "${red}不支持的系统类型！${plain}"
        exit 1
    fi
    
    # 检查版本
    if [[ "$release" == "ubuntu" ]]; then
        version=$(lsb_release -rs | cut -d. -f1)
    fi
}

# 检查依赖并安装
check_dependencies() {
    echo -e "${yellow}正在检查系统依赖...${plain}"
    apt-get update -y
    
    local deps=("curl" "wget" "git" "python3" "python3-pip" "python3-setuptools" "build-essential" "libssl-dev" "libffi-dev" "unzip" "lrzsz")
    
    for dep in "${deps[@]}"; do
        if ! dpkg -l | grep -q "^ii  $dep "; then
            echo -e "${yellow}安装 ${dep}...${plain}"
            apt-get install -y "$dep" || {
                echo -e "${red}安装 ${dep} 失败${plain}"
                return 1
            }
        fi
    done
    
    # 确保有 python 命令指向 python3
    if ! command -v python &> /dev/null && command -v python3 &> /dev/null; then
        ln -sf /usr/bin/python3 /usr/bin/python 2>/dev/null
    fi
    
    echo -e "${green}系统依赖检查完成${plain}"
}

# 安装 libsodium（支持 chacha20 等高级加密必需）
install_libsodium() {
    if ldconfig -p | grep -q "libsodium.so"; then
        echo -e "${green}libsodium 已安装${plain}"
        return 0
    fi
    
    echo -e "${yellow}正在安装 libsodium-${libsodium_version}...${plain}"
    cd /tmp || exit 1
    
    # 下载 libsodium
    local libsodium_url="https://download.libsodium.org/libsodium/releases/libsodium-${libsodium_version}.tar.gz"
    local github_mirror="https://github.com/jedisct1/libsodium/releases/download/${libsodium_version}-RELEASE/libsodium-${libsodium_version}.tar.gz"
    
    if ! wget --timeout=30 -q "$libsodium_url"; then
        echo -e "${yellow}官方源下载失败，尝试 GitHub...${plain}"
        if ! wget --timeout=30 -q "$github_mirror"; then
            echo -e "${red}libsodium 下载失败，将尝试使用软件源安装${plain}"
            apt-get install -y libsodium-dev && ldconfig && return 0
        fi
    fi
    
    tar xf "libsodium-${libsodium_version}.tar.gz"
    cd "libsodium-${libsodium_version}" || exit 1
    
    ./configure --prefix=/usr && make -j$(nproc) && make install
    
    if [ $? -eq 0 ]; then
        ldconfig
        echo -e "${green}libsodium 安装成功${plain}"
    else
        echo -e "${red}libsodium 编译安装失败${plain}"
        return 1
    fi
    
    cd / && rm -rf "/tmp/libsodium-${libsodium_version}"*
}

# 下载并安装 SSR
install_ssr() {
    if [ -d "$ssr_dir/shadowsocks" ]; then
        echo -e "${yellow}检测到 SSR 已安装在 ${ssr_dir}${plain}"
        read -rp "是否覆盖安装? [y/N]: " confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return
        uninstall_ssr false
    fi
    
    echo -e "${green}开始安装 ShadowsocksR...${plain}"
    
    # 安装依赖
    check_dependencies || exit 1
    install_libsodium || echo -e "${yellow}警告: libsodium 安装失败，部分加密方式可能无法使用${plain}"
    
    # 创建目录
    mkdir -p "$ssr_dir"
    cd /tmp || exit 1
    
    echo -e "${yellow}正在下载 ShadowsocksR...${plain}"
    
    # 尝试多个下载源
    local success=false
    for url in "$shadowsocksr_url" "$backup_url"; do
        if wget --timeout=30 -q -O shadowsocksr.zip "$url"; then
            success=true
            echo -e "${green}下载成功${plain}"
            break
        fi
        echo -e "${yellow}下载失败，尝试备用源...${plain}"
    done
    
    if [ "$success" = false ]; then
        echo -e "${red}下载失败！请检查网络连接或手动下载${plain}"
        echo -e "${yellow}手动下载地址: ${shadowsocksr_url}${plain}"
        exit 1
    fi
    
    # 解压安装
    unzip -q -o shadowsocksr.zip
    if [ -d "shadowsocksr-manyuser" ]; then
        mv shadowsocksr-manyuser/shadowsocks/* "$ssr_dir/"
    elif [ -d "shadowsocksr-manyuser-shadowsocksr-manyuser" ]; then
        mv shadowsocksr-manyuser-shadowsocksr-manyuser/shadowsocks/* "$ssr_dir/"
    else
        # 查找解压后的目录
        local ssr_folder=$(find . -maxdepth 1 -type d -name "*shadowsocksr*" | head -1)
        if [ -n "$ssr_folder" ] && [ -d "${ssr_folder}/shadowsocks" ]; then
            mv "${ssr_folder}/shadowsocks/"* "$ssr_dir/"
        else
            echo -e "${red}解压失败，目录结构异常${plain}"
            exit 1
        fi
    fi
    
    # 清理
    rm -rf /tmp/shadowsocksr* /tmp/ShadowsocksR*
    
    # 检查安装
    if [ ! -f "$ssr_dir/server.py" ]; then
        echo -e "${red}安装失败，主程序不存在${plain}"
        exit 1
    fi
    
    # 创建 systemd 服务
    cat > "$service_file" << EOF
[Unit]
Description=ShadowsocksR Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=${ssr_dir}
ExecStart=/usr/bin/python ${ssr_dir}/server.py -c ${config_file}
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    echo -e "${green}ShadowsocksR 安装完成${plain}"
    
    # 立即配置
    read -rp "是否立即配置 SSR? [Y/n]: " config_now
    [[ "$config_now" != "n" && "$config_now" != "N" ]] && configure_ssr
}

# 配置 SSR
configure_ssr() {
    if [ ! -f "$ssr_dir/server.py" ]; then
        echo -e "${red}错误: SSR 未安装，请先执行安装${plain}"
        return 1
    fi
    
    echo -e "${blue}=================================${plain}"
    echo -e "${green}   ShadowsocksR 配置向导${plain}"
    echo -e "${blue}=================================${plain}"
    
    # 端口设置
    local default_port=$(shuf -i 10000-60000 -n 1)
    read -rp "请输入 SSR 端口 [默认: ${default_port}]: " port
    port=${port:-$default_port}
    
    # 检查端口是否被占用
    while netstat -tuln | grep -q ":$port "; do
        echo -e "${red}端口 $port 已被占用${plain}"
        read -rp "请输入其他端口: " port
    done
    
    # 密码设置
    local default_pass=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
    read -rp "请输入密码 [默认: ${default_pass}]: " password
    password=${password:-$default_pass}
    
    # 加密方式选择
    echo -e "\n${yellow}请选择加密方式:${plain}"
    local methods=(
        "none"
        "rc4-md5"
        "aes-128-ctr"
        "aes-192-ctr"
        "aes-256-ctr"
        "aes-128-cfb"
        "aes-192-cfb"
        "aes-256-cfb"
        "chacha20"
        "chacha20-ietf"
    )
    
    # 检查 libsodium 以支持 chacha20
    if ! ldconfig -p | grep -q libsodium; then
        echo -e "${red}警告: 未检测到 libsodium，chacha20 加密方式可能无法使用${plain}"
    fi
    
    select method in "${methods[@]}"; do
        if [[ -n "$method" ]]; then
            # 检查 chacha20 依赖
            if [[ "$method" == chacha20* ]] && ! ldconfig -p | grep -q libsodium; then
                echo -e "${red}错误: 使用 ${method} 需要先安装 libsodium${plain}"
                echo -e "${yellow}请运行脚本并选择重装以安装依赖${plain}"
                continue
            fi
            break
        fi
        echo -e "${red}无效选择${plain}"
    done
    
    # 协议选择
    echo -e "\n${yellow}请选择协议:${plain}"
    local protocols=("origin" "verify_simple" "verify_deflate" "verify_sha1" "auth_simple" "auth_sha1" "auth_sha1_v2" "auth_sha1_v4" "auth_aes128_md5" "auth_aes128_sha1" "auth_chain_a" "auth_chain_b")
    select protocol in "${protocols[@]}"; do
        [[ -n "$protocol" ]] && break
        echo -e "${red}无效选择${plain}"
    done
    
    # 混淆选择
    echo -e "\n${yellow}请选择混淆方式:${plain}"
    local obfses=("plain" "http_simple" "http_post" "random_head" "tls1.0_session_auth" "tls1.2_ticket_auth" "tls1.2_ticket_fastauth")
    select obfs in "${obfses[@]}"; do
        [[ -n "$obfs" ]] && break
        echo -e "${red}无效选择${plain}"
    done
    
    # 混淆参数
    read -rp "请输入混淆参数(默认空): " obfs_param
    
    # 生成配置文件
    cat > "$config_file" << EOF
{
    "server": "0.0.0.0",
    "server_ipv6": "::",
    "server_port": ${port},
    "local_address": "127.0.0.1",
    "local_port": 1080,
    "password": "${password}",
    "timeout": 120,
    "udp_timeout": 60,
    "method": "${method}",
    "protocol": "${protocol}",
    "protocol_param": "",
    "obfs": "${obfs}",
    "obfs_param": "${obfs_param}",
    "speed_limit_per_con": 0,
    "speed_limit_per_user": 0,
    "dns_ipv6": false,
    "connect_verbose_info": 0,
    "redirect": "",
    "fast_open": false
}
EOF
    
    # 设置防火墙
    configure_firewall "$port"
    
    echo -e "${green}配置完成！${plain}"
    show_config
    
    # 启动服务
    read -rp "是否立即启动/重启服务? [Y/n]: " start_now
    if [[ "$start_now" != "n" && "$start_now" != "N" ]]; then
        restart_ssr
    fi
}

# 防火墙配置
configure_firewall() {
    local port=$1
    echo -e "${yellow}配置防火墙规则...${plain}"
    
    if command -v ufw &> /dev/null; then
        ufw allow "$port/tcp" 2>/dev/null
        ufw allow "$port/udp" 2>/dev/null
        echo -e "${green}UFW 规则已添加${plain}"
    fi
    
    if command -v iptables &> /dev/null; then
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
        iptables -I INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null
        # 尝试保存规则
        iptables-save > /etc/iptables.rules 2>/dev/null || true
        echo -e "${green}iptables 规则已添加${plain}"
    fi
}

# 显示配置信息
show_config() {
    if [ ! -f "$config_file" ]; then
        echo -e "${red}配置文件不存在${plain}"
        return 1
    fi
    
    local port=$(python3 -c "import json; print(json.load(open('${config_file}'))['server_port'])")
    local password=$(python3 -c "import json; print(json.load(open('${config_file}'))['password'])")
    local method=$(python3 -c "import json; print(json.load(open('${config_file}'))['method'])")
    local protocol=$(python3 -c "import json; print(json.load(open('${config_file}'))['protocol'])")
    local obfs=$(python3 -c "import json; print(json.load(open('${config_file}'))['obfs'])")
    local ip=$(curl -s -4 ip.sb || curl -s -4 ifconfig.me || echo "你的服务器IP")
    
    echo -e "\n${green}========== SSR 配置信息 ==========${plain}"
    echo -e " 服务器地址: ${ip}"
    echo -e " 端口: ${port}"
    echo -e " 密码: ${password}"
    echo -e " 加密方式: ${method}"
    echo -e " 协议: ${protocol}"
    echo -e " 混淆: ${obfs}"
    echo -e "${green}==================================${plain}"
    
    # 生成 SSR 链接
    local base64_pass=$(echo -n "${password}" | base64 -w0 | sed 's/=//g')
    local base64_obfs_param=$(echo -n "" | base64 -w0 | sed 's/=//g')
    local base64_remarks=$(echo -n "SSR-${ip}" | base64 -w0 | sed 's/=//g')
    local base64_group=$(echo -n "Github" | base64 -w0 | sed 's/=//g')
    
    local ssr_str="${ip}:${port}:${protocol}:${method}:${obfs}:${base64_pass}/?obfsparam=${base64_obfs_param}&remarks=${base64_remarks}&group=${base64_group}"
    local ssr_url="ssr://$(echo -n "$ssr_str" | base64 -w0)"
    
    echo -e "\n${yellow}SSR链接:${plain}\n${ssr_url}\n"
}

# 服务管理
start_ssr() {
    systemctl start shadowsocksr && echo -e "${green}SSR 启动成功${plain}" || echo -e "${red}SSR 启动失败，请检查日志: journalctl -u shadowsocksr${plain}"
}

stop_ssr() {
    systemctl stop shadowsocksr && echo -e "${green}SSR 停止成功${plain}" || echo -e "${red}SSR 停止失败${plain}"
}

restart_ssr() {
    systemctl restart shadowsocksr && echo -e "${green}SSR 重启成功${plain}" || echo -e "${red}SSR 重启失败${plain}"
}

status_ssr() {
    systemctl status shadowsocksr --no-pager
    if systemctl is-active --quiet shadowsocksr; then
        echo -e "\n${green}连接信息:${plain}"
        show_config
    fi
}

view_log() {
    journalctl -u shadowsocksr -n 50 --no-pager
}

# 卸载
uninstall_ssr() {
    local ask=${1:-true}
    
    if $ask; then
        read -rp "确定要卸载 ShadowsocksR 吗?(此操作不可恢复) [y/N]: " confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return
    fi
    
    echo -e "${yellow}正在卸载 ShadowsocksR...${plain}"
    
    # 停止并禁用服务
    systemctl stop shadowsocksr 2>/dev/null
    systemctl disable shadowsocksr 2>/dev/null
    
    # 删除文件
    rm -f "$service_file"
    rm -rf "$ssr_dir"
    
    systemctl daemon-reload
    
    echo -e "${green}ShadowsocksR 已完全卸载${plain}"
}

# 更新脚本
update_script() {
    echo -e "${yellow}脚本更新功能待实现，请手动下载最新版本${plain}"
}

# 主菜单
show_menu() {
    clear
    echo -e "${blue}=================================${plain}"
    echo -e "${green}  ShadowsocksR 管理脚本 v1.0${plain}"
    echo -e "${blue}=================================${plain}"
    echo -e "  ${green}1.${plain} 安装 ShadowsocksR"
    echo -e "  ${green}2.${plain} 配置 ShadowsocksR"
    echo -e "  ${green}3.${plain} 启动服务"
    echo -e "  ${green}4.${plain} 停止服务"
    echo -e "  ${green}5.${plain} 重启服务"
    echo -e "  ${green}6.${plain} 查看状态"
    echo -e "  ${green}7.${plain} 查看配置/二维码"
    echo -e "  ${green}8.${plain} 查看日志"
    echo -e "  ${green}9.${plain} 卸载 ShadowsocksR"
    echo -e "  ${green}0.${plain} 退出脚本"
    echo -e "${blue}=================================${plain}"
    
    # 显示运行状态
    if systemctl is-active --quiet shadowsocksr 2>/dev/null; then
        echo -e " 当前状态: ${green}运行中${plain}"
    else
        echo -e " 当前状态: ${red}未运行${plain}"
    fi
    echo ""
}

# 主程序
main() {
    check_root
    check_system
    
    if [[ "$release" != "ubuntu" && "$release" != "debian" ]]; then
        echo -e "${red}本脚本仅支持 Ubuntu/Debian 系统${plain}"
        exit 1
    fi
    
    # 命令行模式
    if [ $# -gt 0 ]; then
        case "$1" in
            install) install_ssr ;;
            config) configure_ssr ;;
            start) start_ssr ;;
            stop) stop_ssr ;;
            restart) restart_ssr ;;
            status) status_ssr ;;
            log) view_log ;;
            show) show_config ;;
            uninstall) uninstall_ssr ;;
            *) echo "用法: $0 {install|config|start|stop|restart|status|log|show|uninstall}" ;;
        esac
        exit 0
    fi
    
    # 交互式菜单
    while true; do
        show_menu
        read -rp "请输入数字 [0-9]: " num
        case "$num" in
            1) install_ssr ;;
            2) configure_ssr ;;
            3) start_ssr ;;
            4) stop_ssr ;;
            5) restart_ssr ;;
            6) status_ssr ;;
            7) show_config ;;
            8) view_log ;;
            9) uninstall_ssr ;;
            0) exit 0 ;;
            *) echo -e "${red}请输入正确的数字 [0-9]${plain}" && sleep 1 ;;
        esac
        echo ""
        read -rp "按回车键继续..." temp
    done
}

main "$@"
