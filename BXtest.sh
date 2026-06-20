#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

BXTEST_GITHUB_API_URL="https://api.github.com/repos/Kopw/BXtest/releases/latest"
BXTEST_GITHUB_RELEASE_URL="https://github.com/Kopw/BXtest/releases/download"
BXTEST_RESOLVED_VERSION=""
BXTEST_GITHUB_MIRROR=""
BXTEST_GITHUB_MIRRORS=(
    "https://gh.llkk.cc"
    "https://ghfast.top"
    "https://gh-proxy.com"
    "https://hub.gitmirror.com"
)

normalize_github_mirror() {
    local mirror="$1"
    mirror=$(echo "$mirror" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
    [[ -z "$mirror" ]] && return 1
    if [[ "$mirror" != http://* && "$mirror" != https://* ]]; then
        mirror="https://${mirror}"
    fi
    echo "${mirror%/}"
}

github_url_with_mirror() {
    local mirror="$1"
    local target_url="$2"
    if [[ -z "$mirror" ]]; then
        echo "$target_url"
        return 0
    fi

    mirror=$(normalize_github_mirror "$mirror") || return 1
    echo "${mirror}/${target_url}"
}

detect_latest_BXtest_version_from() {
    local mirror="$1"
    local api_url
    api_url=$(github_url_with_mirror "$mirror" "$BXTEST_GITHUB_API_URL") || return 1
    curl -fsSL "$api_url" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | head -n 1
}

detect_latest_BXtest_version() {
    local mirror
    local version

    BXTEST_RESOLVED_VERSION=""
    BXTEST_GITHUB_MIRROR=""

    version=$(detect_latest_BXtest_version_from "")
    if [[ -n "$version" ]]; then
        BXTEST_RESOLVED_VERSION="$version"
        return 0
    fi

    echo -e "${yellow}检测 BXtest 版本失败，正在尝试内置 GitHub 镜像站点...${plain}"
    for mirror in "${BXTEST_GITHUB_MIRRORS[@]}"; do
        mirror=$(normalize_github_mirror "$mirror") || continue
        echo -e "${yellow}尝试镜像：${mirror}${plain}"
        version=$(detect_latest_BXtest_version_from "$mirror")
        if [[ -n "$version" ]]; then
            BXTEST_RESOLVED_VERSION="$version"
            BXTEST_GITHUB_MIRROR="$mirror"
            return 0
        fi
    done

    while true; do
        read -rp "内置镜像均不可用，请输入 GitHub 镜像站点（例如 https://gh.llkk.cc，直接回车取消）: " mirror
        mirror=$(normalize_github_mirror "$mirror") || return 1
        echo -e "${yellow}尝试镜像：${mirror}${plain}"
        version=$(detect_latest_BXtest_version_from "$mirror")
        if [[ -n "$version" ]]; then
            BXTEST_RESOLVED_VERSION="$version"
            BXTEST_GITHUB_MIRROR="$mirror"
            return 0
        fi
        echo -e "${red}该镜像无法获取 BXtest 最新版本，请检查后重试${plain}"
    done
}

download_BXtest_from() {
    local mirror="$1"
    local version="$2"
    local output="$3"
    local arch="$4"
    local target_url="${BXTEST_GITHUB_RELEASE_URL}/${version}/BXtest-linux-${arch}.zip"
    local download_url

    download_url=$(github_url_with_mirror "$mirror" "$target_url") || return 1
    wget --no-check-certificate -N -q --show-progress -O "$output" "$download_url"
    if [[ $? -ne 0 ]]; then
        rm -f "$output"
        return 1
    fi
    return 0
}

download_BXtest_release() {
    local version="$1"
    local output="$2"
    local arch="$3"
    local mirror

    if [[ -n "$BXTEST_GITHUB_MIRROR" ]]; then
        echo -e "${yellow}正在通过镜像下载 BXtest ${version} (${arch})：${BXTEST_GITHUB_MIRROR}${plain}"
        if download_BXtest_from "$BXTEST_GITHUB_MIRROR" "$version" "$output" "$arch"; then
            return 0
        fi
        echo -e "${yellow}镜像下载失败，正在尝试原始 GitHub 地址...${plain}"
    fi

    echo -e "${yellow}正在下载 BXtest ${version} (${arch})...${plain}"
    if download_BXtest_from "" "$version" "$output" "$arch"; then
        return 0
    fi

    echo -e "${yellow}原始 GitHub 下载失败，正在尝试内置 GitHub 镜像站点...${plain}"
    for mirror in "${BXTEST_GITHUB_MIRRORS[@]}"; do
        mirror=$(normalize_github_mirror "$mirror") || continue
        [[ -n "$BXTEST_GITHUB_MIRROR" && "$mirror" == "$BXTEST_GITHUB_MIRROR" ]] && continue
        echo -e "${yellow}尝试镜像：${mirror}${plain}"
        if download_BXtest_from "$mirror" "$version" "$output" "$arch"; then
            BXTEST_GITHUB_MIRROR="$mirror"
            return 0
        fi
    done

    while true; do
        read -rp "内置镜像均下载失败，请输入 GitHub 镜像站点（直接回车取消）: " mirror
        mirror=$(normalize_github_mirror "$mirror") || return 1
        echo -e "${yellow}尝试镜像：${mirror}${plain}"
        if download_BXtest_from "$mirror" "$version" "$output" "$arch"; then
            BXTEST_GITHUB_MIRROR="$mirror"
            return 0
        fi
        echo -e "${red}该镜像下载失败，请检查后重试${plain}"
    done
}

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "alpine"; then
    release="alpine"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "arch"; then
    release="arch"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
    if [[ ${os_version} -eq 7 ]]; then
        echo -e "${red}注意： CentOS 7 无法使用hysteria1/2协议！${plain}\n"
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

# 检查系统是否有 IPv6 地址
check_ipv6_support() {
    if ip -6 addr | grep -q "inet6"; then
        echo "1"  # 支持 IPv6
    else
        echo "0"  # 不支持 IPv6
    fi
}

# 设置北京时区
set_beijing_timezone() {
    echo -e "${yellow}正在设置系统时区为北京时间 (Asia/Shanghai)...${plain}"
    
    case "$release" in
        "alpine")
            # Alpine 使用 apk 安装 tzdata 并设置时区
            apk add --no-cache tzdata >/dev/null 2>&1
            cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
            echo "Asia/Shanghai" > /etc/timezone
            ;;
        "debian"|"ubuntu")
            # Debian/Ubuntu 使用 timedatectl 或直接设置
            if command -v timedatectl &>/dev/null; then
                timedatectl set-timezone Asia/Shanghai >/dev/null 2>&1
            else
                # 备用方案：直接设置
                ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
                echo "Asia/Shanghai" > /etc/timezone
            fi
            ;;
        "centos")
            # CentOS 使用 timedatectl
            if command -v timedatectl &>/dev/null; then
                timedatectl set-timezone Asia/Shanghai >/dev/null 2>&1
            else
                ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
            fi
            ;;
        *)
            # 通用方案
            if [[ -f /usr/share/zoneinfo/Asia/Shanghai ]]; then
                ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
                echo "Asia/Shanghai" > /etc/timezone 2>/dev/null
            else
                echo -e "${red}无法设置时区，请手动设置为 Asia/Shanghai${plain}"
                return 1
            fi
            ;;
    esac
    
    echo -e "${green}时区已设置为: $(date +%Z) $(date)${plain}"
    return 0
}

# 安装 acme.sh 依赖
install_acme_deps() {
    echo -e "${yellow}正在安装 acme.sh 依赖...${plain}"
    
    case "$release" in
        "debian"|"ubuntu")
            apt-get update -y >/dev/null 2>&1
            apt-get install -y curl socat cron openssl >/dev/null 2>&1
            systemctl enable cron >/dev/null 2>&1
            systemctl start cron >/dev/null 2>&1
            ;;
        "alpine")
            apk update >/dev/null 2>&1
            apk add curl socat openssl dcron >/dev/null 2>&1
            rc-update add dcron default >/dev/null 2>&1
            rc-service dcron start >/dev/null 2>&1
            ;;
        "centos")
            yum install -y curl socat cronie openssl >/dev/null 2>&1
            systemctl enable crond >/dev/null 2>&1
            systemctl start crond >/dev/null 2>&1
            ;;
        *)
            echo -e "${red}未知系统，请手动安装 curl socat openssl 和 cron${plain}"
            ;;
    esac
}

# 安装 acme.sh
install_acme() {
    local email=$1
    if command -v ~/.acme.sh/acme.sh &> /dev/null; then
        echo -e "${green}acme.sh 已安装，正在更新...${plain}"
        ~/.acme.sh/acme.sh --upgrade >/dev/null 2>&1
    else
        echo -e "${yellow}正在安装 acme.sh...${plain}"
        curl -s https://get.acme.sh | sh -s email="$email"
        if [[ $? -ne 0 ]]; then
            echo -e "${red}acme.sh 安装失败${plain}"
            return 1
        fi
    fi
    # 设置默认 CA 为 Let's Encrypt
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1
    # 更新账户邮箱（解决之前用 example.com 注册的问题）
    echo -e "${yellow}正在更新账户邮箱...${plain}"
    ~/.acme.sh/acme.sh --update-account --accountemail "$email" >/dev/null 2>&1
    return 0
}

