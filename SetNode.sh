#!/bin/bash

# ============================================
# ShadowsocksR 完整管理脚本 for Ubuntu/Debian
# 功能：安装 | 单/多用户配置 | 管理 | 查询 | 卸载
# ============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
ORANGE='\033[0;33m'
NC='\033[0m'

# 配置变量
SSR_DIR="/usr/local/shadowsocksr"
SSR_REPO="https://github.com/shadowsocksrr/shadowsocksr.git"
SERVICE_FILE="/etc/systemd/system/shadowsocksr.service"
CONFIG_FILE="/etc/shadowsocksr.json"
USERS_FILE="/etc/shadowsocksr.users.json"
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

check_ssr_installed() {
    if [ ! -d "$SSR_DIR" ]; then
        echo -e "${RED}错误：SSR未安装，请先安装 (选项1)${NC}"
        return 1
    fi
    return 0
}

# ============================================
# 安装相关函数
# ============================================

install_deps() {
    echo -e "${BLUE}正在安装依赖...${NC}"
    apt-get update
    apt-get install -y python3 python3-pip python3-setuptools git curl wget \
        build-essential libsodium-dev openssl libssl-dev net-tools
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
    
    # 初始化用户配置文件
    echo '{"mode": "single", "users": []}' > "$USERS_FILE"
    
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}      安装完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "下一步：选择 ${YELLOW}[2] 配置管理${NC} 进行配置"
}

# ============================================
# 配置生成函数
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
    if command -v ufw &> /dev/null; then
        ufw allow $port/tcp >/dev/null 2>&1 || true
        ufw allow $port/udp >/dev/null 2>&1 || true
    fi
    if command -v iptables &> /dev/null; then
        iptables -I INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null || true
        iptables -I INPUT -p udp --dport $port -j ACCEPT 2>/dev/null || true
    fi
}

remove_firewall_port() {
    local port=$1
    if command -v ufw &> /dev/null; then
        ufw delete allow $port/tcp >/dev/null 2>&1 || true
        ufw delete allow $port/udp >/dev/null 2>&1 || true
    fi
}

# ============================================
# 用户管理函数
# ============================================

init_users_file() {
    if [ ! -f "$USERS_FILE" ]; then
        echo '{"mode": "single", "users": []}' > "$USERS_FILE"
    fi
}

get_next_user_id() {
    local max_id=$(python3 -c "import json; data=json.load(open('$USERS_FILE')); print(max([u.get('id',0) for u in data['users']] + [0]))")
    echo $((max_id + 1))
}

