#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

GITHUB_REPO="hanshans135/autopterobk"
INSTALL_DIR="/opt/autopterobk"
VENV_DIR="$INSTALL_DIR/.venv"

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    echo ""
    echo "============================================"
    echo "  AutoPteroBK 安裝腳本"
    echo "============================================"
    echo ""
    echo "用法: $0 [選項]"
    echo ""
    echo "選項:"
    echo "  server                    安裝伺服端"
    echo "  client [參數]             安裝用戶端"
    echo ""
    echo "Server 安裝範例:"
    echo "  $0 server"
    echo ""
    echo "Client 安裝範例:"
    echo "  $0 client --url https://your-server.com --key your-api-key"
    echo ""
    echo "Client 參數:"
    echo "  --url <URL>       伺服端 URL"
    echo "  --key <API_KEY>   API 金鑰"
    echo ""
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "請使用 root 權限執行此腳本"
        echo "使用: sudo $0 $*"
        exit 1
    fi
}

detect_os() {
    if [ -f /etc/synoinfo.conf ] || [ -f /etc.defaults/synoinfo.conf ]; then
        OS="synology"
        VERSION=$(cat /etc.defaults/VERSION 2>/dev/null | grep productversion | cut -d'"' -f2 || echo "unknown")
        print_info "檢測到系統: Synology DSM $VERSION"
        return
    fi
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS="centos"
        VERSION=$(cat /etc/redhat-release | grep -oE '[0-9]+' | head -1)
    elif [ -f /etc/debian_version ]; then
        OS="debian"
        VERSION=$(cat /etc/debian_version)
    else
        print_warning "無法檢測作業系統類型，嘗試繼續安裝..."
        OS="unknown"
        VERSION="unknown"
    fi
    print_info "檢測到系統: $OS $VERSION"
}

install_dependencies() {
    print_info "正在安裝系統依賴..."
    
    case $OS in
        ubuntu|debian)
            apt-get update
            apt-get install -y python3 python3-pip python3-venv git curl
            ;;
        centos|rhel|fedora|rocky|almalinux)
            if command -v dnf &> /dev/null; then
                dnf install -y python3 python3-pip git curl
            else
                yum install -y python3 python3-pip git curl
            fi
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm python python-pip git curl
            ;;
        synology)
            # 群暉 DSM 需要透過套件中心或 opkg/entware 安裝
            print_warning "群暉 DSM 系統檢測到"
            print_info "請確保已安裝以下套件："
            print_info "  - Python 3 (透過套件中心)"
            print_info "  - Git (透過套件中心或 Community)"
            
            # 檢查 Python3 是否存在
            if ! command -v python3 &> /dev/null; then
                print_error "找不到 Python3，請先從套件中心安裝 Python 3"
                exit 1
            fi
            
            # 檢查 git 是否存在
            if ! command -v git &> /dev/null; then
                print_error "找不到 Git，請先從套件中心安裝 Git"
                exit 1
            fi
            
            # 確保 pip 可用
            if ! python3 -m pip --version &> /dev/null; then
                print_info "正在安裝 pip..."
                python3 -m ensurepip --upgrade 2>/dev/null || curl -sSL https://bootstrap.pypa.io/get-pip.py | python3
            fi
            ;;
        *)
            print_warning "未知的系統類型，嘗試繼續安裝..."
            # 嘗試檢查必要的工具
            if ! command -v python3 &> /dev/null; then
                print_error "找不到 Python3，請手動安裝"
                exit 1
            fi
            if ! command -v git &> /dev/null; then
                print_error "找不到 Git，請手動安裝"
                exit 1
            fi
            ;;
    esac
    
    print_success "系統依賴檢查完成"
}