# 检测现有证书
check_existing_cert() {
    local ip_addr=$1
    local cert_path="/etc/BXtest"
    local bt_cert_path="/www/server/panel/vhost/cert/${ip_addr}"
    local bt_panel_ssl="/www/server/panel/ssl"
    
    # 检查宝塔面板网站证书目录
    if [[ -f "${bt_cert_path}/fullchain.pem" && -f "${bt_cert_path}/privkey.pem" ]]; then
        echo -e "${green}检测到宝塔面板已有 IP 证书：${bt_cert_path}${plain}"
        read -rp "是否使用该证书？(y/n，默认y): " use_bt_cert
        use_bt_cert=${use_bt_cert:-y}
        if [[ "$use_bt_cert" == "y" || "$use_bt_cert" == "Y" ]]; then
            # 创建软链接到 BXtest 目录（证书更新后会自动关联）
            ln -sf "${bt_cert_path}/fullchain.pem" "${cert_path}/fullchain.cer"
            ln -sf "${bt_cert_path}/privkey.pem" "${cert_path}/cert.key"
            echo -e "${green}已创建软链接到 ${cert_path}${plain}"
            return 0
        fi
    fi
    
    # 检查宝塔面板自用 SSL 证书
    if [[ -f "${bt_panel_ssl}/certificate.pem" && -f "${bt_panel_ssl}/privateKey.pem" ]]; then
        # 检查证书是否包含该 IP
        local cert_info=$(openssl x509 -in "${bt_panel_ssl}/certificate.pem" -text -noout 2>/dev/null)
        if echo "$cert_info" | grep -q "IP Address:${ip_addr}"; then
            echo -e "${green}检测到宝塔面板自用 SSL 证书包含 IP：${ip_addr}${plain}"
            read -rp "是否使用该证书？(y/n，默认y): " use_panel_cert
            use_panel_cert=${use_panel_cert:-y}
            if [[ "$use_panel_cert" == "y" || "$use_panel_cert" == "Y" ]]; then
                # 创建软链接到 BXtest 目录
                ln -sf "${bt_panel_ssl}/certificate.pem" "${cert_path}/fullchain.cer"
                ln -sf "${bt_panel_ssl}/privateKey.pem" "${cert_path}/cert.key"
                echo -e "${green}已创建软链接到 ${cert_path}${plain}"
                return 0
            fi
        fi
    fi
    
    # 检查 BXtest 目录是否已有证书
    if [[ -f "${cert_path}/fullchain.cer" && -f "${cert_path}/cert.key" ]]; then
        echo -e "${green}检测到 ${cert_path} 目录已有证书${plain}"
        read -rp "是否使用现有证书？(y/n，默认y): " use_existing
        use_existing=${use_existing:-y}
        if [[ "$use_existing" == "y" || "$use_existing" == "Y" ]]; then
            echo -e "${green}将使用现有证书${plain}"
            return 0
        fi
    fi
    
    # 没有找到现有证书或用户选择不使用
    return 1
}


issue_ip_cert() {
    local ip_addr=$1
    local cert_path="/etc/BXtest"
    
    echo -e "${yellow}正在为 IP ${ip_addr} 申请 Let's Encrypt 证书...${plain}"
    echo -e "${yellow}注意：证书申请需要使用端口 80，请确保端口 80 未被占用${plain}"
    echo -e "${yellow}如果端口 80 被占用，请手动停止占用该端口的服务后重试${plain}"
    
    # 使用 standalone 模式申请 IP 证书（短期证书）
    echo -e "${yellow}正在申请证书，请稍候...${plain}"
    ~/.acme.sh/acme.sh --issue --standalone -d "$ip_addr" \
        --server letsencrypt \
        --certificate-profile shortlived \
        --force
    
    if [[ $? -ne 0 ]]; then
        echo -e "${red}证书申请失败，请检查上方日志信息${plain}"
        echo -e "${red}常见原因：${plain}"
        echo -e "${red}1. IP 地址是否正确（必须是公网 IP）${plain}"
        echo -e "${red}2. 端口 80 是否对外开放${plain}"
        echo -e "${red}3. 防火墙是否放行${plain}"
        echo -e "${red}4. Let's Encrypt 服务是否可达${plain}"
        return 1
    fi
    
    # 安装证书到指定目录
    echo -e "${yellow}正在安装证书...${plain}"
    # 注意：不设置 reloadcmd 以避免自动重启 BXtest
    # 证书更新后仅更新文件，BXtest 会在下次启动时自动加载新证书
    ~/.acme.sh/acme.sh --install-cert -d "$ip_addr" \
        --key-file "$cert_path/cert.key" \
        --fullchain-file "$cert_path/fullchain.cer" \
        --reloadcmd "true"
    
    if [[ $? -ne 0 ]]; then
        echo -e "${red}证书安装失败，请检查上方日志信息${plain}"
        return 1
    fi
    
    # 设置每日自动续期（因为 IP 证书只有 6 天有效期）
    setup_daily_renewal "$ip_addr"
    
    echo -e "${green}IP 证书申请成功！${plain}"
    echo -e "${green}证书路径: ${cert_path}/fullchain.cer${plain}"
    echo -e "${green}私钥路径: ${cert_path}/cert.key${plain}"
    return 0
}