generate_ssr_config() {
    local mode=$(python3 -c "import json; print(json.load(open('$USERS_FILE')).get('mode', 'single'))")
    local dns="1.1.1.1,8.8.8.8"
    
    if [ "$mode" == "single" ]; then
        # 单用户模式，使用第一个用户或默认配置
        local user=$(python3 -c "import json; users=json.load(open('$USERS_FILE'))['users']; print(json.dumps(users[0]) if users else '{}')")
        if [ "$user" == "{}" ]; then
            echo -e "${RED}错误：没有配置用户${NC}"
            return 1
        fi
        
        local port=$(echo "$user" | python3 -c "import sys,json; print(json.load(sys.stdin)['port'])")
        local password=$(echo "$user" | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")
        local method=$(echo "$user" | python3 -c "import sys,json; print(json.load(sys.stdin)['method'])")
        local protocol=$(echo "$user" | python3 -c "import sys,json; print(json.load(sys.stdin)['protocol'])")
        local obfs=$(echo "$user" | python3 -c "import sys,json; print(json.load(sys.stdin)['obfs'])")
        local protocol_param=$(echo "$user" | python3 -c "import sys,json; print(json.load(sys.stdin).get('protocol_param',''))")
        local obfs_param=$(echo "$user" | python3 -c "import sys,json; print(json.load(sys.stdin).get('obfs_param',''))")
        
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
    "protocol_param": "$protocol_param",
    "obfs": "$obfs",
    "obfs_param": "$obfs_param",
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
    "dns_server": ["${dns//,/\",\"}"]
}
EOF
    else
        # 多用户模式，使用additional_ports
        local main_user=$(python3 -c "import json; users=json.load(open('$USERS_FILE'))['users']; print(json.dumps(users[0]) if users else '{}')")
        local main_port=$(echo "$main_user" | python3 -c "import sys,json; print(json.load(sys.stdin)['port'])")
        local main_password=$(echo "$main_user" | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")
        local main_method=$(echo "$main_user" | python3 -c "import sys,json; print(json.load(sys.stdin)['method'])")
        local main_protocol=$(echo "$main_user" | python3 -c "import sys,json; print(json.load(sys.stdin)['protocol'])")
        local main_obfs=$(echo "$main_user" | python3 -c "import sys,json; print(json.load(sys.stdin)['obfs'])")
        
        # 生成additional_ports
        local additional_ports=$(python3 << PYEOF
import json
with open('$USERS_FILE') as f:
    data = json.load(f)
users = data.get('users', [])
ports = {}
for user in users[1:]:  # 跳过第一个，作为主端口
    if user.get('enable', True):
        ports[str(user['port'])] = {
            "password": user['password'],
            "method": user['method'],
            "protocol": user['protocol'],
            "protocol_param": user.get('protocol_param', ''),
            "obfs": user['obfs'],
            "obfs_param": user.get('obfs_param', '')
        }
print(json.dumps(ports, indent=4))
PYEOF
)
        
        cat > "$CONFIG_FILE" << EOF
{
    "server": "0.0.0.0",
    "server_ipv6": "::",
    "server_port": $main_port,
    "local_address": "127.0.0.1",
    "local_port": 1080,
    "password": "$main_password",
    "method": "$main_method",
    "protocol": "$main_protocol",
    "protocol_param": "",
    "obfs": "$main_obfs",
    "obfs_param": "",
    "speed_limit_per_con": 0,
    "speed_limit_per_user": 0,
    "additional_ports": $additional_ports,
    "additional_ports_only": false,
    "timeout": 120,
    "udp_timeout": 60,
    "dns_ipv6": false,
    "connect_verbose_info": 1,
    "redirect": "",
    "fast_open": true,
    "workers": 1,
    "prefer_ipv6": false,
    "dns_server": ["${dns//,/\",\"}"]
}
EOF
    fi
    
    # 开放所有用户端口
    python3 -c "import json; users=json.load(open('$USERS_FILE'))['users']" 2>/dev/null | while read user; do
        local port=$(echo "$user" | python3 -c "import sys,json; print(json.load(sys.stdin)['port'])" 2>/dev/null || continue)
        configure_firewall_port "$port"
    done
    
    return 0
}

add_user() {
    echo -e "${GREEN}========== 添加新用户 ==========${NC}"
    
    local id=$(get_next_user_id)
    read -p "用户名: " name
    [ -z "$name" ] && name="user$id"
    
    # 检查用户名是否已存在
    local exists=$(python3 -c "import json; users=json.load(open('$USERS_FILE'))['users']; print('1' if any(u['name']=='$name' for u in users) else '0')")
    if [ "$exists" == "1" ]; then
        echo -e "${RED}错误：用户名已存在${NC}"
        return 1
    fi
    
    read -p "端口 [随机]: " port
    port=${port:-$(generate_port)}
    
    # 检查端口是否被占用
    local port_used=$(python3 -c "import json; users=json.load(open('$USERS_FILE'))['users']; print('1' if any(u['port']==$port for u in users) else '0')")
    if [ "$port_used" == "1" ]; then
        echo -e "${RED}错误：端口已被使用${NC}"
        return 1
    fi
    
    local password=$(generate_password)
    read -p "密码 [默认: $password]: " input_pass
    password=${input_pass:-$password}
    
    echo -e "${CYAN}请选择加密方式：${NC}"
    local method=$(get_method)
    echo -e "${CYAN}请选择协议：${NC}"
    local protocol=$(get_protocol)
    echo -e "${CYAN}请选择混淆：${NC}"
    local obfs=$(get_obfs)
    
    read -p "协议参数 (可选): " protocol_param
    read -p "混淆参数 (可选): " obfs_param
    
    # 添加到用户文件
    python3 << PYEOF
import json
with open('$USERS_FILE', 'r') as f:
    data = json.load(f)

new_user = {
    "id": $id,
    "name": "$name",
    "port": $port,
    "password": "$password",
    "method": "$method",
    "protocol": "$protocol",
    "protocol_param": "$protocol_param",
    "obfs": "$obfs",
    "obfs_param": "$obfs_param",
    "enable": True,
    "created": "$(date +%Y-%m-%d)"
}

data['users'].append(new_user)
with open('$USERS_FILE', 'w') as f:
    json.dump(data, f, indent=2)
PYEOF

    configure_firewall_port "$port"
    echo -e "${GREEN}用户 $name 添加成功！端口: $port${NC}"
    
    # 显示配置信息
    show_user_info "$id"
}

delete_user() {
    echo -e "${RED}========== 删除用户 ==========${NC}"
    list_users
    
    read -p "请输入要删除的用户ID: " id
    [ -z "$id" ] && return
    
    local user=$(python3 -c "import json; users=json.load(open('$USERS_FILE'))['users']; u=next((x for x in users if x['id']==$id), None); print(json.dumps(u) if u else '{}')")
    if [ "$user" == "{}" ]; then
        echo -e "${RED}用户不存在${NC}"
        return 1
    fi
    
    local name=$(echo "$user" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")
    local port=$(echo "$user" | python3 -c "import sys,json; print(json.load(sys.stdin)['port'])")
    
    read -p "确定删除用户 $name? (yes/no): " confirm
    if [ "$confirm" == "yes" ]; then
        python3 << PYEOF
import json
with open('$USERS_FILE', 'r') as f:
    data = json.load(f)
data['users'] = [u for u in data['users'] if u['id'] != $id]
with open('$USERS_FILE', 'w') as f:
    json.dump(data, f, indent=2)
PYEOF
        remove_firewall_port "$port"
        echo -e "${GREEN}用户已删除${NC}"
    else
        echo -e "${YELLOW}已取消${NC}"
    fi
}

modify_user() {
    echo -e "${YELLOW}========== 修改用户 ==========${NC}"
    list_users
    
    read -p "请输入要修改的用户ID: " id
    [ -z "$id" ] && return
    
    local user=$(python3 -c "import json; users=json.load(open('$USERS_FILE'))['users']; u=next((x for x in users if x['id']==$id), None); print(json.dumps(u) if u else '{}')")
    if [ "$user" == "{}" ]; then
        echo -e "${RED}用户不存在${NC}"
        return 1
    fi
    
    local name=$(echo "$user" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")
    local old_port=$(echo "$user" | python3 -c "import sys,json; print(json.load(sys.stdin)['port'])")
    
    echo -e "正在修改用户: ${CYAN}$name${NC}"
    echo -e "${YELLOW}直接回车保持原值不变${NC}"
    
    read -p "新用户名: " new_name
    read -p "新端口: " new_port
    read -p "新密码: " new_pass
    
    local new_method=""
    local new_protocol=""
    local new_obfs=""
    
    read -p "是否修改加密/协议/混淆? (y/N): " change_crypto
    if [[ "$change_crypto" == "y" || "$change_crypto" == "Y" ]]; then
        echo -e "${CYAN}请选择新的加密方式：${NC}"
        new_method=$(get_method)
        echo -e "${CYAN}请选择新的协议：${NC}"
        new_protocol=$(get_protocol)
        echo -e "${CYAN}请选择新的混淆：${NC}"
        new_obfs=$(get_obfs)
    fi
    
    python3 << PYEOF
import json
with open('$USERS_FILE', 'r') as f:
    data = json.load(f)

for u in data['users']:
    if u['id'] == $id:
        if "${new_name:-}": u['name'] = "$new_name"
        if "$new_port": 
            u['port'] = int($new_port)
        if "${new_pass:-}": u['password'] = "$new_pass"
        if "${new_method:-}": u['method'] = "$new_method"
        if "${new_protocol:-}": u['protocol'] = "$new_protocol"
        if "${new_obfs:-}": u['obfs'] = "$new_obfs"
        break

with open('$USERS_FILE', 'w') as f:
    json.dump(data, f, indent=2)
PYEOF

    if [ -n "$new_port" ] && [ "$new_port" != "$old_port" ]; then
        remove_firewall_port "$old_port"
        configure_firewall_port "$new_port"
    fi
    
    echo -e "${GREEN}用户修改成功${NC}"
}

toggle_user() {
    list_users
    
    read -p "请输入要启用/禁用的用户ID: " id
    [ -z "$id" ] && return
    
    python3 << PYEOF
import json
with open('$USERS_FILE', 'r') as f:
    data = json.load(f)

for u in data['users']:
    if u['id'] == $id:
        u['enable'] = not u.get('enable', True)
        status = "启用" if u['enable'] else "禁用"
        print(f"用户 {u['name']} 已{status}")
        break

with open('$USERS_FILE', 'w') as f:
    json.dump(data, f, indent=2)
PYEOF
}

list_users() {
    echo -e "${CYAN}========== 用户列表 ==========${NC}"
    printf "%-4s %-12s %-6s %-16s %-8s %-20s\n" "ID" "用户名" "端口" "密码" "状态" "创建时间"
    echo "--------------------------------------------------------------------------------"
    
    python3 << PYEOF
import json
try:
    with open('$USERS_FILE', 'r') as f:
        data = json.load(f)
    users = data.get('users', [])
    if not users:
        print("暂无用户")
    for u in users:
        status = "启用" if u.get('enable', True) else "禁用"
        print(f"{u['id']:<4} {u['name']:<12} {u['port']:<6} {u['password']:<16} {status:<8} {u.get('created', 'N/A')}")
except Exception as e:
    print(f"读取失败: {e}")
PYEOF
    echo ""
}

show_user_info() {
    local target_id=$1
    local server_ip=$(get_server_ip)
    
    python3 << PYEOF
import json
import base64

with open('$USERS_FILE', 'r') as f:
    data = json.load(f)

users = data.get('users', [])
if $target_id > 0:
    users = [u for u in users if u['id'] == $target_id]

for u in users:
    print(f"\n{'='*50}")
    print(f"用户: {u['name']} (ID: {u['id']})")
    print(f"{'='*50}")
    print(f"服务器: $server_ip")
    print(f"端口: {u['port']}")
    print(f"密码: {u['password']}")
    print(f"加密: {u['method']}")
    print(f"协议: {u['protocol']}")
    print(f"混淆: {u['obfs']}")
    if u.get('protocol_param'):
        print(f"协议参数: {u['protocol_param']}")
    if u.get('obfs_param'):
        print(f"混淆参数: {u['obfs_param']}")
    
    # 生成SSR链接
    user_info = base64.b64encode(f"{u['method']}:{u['password']}".encode()).decode().replace('+', '-').replace('/', '_').rstrip('=')
    params = ""
    if u.get('obfs_param'):
        obfsparam = base64.b64encode(u['obfs_param'].encode()).decode().replace('+', '-').replace('/', '_').rstrip('=')
        params = f"&obfsparam={obfsparam}"
    
    ssr_link = f"ssr://{base64.b64encode(f'$server_ip:{u[\'port\']}:{u[\'protocol\']}:{u[\'method\']}:{u[\'obfs\']}:{user_info}{params}'.encode()).decode().replace('+', '-').replace('/', '_').rstrip('=')}"
    print(f"\nSSR链接: {ssr_link}")
    print(f"{'='*50}")
PYEOF
}

switch_mode() {
    local current_mode=$(python3 -c "import json; print(json.load(open('$USERS_FILE')).get('mode', 'single'))")
    echo -e "当前模式: ${CYAN}$current_mode${NC}"
    echo "1) 单用户模式 (所有流量走主端口)"
    echo "2) 多用户模式 (每个用户独立端口)"
    read -p "请选择 [1-2]: " mode_choice
    
    local new_mode="single"
    [ "$mode_choice" == "2" ] && new_mode="multi"
    
    python3 << PYEOF
import json
with open('$USERS_FILE', 'r') as f:
    data = json.load(f)
data['mode'] = '$new_mode'
with open('$USERS_FILE', 'w') as f:
    json.dump(data, f, indent=2)
PYEOF

    echo -e "${GREEN}已切换到 $new_mode 模式${NC}"
    [ "$new_mode" == "multi" ] && echo -e "${YELLOW}提示：多用户模式下每个用户需配置不同端口${NC}"
}

multi_user_menu() {
    while true; do
        echo -e "\n${PURPLE}========== 多用户管理 ==========${NC}"
        echo "1) 添加用户"
        echo "2) 删除用户"
        echo "3) 修改用户"
        echo "4) 启用/禁用用户"
        echo "5) 查看所有用户"
        echo "6) 切换单/多用户模式"
        echo "7) 生成配置文件"
        echo "0) 返回上级"
        read -p "请选择: " choice
        
        case $choice in
            1) add_user ;;
            2) delete_user ;;
            3) modify_user ;;
            4) toggle_user ;;
            5) list_users ;;
            6) switch_mode ;;
            7) 
                generate_ssr_config
                echo -e "${GREEN}配置已生成，建议重启服务生效${NC}"
                ;;
            0) break ;;
            *) echo -e "${RED}无效选项${NC}" ;;
        esac
        press_any_key
    done
}

