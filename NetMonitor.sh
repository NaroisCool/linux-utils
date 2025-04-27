#!/bin/bash

# 配置参数
SCAN_INTERVAL=10
EMAIL_TO="861785837@qq.com"
ONLINE_DEVICES_FILE="/tmp/network_devices_online.txt"
OFFLINE_DEVICES_FILE="/tmp/network_devices_offline.txt"
CURRENT_SCAN_FILE=$(mktemp)

# 邮件服务器配置
SMTP_SERVER="smtp.qq.com"
SMTP_PORT="587"
SMTP_USER="861785837@qq.com"
SMTP_PASS="ilrsdupbblodbbhh"
FROM_EMAIL="861785837@qq.com"

# 获取本地网络范围函数
get_network_range() {
    if command -v ifconfig >/dev/null 2>&1; then
        NETWORK_RANGE=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | awk '{print $2}' | grep -v '^127' | head -n1)
        if [ -n "$NETWORK_RANGE" ]; then
            # 转换为CIDR表示法（假设子网掩码为24）
            echo "${NETWORK_RANGE%.*}.0/24"
            return
        fi
    fi

    # 如果都失败，使用默认值
    echo "192.168.1.0/24"
}

# 发送邮件函数
send_email() {
    local subject=$1
    local body=$2
    
    swaks --to "$EMAIL_TO" \
          --from "$FROM_EMAIL" \
          --server "$SMTP_SERVER:$SMTP_PORT" \
          --auth-user "$SMTP_USER" \
          --auth-password "$SMTP_PASS" \
          --tls \
          --h-Subject "$subject" \
          --body "$body"
}

# 安装依赖（swaks是强大的SMTP测试工具）
if ! command -v swaks &> /dev/null; then
    echo "正在安装swaks..."
    sudo apt install swaks || sudo yum install swaks
fi
if ! command -v nmap &> /dev/null; then
    echo "正在安装nmap..."
    sudo apt install -y nmap || sudo yum install -y nmap
fi

# 获取网络范围
NETWORK_RANGE=$(get_network_range)
echo "检测到的网络范围: $NETWORK_RANGE"

# 初始化已知设备列表
[ -f "$ONLINE_DEVICES_FILE" ] && : > "$ONLINE_DEVICES_FILE" || touch "$ONLINE_DEVICES_FILE"
[ -f "$OFFLINE_DEVICES_FILE" ] && : > "$OFFLINE_DEVICES_FILE" || touch "$OFFLINE_DEVICES_FILE"

while true; do
    NETWORK_RANGE=$(get_network_range)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 扫描网络: $NETWORK_RANGE"
    
    # 执行扫描并提取IP
    nmap -sn "$NETWORK_RANGE" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort > "$CURRENT_SCAN_FILE"
    
    # 检测新上线设备
    NEW_ONLINE=$(comm -13 "$ONLINE_DEVICES_FILE" "$CURRENT_SCAN_FILE")
    if [ -n "$NEW_ONLINE" ]; then
        echo "新设备上线:"
        echo "$NEW_ONLINE"
        send_email "网络警报: 新设备上线" "新上线IP:\n$NEW_ONLINE\n\n当前在线设备总数: $(wc -l < "$CURRENT_SCAN_FILE")"
        
        # 更新在线设备列表
        cat "$CURRENT_SCAN_FILE" > "$ONLINE_DEVICES_FILE"
    fi
    
    # 检测离线设备
    NEW_OFFLINE=$(comm -23 "$ONLINE_DEVICES_FILE" "$CURRENT_SCAN_FILE")
    if [ -n "$NEW_OFFLINE" ]; then
        echo "设备离线:"
        echo "$NEW_OFFLINE"
        send_email "网络警报: 设备离线" "离线IP:\n$NEW_OFFLINE\n\n当前在线设备总数: $(wc -l < "$CURRENT_SCAN_FILE")"
        
        # 更新离线记录
        echo "$NEW_OFFLINE" >> "$OFFLINE_DEVICES_FILE"
        sort -u "$OFFLINE_DEVICES_FILE" -o "$OFFLINE_DEVICES_FILE"
        
        # 更新在线设备列表
        cat "$CURRENT_SCAN_FILE" > "$ONLINE_DEVICES_FILE"
    fi
    
    sleep "$SCAN_INTERVAL"
done