# 设置每日自动续期
setup_daily_renewal() {
    local ip_addr=$1
    # 每天早上 6:30 执行续期，使用 --force 强制更新
    local cron_cmd="30 6 * * * /root/.acme.sh/acme.sh --cron --home /root/.acme.sh --force >/dev/null 2>&1"
    
    # 先设置北京时区，确保 cron 按北京时间执行
    set_beijing_timezone
    
    # 检查是否已存在续期任务，如果存在则先删除旧的
    if crontab -l 2>/dev/null | grep -q "acme.sh --cron"; then
        echo -e "${yellow}检测到旧的续期任务，正在更新...${plain}"
        crontab -l 2>/dev/null | grep -v "acme.sh --cron" | crontab -
    fi
    
    # 添加新的 cron 任务
    (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
    
    if [[ $? -eq 0 ]]; then
        echo -e "${green}已设置每日早上 6:30（北京时间）自动续期${plain}"
    else
        echo -e "${red}设置自动续期失败，请手动添加 cron 任务${plain}"
        echo -e "${yellow}cron 命令: $cron_cmd${plain}"
    fi
}

# 从直链下载证书和密钥
download_cert_from_url() {
    local cert_url=$1
    local key_url=$2
    local cert_remark=$3
    local cert_path="/etc/BXtest"
    local cert_file="${cert_remark}_fullchain.cer"
    local key_file="${cert_remark}_cert.key"
    
    echo -e "${yellow}正在从直链下载证书...${plain}"
    
    # 确保目录存在
    mkdir -p "$cert_path"
    
    # 下载证书
    if curl -sL -o "${cert_path}/${cert_file}" "$cert_url"; then
        echo -e "${green}证书下载成功: ${cert_path}/${cert_file}${plain}"
    else
        echo -e "${red}证书下载失败，请检查 URL 是否正确${plain}"
        return 1
    fi
    
    # 下载密钥
    if curl -sL -o "${cert_path}/${key_file}" "$key_url"; then
        echo -e "${green}密钥下载成功: ${cert_path}/${key_file}${plain}"
    else
        echo -e "${red}密钥下载失败，请检查 URL 是否正确${plain}"
        return 1
    fi
    
    # 设置正确的权限
    chmod 600 "${cert_path}/${key_file}"
    chmod 644 "${cert_path}/${cert_file}"
    
    echo -e "${green}证书和密钥下载完成！${plain}"
    return 0
}

# 设置每日自动下载证书
setup_daily_cert_download() {
    local cert_url=$1
    local key_url=$2
    local cert_remark=$3
    local cert_path="/etc/BXtest"
    
    # 创建下载脚本
    local download_script="/etc/BXtest/update_cert.sh"
    cat > "$download_script" << 'SCRIPT_EOF'
#!/bin/bash
# BXtest 证书自动更新脚本
CERT_URL="__CERT_URL__"
KEY_URL="__KEY_URL__"
CERT_REMARK="__CERT_REMARK__"
CERT_PATH="/etc/BXtest"
CERT_FILE="${CERT_REMARK}_fullchain.cer"
KEY_FILE="${CERT_REMARK}_cert.key"
LOG_FILE="/var/log/bxtest_cert_update.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "开始更新证书..."

# 确保目录存在
mkdir -p "$CERT_PATH"

# 直接下载证书覆盖旧文件
if curl -sL -o "${CERT_PATH}/${CERT_FILE}" "$CERT_URL"; then
    log "证书下载成功: ${CERT_PATH}/${CERT_FILE}"
else
    log "证书下载失败"
    exit 1
fi

# 直接下载密钥覆盖旧文件
if curl -sL -o "${CERT_PATH}/${KEY_FILE}" "$KEY_URL"; then
    log "密钥下载成功: ${CERT_PATH}/${KEY_FILE}"
else
    log "密钥下载失败"
    exit 1
fi

# 设置权限
chmod 644 "${CERT_PATH}/${CERT_FILE}"
chmod 600 "${CERT_PATH}/${KEY_FILE}"

log "证书更新完成"
SCRIPT_EOF

    # 替换脚本中的占位符
    sed -i "s|__CERT_URL__|${cert_url}|g" "$download_script"
    sed -i "s|__KEY_URL__|${key_url}|g" "$download_script"
    sed -i "s|__CERT_REMARK__|${cert_remark}|g" "$download_script"
    
    # 设置脚本可执行权限
    chmod +x "$download_script"
    
    # 先设置北京时区
    set_beijing_timezone
    
    # 每天凌晨 3:00 执行下载更新
    local cron_cmd="0 3 * * * $download_script >/dev/null 2>&1"
    
    # 检查是否已存在证书下载任务
    if crontab -l 2>/dev/null | grep -q "update_cert.sh"; then
        echo -e "${yellow}检测到旧的证书下载任务，正在更新...${plain}"
        crontab -l 2>/dev/null | grep -v "update_cert.sh" | crontab -
    fi
    
    # 添加新的 cron 任务
    (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
    
    if [[ $? -eq 0 ]]; then
        echo -e "${green}已设置每日凌昨3:00（北京时间）自动下载更新证书${plain}"
        echo -e "${green}更新脚本: $download_script${plain}"
        echo -e "${green}更新日志: /var/log/bxtest_cert_update.log${plain}"
    else
        echo -e "${red}设置自动下载失败，请手动添加 cron 任务${plain}"
        echo -e "${yellow}cron 命令: $cron_cmd${plain}"
    fi
}

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -rp "$1 [默认$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -rp "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "是否重启BXtest" "y"
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            restart
        else
            restart 0
        fi
    elif [[ $# == 0 ]]; then
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}按回车返回主菜单: ${plain}" && read temp
    show_menu
}

install_BXtest() {
    bash <(curl -Ls https://raw.githubusercontent.com/Kopw/BXtest-script/master/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    if [[ $# == 0 ]]; then
        echo && echo -n -e "输入指定版本(默认最新版): " && read version
    else
        version=$2
    fi

    local arch=$(uname -m)
    if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
        arch="64"
    elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
        arch="arm64-v8a"
    elif [[ $arch == "s390x" ]]; then
        arch="s390x"
    else
        arch="64"
        echo -e "${yellow}检测架构失败，使用默认架构: ${arch}${plain}"
    fi

    if [[ -z "$version" ]]; then
        if ! detect_latest_BXtest_version; then
            echo -e "${red}检测 BXtest 最新版本失败，已尝试内置镜像和手动镜像，仍未能获取版本；请稍后再试，或手动指定 BXtest 版本${plain}"
            if [[ $# == 0 ]]; then
                before_show_menu
            fi
            return 1
        fi
        version="$BXTEST_RESOLVED_VERSION"
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d /tmp/bxtest-update.XXXXXX)
    local zip_path="${tmp_dir}/BXtest-linux.zip"

    if ! download_BXtest_release "$version" "$zip_path" "$arch"; then
        rm -rf "$tmp_dir"
        echo -e "${red}下载 BXtest ${version} 失败，请检查版本号、网络连接或 GitHub 镜像站点${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    fi

    unzip -o "$zip_path" -d "$tmp_dir" >/dev/null 2>&1
    if [[ $? -ne 0 || ! -f "${tmp_dir}/BXtest" ]]; then
        rm -rf "$tmp_dir"
        echo -e "${red}解压 BXtest ${version} 失败，未找到 BXtest 可执行文件${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    fi

    local binary_tmp="/usr/local/BXtest/BXtest.tmp.$$"
    cp "${tmp_dir}/BXtest" "$binary_tmp"
    if [[ $? -ne 0 ]]; then
        rm -rf "$tmp_dir"
        echo -e "${red}替换 BXtest 程序失败${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    fi
    chmod +x "$binary_tmp"
    mv -f "$binary_tmp" /usr/local/BXtest/BXtest
    if [[ $? -ne 0 ]]; then
        rm -f "$binary_tmp"
        rm -rf "$tmp_dir"
        echo -e "${red}替换 BXtest 程序失败${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    fi
    rm -rf "$tmp_dir"

    restart 0
    echo -e "${green}更新完成，仅替换了 BXtest 程序并重启服务，请使用 BXtest log 查看运行日志${plain}"

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

config() {
    echo "BXtest在修改配置后会自动尝试重启"
    vi /etc/BXtest/config.json
    sleep 2
    restart
    check_status
    case $? in
        0)
            echo -e "BXtest状态: ${green}已运行${plain}"
            ;;
        1)
            echo -e "检测到您未启动BXtest或BXtest自动重启失败，是否查看日志？[Y/n]" && echo
            read -e -rp "(默认: y):" yn
            [[ -z ${yn} ]] && yn="y"
            if [[ ${yn} == [Yy] ]]; then
               show_log
            fi
            ;;
        2)
            echo -e "BXtest状态: ${red}未安装${plain}"
    esac
}

uninstall() {
    confirm "确定要卸载 BXtest 吗?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    local keep_cert_assets=true
    local cert_backup_dir=""
    confirm "是否同时卸载 acme.sh 并清理已保存的证书和自动更新任务？" "n"
    if [[ $? == 0 ]]; then
        keep_cert_assets=false
    elif [[ -d /etc/BXtest ]]; then
        cert_backup_dir=$(mktemp -d /tmp/bxtest-cert-backup.XXXXXX)
        find /etc/BXtest -maxdepth 1 \( -name "*.cer" -o -name "*.key" -o -name "*.pem" -o -name "update_cert.sh" \) -exec cp -a {} "$cert_backup_dir"/ \; 2>/dev/null
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        service BXtest stop
        rc-update del BXtest
        rm /etc/init.d/BXtest -f
    else
        systemctl stop BXtest
        systemctl disable BXtest
        rm /etc/systemd/system/BXtest.service -f
        systemctl daemon-reload
        systemctl reset-failed
    fi
    rm /etc/BXtest/ -rf
    rm /usr/local/BXtest/ -rf

    if [[ "$keep_cert_assets" == true ]]; then
        mkdir -p /etc/BXtest
        if [[ -n "$cert_backup_dir" && -d "$cert_backup_dir" ]]; then
            cp -a "$cert_backup_dir"/. /etc/BXtest/ 2>/dev/null
            rm -rf "$cert_backup_dir"
        fi
        chmod 600 /etc/BXtest/*.key 2>/dev/null
        chmod 644 /etc/BXtest/*.cer /etc/BXtest/*.pem 2>/dev/null
        [[ -f /etc/BXtest/update_cert.sh ]] && chmod +x /etc/BXtest/update_cert.sh
        echo -e "${green}已保留 /etc/BXtest 下的证书文件、更新脚本以及现有 cron 自动更新任务${plain}"
    else
        rm -rf "$cert_backup_dir" 2>/dev/null
        if crontab -l 2>/dev/null | grep -Eq "acme.sh|update_cert.sh"; then
            crontab -l 2>/dev/null | grep -Ev "acme.sh|update_cert.sh" | crontab -
            echo -e "${green}已清理证书自动更新任务${plain}"
        fi
        if [[ -f ~/.acme.sh/acme.sh ]]; then
            ~/.acme.sh/acme.sh --uninstall >/dev/null 2>&1
            rm -rf ~/.acme.sh
            echo -e "${green}已卸载 acme.sh${plain}"
        fi
    fi

    echo ""
    echo -e "卸载成功，如果你想删除此脚本，则退出脚本后运行 ${green}rm /usr/bin/BXtest -f${plain} 进行删除"
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        echo -e "${green}BXtest已运行，无需再次启动，如需重启请选择重启${plain}"
    else
        if [[ x"${release}" == x"alpine" ]]; then
            service BXtest start
        else
            systemctl start BXtest
        fi
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            echo -e "${green}BXtest 启动成功，请使用 BXtest log 查看运行日志${plain}"
        else
            echo -e "${red}BXtest可能启动失败，请稍后使用 BXtest log 查看日志信息${plain}"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    if [[ x"${release}" == x"alpine" ]]; then
        service BXtest stop
    else
        systemctl stop BXtest
    fi
    sleep 2
    check_status
    if [[ $? == 1 ]]; then
        echo -e "${green}BXtest 停止成功${plain}"
    else
        echo -e "${red}BXtest停止失败，可能是因为停止时间超过了两秒，请稍后查看日志信息${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    if [[ x"${release}" == x"alpine" ]]; then
        service BXtest restart
    else
        systemctl restart BXtest
    fi
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        echo -e "${green}BXtest 重启成功，请使用 BXtest log 查看运行日志${plain}"
    else
        echo -e "${red}BXtest可能启动失败，请稍后使用 BXtest log 查看日志信息${plain}"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    if [[ x"${release}" == x"alpine" ]]; then
        service BXtest status
    else
        systemctl status BXtest --no-pager -l
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update add BXtest
    else
        systemctl enable BXtest
    fi
    if [[ $? == 0 ]]; then
        echo -e "${green}BXtest 设置开机自启成功${plain}"
    else
        echo -e "${red}BXtest 设置开机自启失败${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update del BXtest
    else
        systemctl disable BXtest
    fi
    if [[ $? == 0 ]]; then
        echo -e "${green}BXtest 取消开机自启成功${plain}"
    else
        echo -e "${red}BXtest 取消开机自启失败${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    if [[ x"${release}" == x"alpine" ]]; then
        echo -e "${red}alpine系统暂不支持日志查看${plain}\n" && exit 1
    else
        journalctl -u BXtest.service -e --no-pager -f
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

install_smartdns_package() {
    if [[ x"${release}" == x"alpine" ]] && [[ -x /usr/sbin/smartdns ]]; then
        if ! /usr/sbin/smartdns -v >/dev/null 2>&1; then
            echo -e "${yellow}检测到现有 smartdns 无法执行，重新下载 Alpine 二进制文件...${plain}"
            install_smartdns_alpine_binary
            return $?
        fi
        write_smartdns_alpine_service "/usr/sbin/smartdns" || return 1
        echo -e "${green}检测到 smartdns 已安装，跳过安装步骤${plain}"
        return 0
    fi

    if command -v smartdns >/dev/null 2>&1; then
        if [[ x"${release}" == x"alpine" ]]; then
            if ! smartdns -v >/dev/null 2>&1; then
                echo -e "${yellow}检测到现有 smartdns 无法执行，重新下载 Alpine 二进制文件...${plain}"
                install_smartdns_alpine_binary
                return $?
            fi
            write_smartdns_alpine_service "$(command -v smartdns)" || return 1
        fi
        echo -e "${green}检测到 smartdns 已安装，跳过安装步骤${plain}"
        return 0
    fi

    echo -e "${yellow}正在安装 smartdns...${plain}"
    case "$release" in
        "debian"|"ubuntu")
            apt-get update -y >/dev/null 2>&1
            apt-get install -y smartdns >/dev/null 2>&1 && return 0
            ;;
        "centos")
            yum install -y smartdns >/dev/null 2>&1 && return 0
            ;;
        "alpine")
            install_smartdns_alpine_binary
            return $?
            ;;
        "arch")
            pacman -Sy --noconfirm >/dev/null 2>&1
            pacman -S --noconfirm --needed smartdns >/dev/null 2>&1 && return 0
            ;;
    esac

    install_smartdns_from_release
}

write_smartdns_alpine_service() {
    local smartdns_bin="$1"
    [[ -z "$smartdns_bin" ]] && smartdns_bin="/usr/sbin/smartdns"

    mkdir -p /etc/init.d /etc/default
    if [[ ! -f /etc/default/smartdns ]]; then
        cat <<'EOF' > /etc/default/smartdns
SMART_DNS_OPTS=""
EOF
    fi

    cat > /etc/init.d/smartdns <<EOF
#!/sbin/openrc-run

name="smartdns"
description="SmartDNS local DNS server"
command="${smartdns_bin}"
pidfile="/run/smartdns.pid"
config="/etc/smartdns/smartdns.conf"

depend() {
    need net
    after firewall
}

load_opts() {
    [ -f /etc/default/smartdns ] && . /etc/default/smartdns
    SMART_DNS_OPTS=\${SMART_DNS_OPTS:-\${SMARTDNS_OPTS:-}}
}

checkconfig() {
    if [ ! -x "\${command}" ]; then
        eerror "smartdns binary not found or not executable: \${command}"
        return 1
    fi
    if [ ! -r "\${config}" ]; then
        eerror "smartdns config not found or not readable: \${config}"
        return 1
    fi
    checkpath --directory --mode 0755 /run
    checkpath --directory --mode 0755 /etc/smartdns
    checkpath --directory --mode 0755 /var/cache/smartdns
    checkpath --directory --mode 0755 /var/log/smartdns
}

start() {
    load_opts
    checkconfig || return 1
    ebegin "Starting smartdns"
    rm -f "\${pidfile}"
    \${command} -p "\${pidfile}" -c "\${config}" \${SMART_DNS_OPTS}
    ret=\$?
    if [ \$ret -eq 0 ]; then
        i=0
        while [ \$i -lt 20 ]; do
            if [ -s "\${pidfile}" ]; then
                pid="\$(cat "\${pidfile}" 2>/dev/null)"
                if [ -n "\${pid}" ] && kill -0 "\${pid}" 2>/dev/null; then
                    eend 0
                    return 0
                fi
            fi
            sleep .5
            i=\$((i + 1))
        done
        ret=1
    fi
    eend \$ret
    return \$ret
}

stop() {
    ebegin "Stopping smartdns"
    if [ ! -f "\${pidfile}" ]; then
        eend 0
        return 0
    fi
    pid="\$(cat "\${pidfile}" 2>/dev/null)"
    if [ -z "\${pid}" ] || ! kill -0 "\${pid}" 2>/dev/null; then
        rm -f "\${pidfile}"
        eend 0
        return 0
    fi
    kill -TERM "\${pid}" 2>/dev/null
    ret=\$?
    i=0
    while [ \$i -lt 30 ]; do
        kill -0 "\${pid}" 2>/dev/null || break
        sleep .5
        i=\$((i + 1))
    done
    if kill -0 "\${pid}" 2>/dev/null; then
        kill -KILL "\${pid}" 2>/dev/null
    fi
    rm -f "\${pidfile}"
    eend \$ret
    return \$ret
}

status() {
    pid="\$(cat "\${pidfile}" 2>/dev/null)"
    if [ -n "\${pid}" ] && kill -0 "\${pid}" 2>/dev/null; then
        echo "smartdns is running (pid \${pid})"
        return 0
    fi
    echo "smartdns is stopped"
    return 1
}
EOF
    chmod +x /etc/init.d/smartdns
    rc-update add smartdns default >/dev/null 2>&1
}

install_smartdns_from_release() {
    local arch smartdns_arch api_url release_json download_url tmp_dir pkg_path install_result

    echo -e "${yellow}系统软件源未能安装 smartdns，尝试从官方 release 安装...${plain}"
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) smartdns_arch="x86_64" ;;
        i386|i686) smartdns_arch="x86" ;;
        aarch64|arm64) smartdns_arch="aarch64" ;;
        armv7l|armv6l|arm) smartdns_arch="arm" ;;
        mips) smartdns_arch="mips" ;;
        mipsel) smartdns_arch="mipsel" ;;
        *)
            echo -e "${red}暂不支持当前架构安装 smartdns: ${arch}${plain}"
            return 1
            ;;
    esac

    api_url="https://api.github.com/repos/pymumu/smartdns/releases/latest"
    release_json=$(curl -fsSL "$api_url" 2>/dev/null)
    if [[ -z "$release_json" ]]; then
        echo -e "${red}获取 smartdns 最新 release 信息失败${plain}"
        return 1
    fi

    download_url=$(echo "$release_json" | grep -oE "https://[^\"]*smartdns\.[^\"]*\.${smartdns_arch}-linux-all\.tar\.gz" | head -n 1)
    if [[ -z "$download_url" ]]; then
        echo -e "${red}未找到当前架构的 smartdns 安装包: ${smartdns_arch}${plain}"
        return 1
    fi

    tmp_dir=$(mktemp -d /tmp/smartdns-install.XXXXXX)
    pkg_path="${tmp_dir}/smartdns.tar.gz"
    if ! curl -fL "$download_url" -o "$pkg_path"; then
        rm -rf "$tmp_dir"
        echo -e "${red}下载 smartdns 安装包失败${plain}"
        return 1
    fi

    if ! tar -xzf "$pkg_path" -C "$tmp_dir"; then
        rm -rf "$tmp_dir"
        echo -e "${red}解压 smartdns 安装包失败${plain}"
        return 1
    fi

    if [[ ! -x "${tmp_dir}/smartdns/install" ]]; then
        rm -rf "$tmp_dir"
        echo -e "${red}smartdns 安装包缺少 install 脚本${plain}"
        return 1
    fi

    (cd "${tmp_dir}/smartdns" && sh ./install -i >/dev/null 2>&1)
    install_result=$?
    rm -rf "$tmp_dir"
    if [[ $install_result -ne 0 ]]; then
        echo -e "${red}smartdns 官方安装脚本执行失败${plain}"
        return 1
    fi

    return 0
}

install_smartdns_alpine_binary() {
    local arch smartdns_arch api_url release_json download_url tmp_path

    echo -e "${yellow}Alpine 系统直接下载 smartdns 二进制文件安装...${plain}"
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) smartdns_arch="x86_64" ;;
        i386|i686) smartdns_arch="x86" ;;
        aarch64|arm64) smartdns_arch="aarch64" ;;
        armv7l|armv6l|arm) smartdns_arch="arm" ;;
        mips) smartdns_arch="mips" ;;
        mipsel) smartdns_arch="mipsel" ;;
        *)
            echo -e "${red}暂不支持当前架构安装 smartdns: ${arch}${plain}"
            return 1
            ;;
    esac

    api_url="https://api.github.com/repos/pymumu/smartdns/releases/latest"
    release_json=$(curl -fsSL "$api_url" 2>/dev/null)
    if [[ -z "$release_json" ]]; then
        echo -e "${red}获取 smartdns 最新 release 信息失败${plain}"
        return 1
    fi

    download_url=$(echo "$release_json" | grep '"browser_download_url"' | grep "/smartdns-${smartdns_arch}\"" | sed -E 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -n 1)
    if [[ -z "$download_url" ]]; then
        echo -e "${red}未找到当前架构的 smartdns 二进制文件: smartdns-${smartdns_arch}${plain}"
        return 1
    fi

    mkdir -p /usr/sbin /etc/smartdns /etc/default
    tmp_path=$(mktemp /tmp/smartdns-bin.XXXXXX)
    echo -e "${yellow}下载 smartdns 二进制文件: ${download_url}${plain}"
    if ! curl -fL "$download_url" -o "$tmp_path"; then
        rm -f "$tmp_path"
        echo -e "${red}下载 smartdns 二进制文件失败${plain}"
        return 1
    fi
    command cp "$tmp_path" /usr/sbin/smartdns && command chmod 0755 /usr/sbin/smartdns
    local install_result=$?
    rm -f "$tmp_path"
    if [[ $install_result -ne 0 ]]; then
        echo -e "${red}安装 smartdns 二进制文件失败${plain}"
        return 1
    fi
    if [[ ! -x /usr/sbin/smartdns ]]; then
        echo -e "${red}/usr/sbin/smartdns 未安装成功或不可执行${plain}"
        ls -l /usr/sbin/smartdns 2>/dev/null || true
        return 1
    fi
    if ! /usr/sbin/smartdns -v >/dev/null 2>&1; then
        echo -e "${red}/usr/sbin/smartdns 无法执行，可能下载到了错误文件或系统架构不匹配${plain}"
        ls -l /usr/sbin/smartdns 2>/dev/null || true
        file /usr/sbin/smartdns 2>/dev/null || true
        /usr/sbin/smartdns -v 2>&1 | head -n 5 || true
        return 1
    fi

    write_smartdns_alpine_service "/usr/sbin/smartdns"
}

normalize_ai_dns_server() {
    local ai_dns_server="$1"
    ai_dns_server=$(echo "$ai_dns_server" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
    ai_dns_server="${ai_dns_server#udp://}"
    ai_dns_server="${ai_dns_server#tcp://}"
    ai_dns_server="${ai_dns_server%/}"

    if [[ -z "$ai_dns_server" ]]; then
        return 1
    fi
    if [[ "$ai_dns_server" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]+)?$ ]]; then
        echo "$ai_dns_server"
        return 0
    fi
    if [[ "$ai_dns_server" =~ ^\[[0-9A-Fa-f:]+\](:[0-9]+)?$ ]]; then
        echo "$ai_dns_server"
        return 0
    fi
    if [[ "$ai_dns_server" =~ ^[0-9A-Fa-f:]+$ && "$ai_dns_server" == *:* ]]; then
        echo "[${ai_dns_server}]"
        return 0
    fi

    return 1
}

prompt_ai_dns_server() {
    local ai_dns_server="$1"
    local normalized_ai_dns_server

    if [[ -n "$ai_dns_server" ]]; then
        normalized_ai_dns_server=$(normalize_ai_dns_server "$ai_dns_server")
        if [[ -n "$normalized_ai_dns_server" ]]; then
            echo "$normalized_ai_dns_server"
            return 0
        fi
        echo -e "${red}AI 分流 DNS 地址格式不正确: ${ai_dns_server}${plain}" >&2
        return 1
    fi

    while true; do
        read -rp "请输入非中国大陆 AI 服务分流 DNS 服务器 IP（例如 8.8.8.8，可带端口）: " ai_dns_server
        normalized_ai_dns_server=$(normalize_ai_dns_server "$ai_dns_server")
        if [[ -n "$normalized_ai_dns_server" ]]; then
            echo "$normalized_ai_dns_server"
            return 0
        fi
        echo -e "${red}请输入有效的 IPv4/IPv6 地址，可选端口，例如 8.8.8.8 或 8.8.8.8:53${plain}"
    done
}

prompt_enable_ai_dns_routing() {
    if [[ -n "$1" ]]; then
        return 0
    fi

    confirm "是否启用非中国大陆 AI 服务 DNS 分流" "n"
}

write_smartdns_config() {
    local ai_dns_server="$1"
    mkdir -p /etc/smartdns /var/cache/smartdns /var/log/smartdns
    if [[ -f /etc/smartdns/smartdns.conf ]]; then
        cp -a /etc/smartdns/smartdns.conf "/etc/smartdns/smartdns.conf.bak.$(date +%Y%m%d%H%M%S)"
    fi

    cat > /etc/smartdns/smartdns.conf <<EOF
########################################
# SmartDNS Config
# - Listen: 127.0.0.1:53
# - Upstream: Cloudflare & Google (IPv4 + IPv6 DoT/DoH)
########################################

########## Listen ##########
bind 127.0.0.1:53
bind-tcp 127.0.0.1:53

########## Disable IPv6 resolving to Client ##########
# 注意：这里配置的是“不向客户端返回 AAAA 记录”，防止客户端连接慢。
# 但 SmartDNS 服务端本身依然可以使用 IPv6 上游去查询数据。
force-AAAA-SOA yes

########## Cache / Log ##########
cache-size 8192
cache-persist yes
cache-file /var/cache/smartdns/smartdns.cache

log-level notice
log-file /var/log/smartdns/smartdns.log
log-size 2M
log-num 8

########## Speed Check & Response ##########
# 测速模式：ping + TCP 443
speed-check-mode tcp:443,ping
# 响应模式：返回测速最快的 IP
response-mode fastest-ip
# 最多返回 2 个 IP
max-reply-ip-num 2

########################################
# Upstream DNS (DoT / DoH)
########################################

# === Cloudflare (IPv4 DoT) ===
server-tls 1.1.1.1:853 -host-name one.one.one.one -tls-host-verify one.one.one.one
server-tls 1.0.0.1:853 -host-name one.one.one.one -tls-host-verify one.one.one.one

# === Cloudflare (IPv6 DoT) ===
server-tls [2606:4700:4700::1111]:853 -host-name one.one.one.one -tls-host-verify one.one.one.one
server-tls [2606:4700:4700::1001]:853 -host-name one.one.one.one -tls-host-verify one.one.one.one

# === Google (IPv4 DoH - 备选使用DoH) ===
server-https https://dns.google/dns-query -host-ip 8.8.8.8 -http-host dns.google -tls-host-verify dns.google
server-https https://dns.google/dns-query -host-ip 8.8.4.4 -http-host dns.google -tls-host-verify dns.google

# === Google (IPv6 DoT) ===
server-tls [2001:4860:4860::8888]:853 -host-name dns.google -tls-host-verify dns.google
server-tls [2001:4860:4860::8844]:853 -host-name dns.google -tls-host-verify dns.google
EOF

    if [[ -n "$ai_dns_server" ]]; then
        cat >> /etc/smartdns/smartdns.conf <<EOF

########################################
# AI DNS Routing
# - Non-China AI services use the ai group only
# - Domain set file is updated by /usr/local/BXtest/update_smartdns_ai_domains.sh
# - Domain list source:
#   https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-ai-!cn.list
########################################

domain-set -name ai_noncn -type list -file /etc/smartdns/domain-set/ai_noncn.conf
nameserver /domain-set:ai_noncn/ai
server ${ai_dns_server} -group ai -exclude-default-group
EOF
    fi
}

write_smartdns_ai_update_script() {
    local update_script="/usr/local/BXtest/update_smartdns_ai_domains.sh"

    mkdir -p /usr/local/BXtest /etc/smartdns/domain-set
    cat <<'EOF' > "$update_script"
#!/bin/sh

AI_DOMAIN_URL="https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-ai-!cn.list"
AI_DOMAIN_FILE="/etc/smartdns/domain-set/ai_noncn.conf"
TMP_FILE="$(mktemp /tmp/smartdns-ai-domains.XXXXXX)"
TMP_OUTPUT="$(mktemp /tmp/smartdns-ai-domains-output.XXXXXX)"

cleanup() {
    rm -f "$TMP_FILE" "$TMP_OUTPUT"
}
trap cleanup EXIT

mkdir -p /etc/smartdns/domain-set

if ! curl -fsSL "$AI_DOMAIN_URL" -o "$TMP_FILE"; then
    echo "download AI domain list failed" >&2
    exit 1
fi

if ! python3 - "$TMP_FILE" "$TMP_OUTPUT" <<'PY'
from pathlib import Path
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
domains = []
seen = set()

for raw_line in src.read_text(encoding="utf-8", errors="ignore").splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#"):
        continue
    if line.startswith("+."):
        line = line[2:]
    elif line.startswith("."):
        line = line[1:]
    elif line.startswith("domain:"):
        line = line.split(":", 1)[1].strip()
    elif line.startswith("full:"):
        line = line.split(":", 1)[1].strip()
    elif line.startswith("regexp:") or line.startswith("keyword:"):
        continue
    line = line.strip().lower().rstrip(".")
    if not line or "/" in line or ":" in line:
        continue
    if line not in seen:
        seen.add(line)
        domains.append(line)

if not domains:
    raise SystemExit("empty ai domain set")

dst.write_text("\n".join(domains) + "\n", encoding="utf-8")
PY
then
    echo "convert AI domain list failed" >&2
    exit 1
fi

command cp "$TMP_OUTPUT" "$AI_DOMAIN_FILE" && command chmod 0644 "$AI_DOMAIN_FILE"
exit $?
EOF
    chmod +x "$update_script"
}

write_smartdns_ai_domain_fallback_set() {
    local ai_domain_file="/etc/smartdns/domain-set/ai_noncn.conf"
    mkdir -p /etc/smartdns/domain-set
    cat <<'EOF' > "$ai_domain_file"
openai.com
chatgpt.com
oaistatic.com
oaiusercontent.com
openaiapi-site.azureedge.net
anthropic.com
claude.ai
poe.com
perplexity.ai
pplx.ai
gemini.google.com
ai.google.dev
makersuite.google.com
notebooklm.google.com
cohere.ai
cohere.com
clipdrop.co
jasper.ai
elevenlabs.io
huggingface.co
replicate.com
midjourney.com
cursor.com
cursor.sh
githubcopilot.com
copilot-proxy.githubusercontent.com
EOF
}

write_smartdns_ai_domain_set() {
    local update_script="/usr/local/BXtest/update_smartdns_ai_domains.sh"

    write_smartdns_ai_update_script
    if "$update_script"; then
        return 0
    fi

    if [[ -f /etc/smartdns/domain-set/ai_noncn.conf ]]; then
        echo -e "${yellow}更新 AI 域名列表失败，保留现有规则文件${plain}"
        return 0
    fi

    echo -e "${yellow}下载 AI 域名列表失败，写入内置备用列表${plain}"
    write_smartdns_ai_domain_fallback_set
}

setup_smartdns_ai_domain_update_cron() {
    local update_script="/usr/local/BXtest/update_smartdns_ai_domains.sh"
    local cron_cmd="17 4 * * * ${update_script} >/dev/null 2>&1"

    case "$release" in
        "debian"|"ubuntu")
            apt-get update -y >/dev/null 2>&1
            apt-get install -y cron >/dev/null 2>&1
            systemctl enable cron >/dev/null 2>&1
            systemctl start cron >/dev/null 2>&1
            ;;
        "centos")
            yum install -y cronie >/dev/null 2>&1
            systemctl enable crond >/dev/null 2>&1
            systemctl start crond >/dev/null 2>&1
            ;;
        "alpine")
            apk update >/dev/null 2>&1
            apk add dcron >/dev/null 2>&1
            rc-update add dcron default >/dev/null 2>&1
            rc-service dcron start >/dev/null 2>&1
            ;;
        "arch")
            pacman -Sy --noconfirm >/dev/null 2>&1
            pacman -S --noconfirm --needed cronie >/dev/null 2>&1
            systemctl enable cronie >/dev/null 2>&1
            systemctl start cronie >/dev/null 2>&1
            ;;
    esac

    if crontab -l 2>/dev/null | grep -q "$update_script"; then
        crontab -l 2>/dev/null | grep -v "$update_script" | crontab -
    fi
    (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
    if [[ $? -ne 0 ]]; then
        echo -e "${yellow}设置 AI 分流规则自动更新任务失败，请手动添加 cron: ${cron_cmd}${plain}"
        return 1
    fi
    return 0
}

update_bxtest_dns_to_smartdns() {
    mkdir -p /etc/BXtest

    if [[ -f /etc/BXtest/dns.json ]]; then
        cp -a /etc/BXtest/dns.json "/etc/BXtest/dns.json.bak.$(date +%Y%m%d%H%M%S)"
    fi
    if ! python3 - <<'PY'
import json
from pathlib import Path

path = Path("/etc/BXtest/dns.json")
data = {}
if path.exists():
    try:
        data = json.loads(path.read_text())
    except Exception:
        data = {}
data["servers"] = ["tcp://127.0.0.1"]
data["tag"] = data.get("tag") or "dns_inbound"
path.write_text(json.dumps(data, indent=4, ensure_ascii=False) + "\n")
PY
    then
        echo -e "${red}更新 /etc/BXtest/dns.json 失败${plain}"
        return 1
    fi

    if [[ -f /etc/BXtest/sing_origin.json ]]; then
        cp -a /etc/BXtest/sing_origin.json "/etc/BXtest/sing_origin.json.bak.$(date +%Y%m%d%H%M%S)"
        if ! python3 - <<'PY'
import json
from pathlib import Path

path = Path("/etc/BXtest/sing_origin.json")
data = json.loads(path.read_text())
dns = data.setdefault("dns", {})
servers = dns.setdefault("servers", [])

server_tag = "smartdns"
replacement = {
    "tag": "cf",
    "address": "tcp://127.0.0.1"
}

new_servers = []
replaced = False
for server in servers:
    if not isinstance(server, dict):
        new_servers.append(server)
        continue
    tag = server.get("tag")
    if tag == "ai_dns":
        continue
    if tag in ("cf", "smartdns"):
        if not replaced:
            new_servers.append(replacement)
            replaced = True
        continue
    new_servers.append(server)
if not replaced:
    new_servers.insert(0, replacement)
dns["servers"] = new_servers

rules = dns.get("rules")
if isinstance(rules, list):
    dns["rules"] = [
        rule for rule in rules
        if not (isinstance(rule, dict) and rule.get("server") == "ai_dns")
    ]
    if not dns["rules"]:
        dns.pop("rules", None)
dns["final"] = "cf"
dns["strategy"] = "ipv4_only"

for outbound in data.get("outbounds", []):
    if isinstance(outbound, dict):
        resolver = outbound.get("domain_resolver")
        if isinstance(resolver, dict) and resolver.get("server") in ("cf", "smartdns", None):
            resolver["server"] = "cf"

route = data.get("route")
if isinstance(route, dict):
    route_rules = route.get("rules")
    if isinstance(route_rules, list):
        route["rules"] = [
            rule for rule in route_rules
            if not (isinstance(rule, dict) and rule.get("server") == "ai_dns")
        ]
    rule_sets = route.get("rule_set")
    if isinstance(rule_sets, list):
        route["rule_set"] = [
            rule_set for rule_set in rule_sets
            if not (isinstance(rule_set, dict) and rule_set.get("tag") == "geosite-category-ai-!cn")
        ]
        if not route["rule_set"]:
            route.pop("rule_set", None)

path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
PY
        then
            echo -e "${red}更新 /etc/BXtest/sing_origin.json 失败${plain}"
            return 1
        fi
    fi

    if [[ -f /etc/BXtest/hy2config.yaml ]]; then
        cp -a /etc/BXtest/hy2config.yaml "/etc/BXtest/hy2config.yaml.bak.$(date +%Y%m%d%H%M%S)"
        if ! python3 - <<'PY'
from pathlib import Path

path = Path("/etc/BXtest/hy2config.yaml")
lines = path.read_text().splitlines()
out = []
i = 0
n = len(lines)
inserted = False

resolver_block = [
    "resolver:",
    "  type: tcp",
    "  ipv4Only: true",
    "  tcp:",
    "    addr: 127.0.0.1:53",
]

while i < n:
    line = lines[i]
    if line.startswith("resolver:"):
        out.extend(resolver_block)
        inserted = True
        i += 1
        while i < n:
            current = lines[i]
            stripped = current.strip()
            if stripped and not current.startswith((" ", "\t")):
                break
            i += 1
        continue
    out.append(line)
    i += 1

if not inserted:
    if out and out[-1].strip():
        out.append("")
    out.extend(resolver_block)

path.write_text("\n".join(out) + "\n")
PY
        then
            echo -e "${red}更新 /etc/BXtest/hy2config.yaml 失败${plain}"
            return 1
        fi
    fi
}

restart_smartdns_service() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update add smartdns default >/dev/null 2>&1
        rc-service smartdns restart || service smartdns restart || {
            rc-service smartdns stop || service smartdns stop
            rc-service smartdns start || service smartdns start
        }
        sleep 1
        rc-service smartdns status || service smartdns status
        return $?
    fi

    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable smartdns >/dev/null 2>&1
    systemctl restart smartdns >/dev/null 2>&1
    sleep 1
    systemctl is-active --quiet smartdns
}

show_smartdns_failure_diagnostics() {
    local smartdns_bin=""
    echo -e "${yellow}smartdns 启动失败诊断信息:${plain}"
    if command -v smartdns >/dev/null 2>&1; then
        smartdns_bin="$(command -v smartdns)"
    elif [[ -x /usr/sbin/smartdns ]]; then
        smartdns_bin="/usr/sbin/smartdns"
    elif [[ -x /usr/local/bin/smartdns ]]; then
        smartdns_bin="/usr/local/bin/smartdns"
    elif [[ -x /usr/local/sbin/smartdns ]]; then
        smartdns_bin="/usr/local/sbin/smartdns"
    fi
    echo -e "${yellow}smartdns 二进制文件:${plain}"
    ls -l /usr/sbin/smartdns /usr/local/bin/smartdns /usr/local/sbin/smartdns 2>/dev/null || true
    if [[ -n "$smartdns_bin" ]]; then
        echo -e "${yellow}smartdns 版本:${plain}"
        "$smartdns_bin" -v 2>&1 | head -n 3 || true
        echo -e "${yellow}前台启动检查:${plain}"
        timeout 3 "$smartdns_bin" -f -p - -c /etc/smartdns/smartdns.conf 2>&1 | tail -n 20 || true
    else
        echo -e "${red}未找到可执行的 smartdns 二进制文件${plain}"
    fi
    if [[ -f /etc/init.d/smartdns ]]; then
        echo -e "${yellow}/etc/init.d/smartdns 状态:${plain}"
        ls -l /etc/init.d/smartdns || true
    fi
    if [[ -f /var/log/smartdns/smartdns.log ]]; then
        echo -e "${yellow}/var/log/smartdns/smartdns.log 最近日志:${plain}"
        tail -n 30 /var/log/smartdns/smartdns.log || true
    fi
    if command -v ss >/dev/null 2>&1; then
        echo -e "${yellow}53 端口占用:${plain}"
        ss -lntup 2>/dev/null | grep -E '(:53[[:space:]]|:53$)' || true
    elif command -v netstat >/dev/null 2>&1; then
        echo -e "${yellow}53 端口占用:${plain}"
        netstat -lntup 2>/dev/null | grep -E '(:53[[:space:]]|:53$)' || true
    fi
}

install_smartdns() {
    if [[ ! -d /etc/BXtest ]]; then
        echo -e "${red}请先安装 BXtest，再使用 smartdns 配置功能${plain}"
        [[ $# == 0 ]] && before_show_menu
        return 1
    fi

    local ai_dns_server=""
    local enable_ai_dns=false
    if prompt_enable_ai_dns_routing "$2"; then
        enable_ai_dns=true
        ai_dns_server=$(prompt_ai_dns_server "$2")
        if [[ -z "$ai_dns_server" ]]; then
            [[ $# == 0 ]] && before_show_menu
            return 1
        fi
    fi

    if ! command -v python3 >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1 || { [[ x"${release}" == x"alpine" ]] && [[ ! -f /etc/ssl/certs/ca-certificates.crt ]]; }; then
        echo -e "${yellow}正在安装 curl/python3 以更新配置文件...${plain}"
        case "$release" in
            "debian"|"ubuntu")
                apt-get update -y >/dev/null 2>&1
                apt-get install -y curl python3 >/dev/null 2>&1
                ;;
            "centos")
                yum install -y curl python3 >/dev/null 2>&1
                ;;
            "alpine")
                apk update >/dev/null 2>&1
                if ! apk add curl python3 ca-certificates >/dev/null 2>&1; then
                    echo -e "${red}安装 curl/python3/ca-certificates 失败，无法继续安装 smartdns${plain}"
                    [[ $# == 0 ]] && before_show_menu
                    return 1
                fi
                update-ca-certificates >/dev/null 2>&1
                ;;
            "arch")
                pacman -Sy --noconfirm >/dev/null 2>&1
                pacman -S --noconfirm --needed curl python >/dev/null 2>&1
                ;;
        esac
    fi

    if ! command -v python3 >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
        echo -e "${red}未检测到 curl/python3，无法安全更新 BXtest 配置文件${plain}"
        [[ $# == 0 ]] && before_show_menu
        return 1
    fi

    if ! install_smartdns_package; then
        echo -e "${red}smartdns 安装失败${plain}"
        [[ $# == 0 ]] && before_show_menu
        return 1
    fi

    write_smartdns_config "$ai_dns_server"
    if [[ "$enable_ai_dns" == true ]]; then
        if ! write_smartdns_ai_domain_set; then
            echo -e "${red}写入 SmartDNS AI 分流域名列表失败${plain}"
            [[ $# == 0 ]] && before_show_menu
            return 1
        fi
        setup_smartdns_ai_domain_update_cron
    else
        if crontab -l 2>/dev/null | grep -q "/usr/local/BXtest/update_smartdns_ai_domains.sh"; then
            crontab -l 2>/dev/null | grep -v "/usr/local/BXtest/update_smartdns_ai_domains.sh" | crontab -
        fi
        rm -f /usr/local/BXtest/update_smartdns_ai_domains.sh
        rm -f /etc/smartdns/domain-set/ai_noncn.conf
    fi
    if ! update_bxtest_dns_to_smartdns; then
        [[ $# == 0 ]] && before_show_menu
        return 1
    fi

    if ! restart_smartdns_service; then
        echo -e "${red}smartdns 启动失败，请检查 127.0.0.1:53 是否被 systemd-resolved 或其他 DNS 服务占用${plain}"
        show_smartdns_failure_diagnostics
        if [[ x"${release}" != x"alpine" ]]; then
            echo -e "${yellow}可使用 journalctl -u smartdns -e --no-pager 查看 smartdns 日志${plain}"
        fi
        [[ $# == 0 ]] && before_show_menu
        return 1
    fi

    echo -e "${green}smartdns 已安装并写入 /etc/smartdns/smartdns.conf${plain}"
    echo -e "${green}已将 BXtest 的 hysteria2、sing-box 及通用 DNS 配置指向 tcp://127.0.0.1${plain}"
    if [[ "$enable_ai_dns" == true ]]; then
        echo -e "${green}已在 SmartDNS 中启用非中国大陆 AI 服务 DNS 分流，AI 域名走 ${ai_dns_server}${plain}"
        echo -e "${green}已设置每日 04:17 自动更新 AI 分流规则文件，不会重启 smartdns${plain}"
    else
        echo -e "${green}未启用 AI DNS 分流，所有域名使用 SmartDNS 默认上游${plain}"
    fi
    [[ $# == 0 ]] && before_show_menu
}

install_bbr() {
    bash <(curl -L -s https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh)
}

update_shell() {
    wget -O /usr/bin/BXtest -N --no-check-certificate https://raw.githubusercontent.com/Kopw/BXtest-script/master/BXtest.sh
    if [[ $? != 0 ]]; then
        echo ""
        echo -e "${red}下载脚本失败，请检查本机能否连接 Github${plain}"
        before_show_menu
    else
        chmod +x /usr/bin/BXtest
        echo -e "${green}升级脚本成功，请重新运行脚本${plain}" && exit 0
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /usr/local/BXtest/BXtest ]]; then
        return 2
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(service BXtest status | awk '{print $3}')
        if [[ x"${temp}" == x"started" ]]; then
            return 0
        else
            return 1
        fi
    else
        temp=$(systemctl status BXtest | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        if [[ x"${temp}" == x"running" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

check_enabled() {
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(rc-update show | grep BXtest)
        if [[ x"${temp}" == x"" ]]; then
            return 1
        else
            return 0
        fi
    else
        temp=$(systemctl is-enabled BXtest)
        if [[ x"${temp}" == x"enabled" ]]; then
            return 0
        else
            return 1;
        fi
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        echo -e "${red}BXtest已安装，请不要重复安装${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        echo -e "${red}请先安装BXtest${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
        0)
            echo -e "BXtest状态: ${green}已运行${plain}"
            show_enable_status
            ;;
        1)
            echo -e "BXtest状态: ${yellow}未运行${plain}"
            show_enable_status
            ;;
        2)
            echo -e "BXtest状态: ${red}未安装${plain}"
    esac
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "是否开机自启: ${green}是${plain}"
    else
        echo -e "是否开机自启: ${red}否${plain}"
    fi
}

generate_x25519_key() {
    echo -n "正在生成 x25519 密钥："
    /usr/local/BXtest/BXtest x25519
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_BXtest_version() {
    echo -n "BXtest 版本："
    /usr/local/BXtest/BXtest version
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

add_node_config() {
    echo -e "${green}请选择节点核心类型：${plain}"
    echo -e "${green}1. xray${plain}"
    echo -e "${green}2. singbox${plain}"
    echo -e "${green}3. hysteria2${plain}"
    read -rp "请输入：" core_type
    if [ "$core_type" == "1" ]; then
        core="xray"
        core_xray=true
    elif [ "$core_type" == "2" ]; then
        core="sing"
        core_sing=true
    elif [ "$core_type" == "3" ]; then
        core="hysteria2"
        core_hysteria2=true
    else
        echo "无效的选择。请选择 1 2 3。"
        continue
    fi
    while true; do
        read -rp "请输入节点Node ID：" NodeID
        # 判断NodeID是否为正整数
        if [[ "$NodeID" =~ ^[0-9]+$ ]]; then
            break  # 输入正确，退出循环
        else
            echo "错误：请输入正确的数字作为Node ID。"
        fi
    done

    if [ "$core_hysteria2" = true ] && [ "$core_xray" = false ] && [ "$core_sing" = false ]; then
        NodeType="hysteria2"
    else
        echo -e "${yellow}请选择节点传输协议：${plain}"
        echo -e "${green}1. Shadowsocks${plain}"
        echo -e "${green}2. Vless${plain}"
        echo -e "${green}3. Vmess${plain}"
        if [ "$core_sing" == true ]; then
            echo -e "${green}4. Hysteria${plain}"
            echo -e "${green}5. Hysteria2${plain}"
        fi
        if [ "$core_hysteria2" == true ] && [ "$core_sing" = false ]; then
            echo -e "${green}5. Hysteria2${plain}"
        fi
        echo -e "${green}6. Trojan${plain}"  
        if [ "$core_sing" == true ]; then
            echo -e "${green}7. Tuic${plain}"
            echo -e "${green}8. AnyTLS${plain}"
        fi
        read -rp "请输入：" NodeType
        case "$NodeType" in
            1 ) NodeType="shadowsocks" ;;
            2 ) NodeType="vless" ;;
            3 ) NodeType="vmess" ;;
            4 ) NodeType="hysteria" ;;
            5 ) NodeType="hysteria2" ;;
            6 ) NodeType="trojan" ;;
            7 ) NodeType="tuic" ;;
            8 ) NodeType="anytls" ;;
            * ) NodeType="shadowsocks" ;;
        esac
    fi
    fastopen=true
    if [ "$NodeType" == "vless" ]; then
        read -rp "请选择是否为reality节点？(y/n)" isreality
    elif [ "$NodeType" == "hysteria" ] || [ "$NodeType" == "hysteria2" ] || [ "$NodeType" == "tuic" ] || [ "$NodeType" == "anytls" ]; then
        fastopen=false
        istls="y"
    fi

    if [[ "$isreality" != "y" && "$isreality" != "Y" &&  "$istls" != "y" ]]; then
        read -rp "请选择是否进行TLS配置？(y/n)" istls
    fi

    certmode="none"
    certdomain="example.com"
    if [[ "$isreality" != "y" && "$isreality" != "Y" && ( "$istls" == "y" || "$istls" == "Y" ) ]]; then
        echo -e "${yellow}请选择证书申请模式：${plain}"
        echo -e "${green}1. http模式自动申请，节点域名已正确解析（认证端口33211，需CF转发80->33211）${plain}"
        echo -e "${green}2. dns模式自动申请，需填入正确域名服务商API参数${plain}"
        echo -e "${green}3. self模式，自签证书或提供已有证书文件${plain}"
        echo -e "${green}4. IP证书模式，使用acme.sh申请Let's Encrypt IP证书（仅支持公网IP）${plain}"
        echo -e "${green}5. tls模式自动申请，使用HTTPS 443端口验证（需确保443端口未被占用）${plain}"
        echo -e "${green}6. 直链下载模式，从URL直接下载证书和密钥（每日自动更新）${plain}"
        read -rp "请输入：" certmode
        case "$certmode" in
            1 ) certmode="http" 
                read -rp "请输入节点证书域名(example.com)：" certdomain
                ;;
            2 ) certmode="dns"
                read -rp "请输入节点证书域名(example.com)：" certdomain
                read -rp "请输入用于证书注册的邮箱地址：" cert_email
                echo -e "${yellow}请输入 Cloudflare API Token（需要 Zone:DNS:Edit 权限）${plain}"
                echo -e "${yellow}获取方式：Cloudflare Dashboard -> My Profile -> API Tokens -> Create Token${plain}"
                read -rp "请输入 CF_DNS_API_TOKEN：" cf_dns_api_token
                if [[ -z "$cf_dns_api_token" ]]; then
                    echo -e "${red}API Token 不能为空，将使用默认占位符，请手动修改配置文件！${plain}"
                    cf_dns_api_token="your_cloudflare_api_token_here"
                else
                    echo -e "${green}Cloudflare API Token 已设置${plain}"
                fi
                ;;
            3 ) certmode="self"
                read -rp "请输入节点证书域名(example.com)：" certdomain
                echo -e "${red}请手动修改配置文件后重启BXtest！${plain}"
                ;;
            4 ) certmode="self"
                read -rp "请输入服务器公网IP地址：" server_ip
                certdomain="$server_ip"
                
                # 先检测是否已有证书
                check_existing_cert "$server_ip"
                if [[ $? -eq 0 ]]; then
                    echo -e "${green}将使用已有证书，跳过申请流程${plain}"
                else
                    read -rp "请输入用于证书注册的邮箱地址：" acme_email
                    echo -e "${yellow}即将申请 Let's Encrypt IP 证书...${plain}"
                    echo -e "${yellow}注意：IP 证书有效期仅 6 天，已配置每日自动续期${plain}"
                    # 安装依赖和 acme.sh
                    install_acme_deps
                    install_acme "$acme_email"
                    if [[ $? -ne 0 ]]; then
                        echo -e "${red}acme.sh 安装失败，请检查网络${plain}"
                    else
                        # 申请证书
                        issue_ip_cert "$server_ip"
                    fi
                fi
                ;;
            5 ) certmode="tls"
                read -rp "请输入节点证书域名(example.com)：" certdomain
                echo -e "${yellow}TLS模式将使用33211端口进行验证，请确保：${plain}"
                echo -e "${yellow}1. 域名已正确解析到本服务器${plain}"
                echo -e "${yellow}2. 需CF转发443->33211（Let's Encrypt访问443端口）${plain}"
                echo -e "${yellow}3. 防火墙已放行33211端口${plain}"
                ;;
            6 ) certmode="self"
                read -rp "请输入节点证书域名(example.com)：" certdomain
                local cert_remark="${certdomain:-nodomain}"
                cert_file_name="${cert_remark}_fullchain.cer"
                key_file_name="${cert_remark}_cert.key"
                echo -e "${yellow}请输入证书直链URL（${cert_file_name}）：${plain}"
                read -rp "证书URL：" cert_download_url
                echo -e "${yellow}请输入密钥直链URL（${key_file_name}）：${plain}"
                read -rp "密钥URL：" key_download_url
                
                if [[ -z "$cert_download_url" || -z "$key_download_url" ]]; then
                    echo -e "${red}证书或密钥 URL 不能为空！${plain}"
                else
                    # 下载证书
                    download_cert_from_url "$cert_download_url" "$key_download_url" "$cert_remark"
                    if [[ $? -eq 0 ]]; then
                        # 设置每日自动更新
                        setup_daily_cert_download "$cert_download_url" "$key_download_url" "$cert_remark"
                        echo -e "${green}证书配置完成！每日将自动从直链获取最新证书${plain}"
                    else
                        echo -e "${red}证书下载失败，请检查 URL 后重试${plain}"
                    fi
                fi
                ;;
        esac
    fi
    ipv6_support=$(check_ipv6_support)
    listen_ip="0.0.0.0"
    if [ "$ipv6_support" -eq 1 ]; then
        listen_ip="::"
    fi
    node_config=""
    if [ "$core_type" == "1" ]; then 
    node_config=$(cat <<EOF
{
            "Core": "$core",
            "Host": "$ApiHost",
            "Key": "$ApiKey",
            "ID": $NodeID,
            "NodeType": "$NodeType",
            "Timeout": 30,
            "ListenIP": "0.0.0.0",
            "SendIP": "0.0.0.0",
            "DeviceOnlineMinTraffic": 200,
            "MinReportTraffic": 0,
            "EnableProxyProtocol": false,
            "EnableUot": true,
            "EnableTFO": true,
            "DNSType": "UseIPv4",
            "CertConfig": {
                "CertMode": "$certmode",
                "RejectUnknownSni": false,
                "CertDomain": "$certdomain",
                "CertFile": "/etc/BXtest/${cert_file_name:-fullchain.cer}",
                "KeyFile": "/etc/BXtest/${key_file_name:-cert.key}",
                "Email": "${cert_email:-BXtest@github.com}",
                "Provider": "cloudflare",
                "DNSEnv": {
                    "CF_DNS_API_TOKEN": "${cf_dns_api_token:-}"
                }
            }
        },
EOF
)
    elif [ "$core_type" == "2" ]; then
    node_config=$(cat <<EOF
{
            "Core": "$core",
            "Host": "$ApiHost",
            "Key": "$ApiKey",
            "ID": $NodeID,
            "NodeType": "$NodeType",
            "Timeout": 30,
            "ListenIP": "$listen_ip",
            "SendIP": "0.0.0.0",
            "DeviceOnlineMinTraffic": 200,
            "MinReportTraffic": 0,
            "TCPFastOpen": $fastopen,
            "SniffEnabled": true,
            "CertConfig": {
                "CertMode": "$certmode",
                "RejectUnknownSni": false,
                "CertDomain": "$certdomain",
                "CertFile": "/etc/BXtest/${cert_file_name:-fullchain.cer}",
                "KeyFile": "/etc/BXtest/${key_file_name:-cert.key}",
                "Email": "${cert_email:-BXtest@github.com}",
                "Provider": "cloudflare",
                "DNSEnv": {
                    "CF_DNS_API_TOKEN": "${cf_dns_api_token:-}"
                }
            }
        },
EOF
)
    elif [ "$core_type" == "3" ]; then
    node_config=$(cat <<EOF
{
            "Core": "$core",
            "Host": "$ApiHost",
            "Key": "$ApiKey",
            "ID": $NodeID,
            "NodeType": "$NodeType",
            "Hysteria2ConfigPath": "/etc/BXtest/hy2config.yaml",
            "Timeout": 30,
            "ListenIP": "",
            "SendIP": "0.0.0.0",
            "DeviceOnlineMinTraffic": 200,
            "MinReportTraffic": 0,
            "CertConfig": {
                "CertMode": "$certmode",
                "RejectUnknownSni": false,
                "CertDomain": "$certdomain",
                "CertFile": "/etc/BXtest/${cert_file_name:-fullchain.cer}",
                "KeyFile": "/etc/BXtest/${key_file_name:-cert.key}",
                "Email": "${cert_email:-BXtest@github.com}",
                "Provider": "cloudflare",
                "DNSEnv": {
                    "CF_DNS_API_TOKEN": "${cf_dns_api_token:-}"
                }
            }
        },
EOF
)
    fi
    nodes_config+=("$node_config")
}

generate_config_file() {
    echo -e "${yellow}BXtest 配置文件生成向导${plain}"
    echo -e "${red}请阅读以下注意事项：${plain}"
    echo -e "${red}1. 目前该功能正处测试阶段${plain}"
    echo -e "${red}2. 生成的配置文件会保存到 /etc/BXtest/config.json${plain}"
    echo -e "${red}3. 原来的配置文件会保存到 /etc/BXtest/config.json.bak${plain}"
    echo -e "${red}4. 目前仅部分支持TLS${plain}"
    echo -e "${red}5. 使用此功能生成的配置文件会自带审计，确定继续？(y/n)${plain}"
    read -rp "请输入：" continue_prompt
    if [[ "$continue_prompt" =~ ^[Nn][Oo]? ]]; then
        exit 0
    fi
    
    nodes_config=()
    first_node=true
    core_xray=false
    core_sing=false
    fixed_api_info=false
    check_api=false
    
    while true; do
        if [ "$first_node" = true ]; then
            read -rp "请输入机场网址(https://example.com)：" ApiHost
            read -rp "请输入面板对接API Key：" ApiKey
            read -rp "是否设置固定的机场网址和API Key？(y/n)" fixed_api
            if [ "$fixed_api" = "y" ] || [ "$fixed_api" = "Y" ]; then
                fixed_api_info=true
                echo -e "${red}成功固定地址${plain}"
            fi
            first_node=false
            add_node_config
        else
            read -rp "是否继续添加节点配置？(回车继续，输入n或no退出)" continue_adding_node
            if [[ "$continue_adding_node" =~ ^[Nn][Oo]? ]]; then
                break
            elif [ "$fixed_api_info" = false ]; then
                read -rp "请输入机场网址：" ApiHost
                read -rp "请输入面板对接API Key：" ApiKey
            fi
            add_node_config
        fi
    done

    # 初始化核心配置数组
    cores_config="["

    # 检查并添加xray核心配置
    if [ "$core_xray" = true ]; then
        cores_config+="
    {
        \"Type\": \"xray\",
        \"Log\": {
            \"Level\": \"error\",
            \"ErrorPath\": \"/etc/BXtest/error.log\"
        },
        \"OutboundConfigPath\": \"/etc/BXtest/custom_outbound.json\",
        \"RouteConfigPath\": \"/etc/BXtest/route.json\"
    },"
    fi

    # 检查并添加sing核心配置
    if [ "$core_sing" = true ]; then
        cores_config+="
    {
        \"Type\": \"sing\",
        \"Log\": {
            \"Level\": \"error\",
            \"Timestamp\": true
        },
        \"NTP\": {
            \"Enable\": false,
            \"Server\": \"time.apple.com\",
            \"ServerPort\": 0
        },
        \"OriginalPath\": \"/etc/BXtest/sing_origin.json\"
    },"
    fi

    # 检查并添加hysteria2核心配置
    if [ "$core_hysteria2" = true ]; then
        cores_config+="
    {
        \"Type\": \"hysteria2\",
        \"Log\": {
            \"Level\": \"error\"
        }
    },"
    fi

    # 移除最后一个逗号并关闭数组
    cores_config+="]"
    cores_config=$(echo "$cores_config" | sed 's/},]$/}]/')

    # 切换到配置文件目录
    cd /etc/BXtest
    
    # 备份旧的配置文件
    mv config.json config.json.bak
    nodes_config_str="${nodes_config[*]}"
    formatted_nodes_config="${nodes_config_str%,}"

    # 创建 config.json 文件
    cat <<EOF > /etc/BXtest/config.json
{
    "Log": {
        "Level": "error",
        "Output": ""
    },
    "Cores": $cores_config,
    "Nodes": [$formatted_nodes_config]
}
EOF
    
    # 创建 custom_outbound.json 文件
    cat <<EOF > /etc/BXtest/custom_outbound.json
    [
        {
            "tag": "IPv4_out",
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIPv4v6"
            }
        },
        {
            "tag": "IPv6_out",
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIPv6"
            }
        },
        {
            "protocol": "blackhole",
            "tag": "block"
        }
    ]
EOF
    
    # 创建 route.json 文件
    cat <<EOF > /etc/BXtest/route.json
    {
        "domainStrategy": "AsIs",
        "rules": [
            {
                "type": "field",
                "outboundTag": "block",
                "ip": [
                    "geoip:private"
                ]
            },
            {
                "type": "field",
                "outboundTag": "block",
                "ip": [
                    "127.0.0.1/32",
                    "10.0.0.0/8",
                    "fc00::/7",
                    "fe80::/10",
                    "172.16.0.0/12"
                ]
            },
            {
                "type": "field",
                "outboundTag": "block",
                "protocol": [
                    "bittorrent"
                ]
            }
        ]
    }
EOF

    ipv6_support=$(check_ipv6_support)
    dnsstrategy="ipv4_only"
    if [ "$ipv6_support" -eq 1 ]; then
        dnsstrategy="prefer_ipv4"
    fi
    # 创建 sing_origin.json 文件
    cat <<EOF > /etc/BXtest/sing_origin.json
{
  "dns": {
    "servers": [
      {
        "tag": "cf",
        "address": "local"
      }
    ],
    "strategy": "ipv4_only"
  },
  "outbounds": [
    {
      "tag": "direct",
      "type": "direct",
      "domain_resolver": {
        "server": "cf",
        "strategy": "ipv4_only"
      }
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "rules": [
      {
        "ip_is_private": true,
        "outbound": "block"
      },
      {
        "protocol": "quic",
        "outbound": "block"
      },
      {
        "outbound": "direct",
        "network": [
          "udp","tcp"
        ]
      }
    ]
  },
  "experimental": {
    "cache_file": {
      "enabled": true
    }
  }
}
EOF

    # 创建 hy2config.yaml 文件           
    cat <<EOF > /etc/BXtest/hy2config.yaml
ignoreClientBandwidth: false
disableUDP: false
congestion:
  type: bbr
  bbrProfile: aggressive
resolver:
  type: system
  ipv4Only: true
sniff:
  enable: true
  timeout: 2s
  rewriteDomain: false
  tcpPorts: all
  udpPorts: all
EOF
    echo -e "${green}BXtest 配置文件生成完成，正在重新启动 BXtest 服务${plain}"
    restart 0
    before_show_menu
}

# 放开防火墙端口
open_ports() {
    systemctl stop firewalld.service 2>/dev/null
    systemctl disable firewalld.service 2>/dev/null
    setenforce 0 2>/dev/null
    ufw disable 2>/dev/null
    iptables -P INPUT ACCEPT 2>/dev/null
    iptables -P FORWARD ACCEPT 2>/dev/null
    iptables -P OUTPUT ACCEPT 2>/dev/null
    iptables -t nat -F 2>/dev/null
    iptables -t mangle -F 2>/dev/null
    iptables -F 2>/dev/null
    iptables -X 2>/dev/null
    netfilter-persistent save 2>/dev/null
    echo -e "${green}放开防火墙端口成功！${plain}"
}

show_usage() {
    echo "BXtest 管理脚本使用方法: "
    echo "------------------------------------------"
    echo "BXtest              - 显示管理菜单 (功能更多)"
    echo "BXtest start        - 启动 BXtest"
    echo "BXtest stop         - 停止 BXtest"
    echo "BXtest restart      - 重启 BXtest"
    echo "BXtest status       - 查看 BXtest 状态"
    echo "BXtest enable       - 设置 BXtest 开机自启"
    echo "BXtest disable      - 取消 BXtest 开机自启"
    echo "BXtest log          - 查看 BXtest 日志"
    echo "BXtest x25519       - 生成 x25519 密钥"
    echo "BXtest generate     - 生成 BXtest 配置文件"
    echo "BXtest smartdns [AI_DNS] - 安装 smartdns，可选启用 AI 分流"
    echo "                        不传 AI_DNS 时会询问是否启用；传入 AI_DNS 时直接启用"
    echo "BXtest update       - 更新 BXtest"
    echo "BXtest update x.x.x - 更新 BXtest 到指定版本"
    echo "BXtest install      - 安装 BXtest"
    echo "BXtest uninstall    - 卸载 BXtest"
    echo "BXtest version      - 查看 BXtest 版本"
    echo "------------------------------------------"
}

show_menu() {
    echo -e "
  ${green}BXtest 后端管理脚本，${plain}${red}不适用于docker${plain}
--- https://github.com/Kopw/BXtest-script ---
  ${green}0.${plain} 修改配置
————————————————
  ${green}1.${plain} 安装 BXtest
  ${green}2.${plain} 更新 BXtest
  ${green}3.${plain} 卸载 BXtest
————————————————
  ${green}4.${plain} 启动 BXtest
  ${green}5.${plain} 停止 BXtest
  ${green}6.${plain} 重启 BXtest
  ${green}7.${plain} 查看 BXtest 状态
  ${green}8.${plain} 查看 BXtest 日志
————————————————
  ${green}9.${plain} 设置 BXtest 开机自启
  ${green}10.${plain} 取消 BXtest 开机自启
————————————————
  ${green}11.${plain} 一键安装 bbr (最新内核)
  ${green}12.${plain} 查看 BXtest 版本
  ${green}13.${plain} 生成 X25519 密钥
  ${green}14.${plain} 升级 BXtest 维护脚本
  ${green}15.${plain} 生成 BXtest 配置文件
  ${green}16.${plain} 放行 VPS 的所有网络端口
  ${green}17.${plain} 安装 smartdns 并可选启用 AI DNS 分流
  ${green}18.${plain} 退出脚本
 "
 #后续更新可加入上方字符串中
    show_status
    echo && read -rp "请输入选择 [0-18]: " num

    case "${num}" in
        0) config ;;
        1) check_uninstall && install_BXtest ;;
        2) check_install && update ;;
        3) check_install && uninstall ;;
        4) check_install && start ;;
        5) check_install && stop ;;
        6) check_install && restart ;;
        7) check_install && status ;;
        8) check_install && show_log ;;
        9) check_install && enable ;;
        10) check_install && disable ;;
        11) install_bbr ;;
        12) check_install && show_BXtest_version ;;
        13) check_install && generate_x25519_key ;;
        14) update_shell ;;
        15) generate_config_file ;;
        16) open_ports ;;
        17) install_smartdns ;;
        18) exit ;;
        *) echo -e "${red}请输入正确的数字 [0-18]${plain}" ;;
    esac
}


if [[ $# > 0 ]]; then
    case $1 in
        "start") check_install 0 && start 0 ;;
        "stop") check_install 0 && stop 0 ;;
        "restart") check_install 0 && restart 0 ;;
        "status") check_install 0 && status 0 ;;
        "enable") check_install 0 && enable 0 ;;
        "disable") check_install 0 && disable 0 ;;
        "log") check_install 0 && show_log 0 ;;
        "update") check_install 0 && update 0 $2 ;;
        "config") config $* ;;
        "generate") generate_config_file ;;
        "smartdns") install_smartdns 0 "$2" ;;
        "install") check_uninstall 0 && install_BXtest 0 ;;
        "uninstall") check_install 0 && uninstall 0 ;;
        "x25519") check_install 0 && generate_x25519_key 0 ;;
        "version") check_install 0 && show_BXtest_version 0 ;;
        "update_shell") update_shell ;;
        *) show_usage
    esac
else
    show_menu
fi