# ============================================
# 查询功能
# ============================================

query_by_port() {
    read -p "请输入要查询的端口: " port
    [ -z "$port" ] && return
    
    python3 << PYEOF
import json
with open('$USERS_FILE', 'r') as f:
    data = json.load(f)

users = [u for u in data['users'] if str(u['port']) == '$port']
if users:
    for u in users:
        print(f"找到用户: {u['name']} (ID: {u['id']})")
        print(f"端口: {u['port']}, 密码: {u['password']}")
        print(f"状态: {'启用' if u.get('enable', True) else '禁用'}")
else:
    print("未找到使用该端口的用户")
PYEOF
}

query_by_name() {
    read -p "请输入用户名(支持模糊查询): " name
    [ -z "$name" ] && return
    
    python3 << PYEOF
import json
with open('$USERS_FILE', 'r') as f:
    data = json.load(f)

users = [u for u in data['users'] if '$name' in u['name']]
if users:
    print(f"找到 {len(users)} 个用户:")
    for u in users:
        status = "启用" if u.get('enable', True) else "禁用"
        print(f"  ID:{u['id']} 用户名:{u['name']} 端口:{u['port']} 状态:{status}")
else:
    print("未找到匹配的用户")
PYEOF
}

query_by_status() {
    echo "1) 启用  2) 禁用  3) 所有"
    read -p "选择状态: " s
    local status="all"
    [ "$s" == "1" ] && status="enable"
    [ "$s" == "2" ] && status="disable"
    
    python3 << PYEOF
import json
with open('$USERS_FILE', 'r') as f:
    data = json.load(f)

users = data['users']
if '$status' == 'enable':
    users = [u for u in users if u.get('enable', True)]
elif '$status' == 'disable':
    users = [u for u in users if not u.get('enable', True)]

print(f"共 {len(users)} 个用户:")
for u in users:
    status = "启用" if u.get('enable', True) else "禁用"
    print(f"  ID:{u['id']} {u['name']:<12} 端口:{u['port']:<6} {status}")
PYEOF
}