download_project() {
    print_info "正在從 GitHub 下載專案..."
    
    if [ -d "$INSTALL_DIR" ]; then
        print_warning "安裝目錄已存在，正在備份..."
        mv "$INSTALL_DIR" "${INSTALL_DIR}.backup.$(date +%Y%m%d%H%M%S)"
    fi
    
    git clone "https://github.com/${GITHUB_REPO}.git" "$INSTALL_DIR"
    
    print_success "專案下載完成"
}

setup_venv() {
    print_info "正在建立 Python 虛擬環境..."
    
    # 群暉可能沒有 venv 模組，嘗試使用 virtualenv 或直接安裝
    if python3 -m venv "$VENV_DIR" 2>/dev/null; then
        print_info "使用 venv 建立虛擬環境"
    elif command -v virtualenv &> /dev/null; then
        print_info "使用 virtualenv 建立虛擬環境"
        virtualenv -p python3 "$VENV_DIR"
    else
        print_warning "無法建立虛擬環境，嘗試安裝 virtualenv..."
        python3 -m pip install virtualenv
        virtualenv -p python3 "$VENV_DIR"
    fi
    
    print_info "正在安裝 Python 套件..."
    
    source "$VENV_DIR/bin/activate"
    pip install --upgrade pip
    pip install -r "$INSTALL_DIR/requirement.txt"
    deactivate
    
    print_success "Python 環境設定完成"
}

generate_secret_key() {
    python3 -c "import secrets; print(secrets.token_hex(32))"
}

configure_server() {
    print_info "正在配置伺服端..."
    
    local config_file="$INSTALL_DIR/server/config.json"
    local example_config="$INSTALL_DIR/server/example_config.json"
    
    if [ -f "$config_file" ]; then
        print_warning "配置文件已存在，跳過配置"
        return
    fi
    
    cp "$example_config" "$config_file"
    
    # 互動式配置
    echo ""
    echo "========== 伺服端配置 =========="
    echo ""
    
    read -p "請輸入監聽地址 [0.0.0.0]: " host
    host=${host:-0.0.0.0}
    
    read -p "請輸入監聽端口 [8080]: " port
    port=${port:-8080}
    
    read -p "請輸入 Pterodactyl Panel URL: " panel_url
    
    read -p "請輸入 Pterodactyl API Key: " api_key
    
    read -p "請輸入資料目錄路徑 [/var/lib/pterodactyl/volumes]: " data_path
    data_path=${data_path:-/var/lib/pterodactyl/volumes}
    
    read -p "請輸入最大上傳大小 (GB) [2]: " max_size
    max_size=${max_size:-2}
    
    read -p "請輸入管理員帳號 [admin]: " admin_user
    admin_user=${admin_user:-admin}
    
    read -sp "請輸入管理員密碼: " admin_pass
    echo ""
    
    local secret_key=$(generate_secret_key)
    
    python3 << EOF
import json

config_path = "$config_file"

with open(config_path, 'r') as f:
    config = json.load(f)

config['host'] = "$host"
config['port'] = $port
config['base_url'] = "$panel_url"
config['api_key'] = "$api_key"
config['data_path'] = "$data_path"
config['max_size'] = $max_size
config['key'] = "$secret_key"
config['account'] = {
    'username': "$admin_user",
    'password': "$admin_pass"
}

with open(config_path, 'w') as f:
    json.dump(config, f, indent=4)

print("配置文件已更新")
EOF
    
    print_success "伺服端配置完成"
}

configure_client() {
    local server_url=$1
    local api_key=$2
    
    print_info "正在配置用戶端..."
    
    local config_file="$INSTALL_DIR/client/config.json"
    local example_config="$INSTALL_DIR/client/example_config.json"
    
    if [ -f "$config_file" ] && [ -z "$server_url" ]; then
        print_warning "配置文件已存在，跳過配置"
        return
    fi
    
    cp "$example_config" "$config_file"
    
    if [ -z "$server_url" ]; then
        echo ""
        echo "========== 用戶端配置 =========="
        echo ""
        
        read -p "請輸入伺服端 URL: " server_url
        read -p "請輸入 API Key: " api_key
    fi
    
    python3 << EOF
import json

config_path = "$config_file"

with open(config_path, 'r') as f:
    config = json.load(f)

config['base_url'] = "$server_url"
config['api_key'] = "$api_key"

with open(config_path, 'w') as f:
    json.dump(config, f, indent=4)

print("配置文件已更新")
EOF
    
    print_success "用戶端配置完成"
}