show_connections() {
    echo -e "${CYAN}========== 连接状态 ==========${NC}"
    echo -e "${YELLOW}端口\t\t连接数\t\t用户${NC}"
    echo "----------------------------------------"
    
    python3 << PYEOF
import json
import subprocess

with open('$USERS_FILE', 'r') as f:
    data = json.load(f)

for u in data['users']:
    if not u.get('enable', True):
        continue
    port = u['port']
    try:
        result = subprocess.run(['ss', '-ant'], capture_output=True, text=True)
        connections = len([line for line in result.stdout.split('\n') if f':{port}' in line])
        print(f"{port}\t\t{connections}\t\t{u['name']}")
    except:
        print(f"{port}\t\t?\t\t{u['name']}")
PYEOF
}

query_menu() {
    while true; do
        echo -e "\n${CYAN}========== 配置查询 ==========${NC}"
        echo "1) 按端口查询"
        echo "2) 按用户名查询"
        echo "3) 按状态查询"
        echo "4) 查看所有配置详情"
        echo "5) 查看连接状态"
        echo "6) 导出所有配置"
        echo "0) 返回上级"
        read -p "请选择: " choice
        
        case $choice in
            1) query_by_port ;;
            2) query_by_name ;;
            3) query_by_status ;;
            4) show_user_info 0 ;;
            5) show_connections ;;
            6) 
                show_user_info 0 > "$INFO_FILE"
                echo -e "${GREEN}配置已导出到: $INFO_FILE${NC}"
                ;;
            0) break ;;
            *) echo -e "${RED}无效选项${NC}" ;;
        esac
        press_any_key
    done
}

# ============================================
# 基础配置（单用户快速配置）
# ============================================

single_user_config() {
    echo -e "${GREEN}========== 单用户快速配置 ==========${NC}"
    
    # 如果已有用户，询问是否覆盖或添加
    local user_count=$(python3 -c "import json; print(len(json.load(open('$USERS_FILE'))['users']))")
    
    if [ "$user_count" -gt 0 ]; then
        echo -e "${YELLOW}检测到已有 $user_count 个用户${NC}"
        echo "1) 覆盖现有配置（删除所有用户，新建单用户）"
        echo "2) 保留现有配置，仅修改主用户"
        read -p "请选择: " opt
        
        if [ "$opt" == "1" ]; then
            # 删除所有用户
            python3 -c "import json; data=json.load(open('$USERS_FILE')); data['users']=[]; data['mode']='single'; json.dump(data, open('$USERS_FILE','w'), indent=2)"
        else
            # 修改第一个用户
            modify_first_user
            return
        fi
    fi
    
    # 设置为单用户模式
    python3 -c "import json; data=json.load(open('$USERS_FILE')); data['mode']='single'; json.dump(data, open('$USERS_FILE','w'), indent=2)"
    
    # 添加单个用户（ID=1）
    read -p "端口 [随机]: " port
    port=${port:-$(generate_port)}
    local password=$(generate_password)
    read -p "密码 [默认: $password]: " input_pass
    password=${input_pass:-$password}
    
    echo -e "${CYAN}请选择加密方式：${NC}"
    local method=$(get_method)
    echo -e "${CYAN}请选择协议：${NC}"
    local protocol=$(get_protocol)
    echo -e "${CYAN}请选择混淆：${NC}"
    local obfs=$(get_obfs)
    
    python3 << PYEOF
import json
with open('$USERS_FILE', 'r') as f:
    data = json.load(f)

new_user = {
    "id": 1,
    "name": "default",
    "port": $port,
    "password": "$password",
    "method": "$method",
    "protocol": "$protocol",
    "obfs": "$obfs",
    "enable": True,
    "created": "$(date +%Y-%m-%d)"
}

data['users'].append(new_user)
with open('$USERS_FILE', 'w') as f:
    json.dump(data, f, indent=2)
PYEOF

    configure_firewall_port "$port"
    generate_ssr_config
    echo -e "${GREEN}单用户配置完成！${NC}"
    show_user_info 1
}