setup_systemd_server() {
    print_info "正在建立 systemd 服務..."
    
    cat > /etc/systemd/system/autopterobk-server.service << EOF
[Unit]
Description=AutoPteroBK Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR/server
Environment="PATH=$VENV_DIR/bin"
ExecStart=$VENV_DIR/bin/python $INSTALL_DIR/server/app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    
    systemctl enable autopterobk-server
    
    systemctl start autopterobk-server
    
    print_success "systemd 服務已建立並啟動"
    echo ""
    echo "管理命令:"
    echo "  啟動: systemctl start autopterobk-server"
    echo "  停止: systemctl stop autopterobk-server"
    echo "  重啟: systemctl restart autopterobk-server"
    echo "  狀態: systemctl status autopterobk-server"
    echo "  日誌: journalctl -u autopterobk-server -f"
    echo ""
}

setup_crontab_client() {
    print_info "正在設定 crontab..."
    
    cat > "$INSTALL_DIR/run_client.sh" << EOF
#!/bin/bash
cd $INSTALL_DIR/client
source $VENV_DIR/bin/activate
python app.py
deactivate
EOF
    
    chmod +x "$INSTALL_DIR/run_client.sh"
    
    crontab -l 2>/dev/null | grep -v "autopterobk" | crontab - 2>/dev/null || true
    
    (crontab -l 2>/dev/null; echo "0 3 * * * $INSTALL_DIR/run_client.sh >> /var/log/autopterobk-client.log 2>&1") | crontab -
    
    print_success "crontab 已設定 (每天凌晨 3:00 執行)"
    echo ""
    echo "查看排程: crontab -l"
    echo "查看日誌: tail -f /var/log/autopterobk-client.log"
    echo "手動執行: $INSTALL_DIR/run_client.sh"
    echo ""
}

install_server() {
    print_info "開始安裝伺服端..."
    echo ""
    
    check_root
    detect_os
    install_dependencies
    download_project
    setup_venv
    configure_server
    setup_systemd_server
    
    echo ""
    echo "============================================"
    print_success "伺服端安裝完成！"
    echo "============================================"
    echo ""
    echo "安裝目錄: $INSTALL_DIR"
    echo "配置文件: $INSTALL_DIR/server/config.json"
    echo ""
    systemctl status autopterobk-server --no-pager
    echo ""
}

# 安裝用戶端
install_client() {
    local server_url=""
    local api_key=""
    
    # 解析參數
    while [[ $# -gt 0 ]]; do
        case $1 in
            --url)
                server_url="$2"
                shift 2
                ;;
            --key)
                api_key="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    print_info "開始安裝用戶端..."
    echo ""
    
    check_root
    detect_os
    install_dependencies
    download_project
    setup_venv
    configure_client "$server_url" "$api_key"
    setup_crontab_client
    
    echo ""
    echo "============================================"
    print_success "用戶端安裝完成！"
    echo "============================================"
    echo ""
    echo "安裝目錄: $INSTALL_DIR"
    echo "配置文件: $INSTALL_DIR/client/config.json"
    echo "執行腳本: $INSTALL_DIR/run_client.sh"
    echo "排程時間: 每天凌晨 3:00"
    echo ""
}

# 主程式
main() {
    echo ""
    echo "============================================"
    echo "  AutoPteroBK 安裝腳本"
    echo "============================================"
    echo ""
    
    case $1 in
        server)
            install_server
            ;;
        client)
            shift
            install_client "$@"
            ;;
        -h|--help|help)
            show_usage
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