modify_first_user() {
    local user=$(python3 -c "import json; users=json.load(open('$USERS_FILE'))['users']; print(json.dumps(users[0]) if users else '{}')")
    [ "$user" == "{}" ] && return
    
    local id=$(echo "$user" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
    local old_port=$(echo "$user" | python3 -c "import sys,json; print(json.load(sys.stdin)['port'])")
    
    echo -e "修改主用户配置..."
    read -p "新端口 [回车保持 $old_port]: " new_port
    new_port=${new_port:-$old_port}
    
    local new_pass=$(generate_password)
    read -p "新密码 [回车随机生成]: " input_pass
    new_pass=${input_pass:-$new_pass}
    
    python3 << PYEOF
import json
with open('$USERS_FILE', 'r') as f:
    data = json.load(f)

if data['users']:
    data['users'][0]['port'] = int($new_port)
    data['users'][0]['password'] = "$new_pass"

with open('$USERS_FILE', 'w') as f:
    json.dump(data, f, indent=2)
PYEOF

    if [ "$new_port" != "$old_port" ]; then
        remove_firewall_port "$old_port"
        configure_firewall_port "$new_port"
    fi
    
    generate_ssr_config
    echo -e "${GREEN}配置已更新${NC}"
    show_user_info 1
}

# ============================================
# 服务管理函数
# ============================================

start_service() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}错误：未找到配置文件，请先配置${NC}"
        return
    fi
    
    echo -e "${BLUE}正在启动 ShadowsocksR...${NC}"
    systemctl restart shadowsocksr
    sleep 2
    
    if systemctl is-active --quiet shadowsocksr; then
        echo -e "${GREEN}服务启动成功！${NC}"
    else
        echo -e "${RED}服务启动失败${NC}"
        journalctl -u shadowsocksr -n 20 --no-pager
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
        show_connections
    fi
}

view_logs() {
    echo -e "${CYAN}========== 实时日志 (按 Ctrl+C 退出) ==========${NC}"
    journalctl -u shadowsocksr -f --no-hostname
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
    rm -f "$USERS_FILE"
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
    echo "║        ShadowsocksR 管理脚本 v3.0              ║"
    echo "║           支持多用户 & 交互查询                ║"
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
        
        if [ -f "$USERS_FILE" ]; then
            local mode=$(python3 -c "import json; print(json.load(open('$USERS_FILE')).get('mode', 'single'))")
            local count=$(python3 -c "import json; print(len(json.load(open('$USERS_FILE'))['users']))")
            echo -e "${CYAN}  模式: $mode | 用户数量: $count${NC}"
        fi
    else
        echo -e "${YELLOW}● 未安装${NC}"
    fi
    
    echo ""
    echo -e "  ${CYAN}[1]${NC} 安装 SSR"
    echo -e "  ${CYAN}[2]${NC} 单用户快速配置"
    echo -e "  ${CYAN}[3]${NC} 多用户管理"
    echo -e "  ${CYAN}[4]${NC} 配置查询"
    echo -e "  ${CYAN}[5]${NC} 启动服务"
    echo -e "  ${CYAN}[6]${NC} 停止服务"
    echo -e "  ${CYAN}[7]${NC} 重启服务"
    echo -e "  ${CYAN}[8]${NC} 查看状态"
    echo -e "  ${CYAN}[9]${NC} 查看日志"
    echo -e "  ${CYAN}[10]${NC} 卸载 SSR"
    echo -e "  ${CYAN}[0]${NC} 退出"
    echo ""
    echo -e "${PURPLE}════════════════════════════════════════════════${NC}"
}

config_menu() {
    check_ssr_installed || return
    init_users_file
    
    while true; do
        echo -e "\n${PURPLE}========== 配置管理 ==========${NC}"
        echo "1) 单用户快速配置（推荐新手）"
        echo "2) 多用户管理（高级）"
        echo "0) 返回主菜单"
        read -p "请选择: " choice
        
        case $choice in
            1) 
                single_user_config
                press_any_key
                ;;
            2) 
                multi_user_menu 
                ;;
            0) break ;;
            *) echo -e "${RED}无效选项${NC}" ;;
        esac
    done
}

main() {
    check_root
    
    while true; do
        show_menu
        read -p "请输入选项 [0-10]: " choice
        echo ""
        
        case $choice in
            1) install_ssr; press_any_key ;;
            2) single_user_config; press_any_key ;;
            3) check_ssr_installed && multi_user_menu ;;
            4) check_ssr_installed && query_menu ;;
            5) check_ssr_installed && start_service; press_any_key ;;
            6) check_ssr_installed && stop_service; press_any_key ;;
            7) check_ssr_installed && restart_service; press_any_key ;;
            8) check_ssr_installed && view_status; press_any_key ;;
            9) check_ssr_installed && view_logs ;;
            10) uninstall_ssr; press_any_key ;;
            0) echo -e "${GREEN}再见！${NC}"; exit 0 ;;
            *) echo -e "${RED}无效选项${NC}"; press_any_key ;;
        esac
    done
}

# 运行主函数
main
