#!/bin/bash

# 配置生成器脚本
# 基于环境变量生成sing-box配置文件

set -e

CONFIG_FILE="/etc/sing-box/config.json"
TEMPLATE_DIR="/opt/sing-box/templates"

# 生成基础配置结构
generate_base_config() {
    cat > "$CONFIG_FILE" << EOF
{
  "log": {
    "output": "/var/log/sing-box/access.log",
    "level": "$LOG_LEVEL",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "google",
        "address": "8.8.8.8"
      },
      {
        "tag": "cloudflare",
        "address": "1.1.1.1"
      }
    ],
    "rules": [
      {
        "domain_suffix": [".cn"],
        "server": "google"
      }
    ],
    "independent_cache": true
  },
  "ntp": {
    "enabled": true,
    "server": "time.apple.com"
  },
  "inbounds": [],
  "outbounds": [
    {
      "tag": "direct",
      "type": "direct"
    }
  ]
}
EOF
}

# 生成VLESS-Reality配置
generate_vless_reality() {
    local inbound=$(cat << EOF
{
  "tag": "vless-reality-$PORT",
  "type": "vless",
  "listen": "::",
  "listen_port": $PORT,
  "users": [
    {
      "uuid": "$UUID",
      "flow": "$FLOW"
    }
  ],
  "tls": {
    "enabled": true,
    "server_name": "$SERVER_NAME",
    "reality": {
      "enabled": true,
      "handshake": {
        "server": "$SERVER_NAME",
        "server_port": 443
      },
      "private_key": "$PRIVATE_KEY",
      "short_id": [""]
    }
  },
  "sniff": $SNIFF_ENABLED,
  "sniff_override_destination": $SNIFF_OVERRIDE_DESTINATION
}
EOF
)

    # 如果是HTTP传输，添加transport配置
    if [[ "$TRANSPORT" == "http" ]]; then
        inbound=$(echo "$inbound" | jq '. + {"transport": {"type": "http"}}')
    fi

    echo "$inbound"
}

# 生成VLESS-WS-TLS配置
generate_vless_ws_tls() {
    cat << EOF
{
  "tag": "vless-ws-tls-$PORT",
  "type": "vless",
  "listen": "::",
  "listen_port": $PORT,
  "users": [
    {
      "uuid": "$UUID"
    }
  ],
  "transport": {
    "type": "ws",
    "path": "$WS_PATH",
    "headers": {
      "host": "$HOST_HEADER"
    },
    "early_data_header_name": "Sec-WebSocket-Protocol"
  },
  "tls": {
    "enabled": true,
    "alpn": ["h2", "http/1.1"]
  },
  "sniff": $SNIFF_ENABLED,
  "sniff_override_destination": $SNIFF_OVERRIDE_DESTINATION
}
EOF
}

# 生成Trojan配置
generate_trojan() {
    local config=$(cat << EOF
{
  "tag": "trojan-$PORT",
  "type": "trojan",
  "listen": "::",
  "listen_port": $PORT,
  "users": [
    {
      "password": "$TROJAN_PASSWORD"
    }
  ],
  "sniff": $SNIFF_ENABLED,
  "sniff_override_destination": $SNIFF_OVERRIDE_DESTINATION
}
EOF
)

    # 根据传输类型添加配置
    case "$TRANSPORT" in
        ws)
            config=$(echo "$config" | jq '. + {
              "transport": {
                "type": "ws",
                "path": "'$WS_PATH'",
                "headers": {
                  "host": "'$HOST_HEADER'"
                },
                "early_data_header_name": "Sec-WebSocket-Protocol"
              }
            }')
            ;;
        h2|http)
            config=$(echo "$config" | jq '. + {
              "transport": {
                "type": "http",
                "path": "'$H2_PATH'",
                "headers": {
                  "host": "'$HOST_HEADER'"
                }
              }
            }')
            ;;
    esac

    # 添加TLS配置 (Reality或标准TLS)
    if [[ "$PROTOCOL" =~ "reality" ]]; then
        config=$(echo "$config" | jq '. + {
          "tls": {
            "enabled": true,
            "server_name": "'$SERVER_NAME'",
            "reality": {
              "enabled": true,
              "handshake": {
                "server": "'$SERVER_NAME'",
                "server_port": 443
              },
              "private_key": "'$PRIVATE_KEY'",
              "short_id": [""]
            }
          }
        }')
    elif [[ "$PROTOCOL" =~ "tls" ]]; then
        config=$(echo "$config" | jq '. + {
          "tls": {
            "enabled": true,
            "alpn": ["h2", "http/1.1"]
          }
        }')
    fi

    echo "$config"
}

# 生成VMess配置
generate_vmess() {
    local config=$(cat << EOF
{
  "tag": "vmess-$PORT",
  "type": "vmess",
  "listen": "::",
  "listen_port": $PORT,
  "users": [
    {
      "uuid": "$UUID",
      "security": "$VMESS_SECURITY"
    }
  ],
  "sniff": $SNIFF_ENABLED,
  "sniff_override_destination": $SNIFF_OVERRIDE_DESTINATION
}
EOF
)

    # 根据传输类型添加配置
    case "$TRANSPORT" in
        ws)
            config=$(echo "$config" | jq '. + {
              "transport": {
                "type": "ws",
                "path": "'$WS_PATH'",
                "headers": {
                  "host": "'$HOST_HEADER'"
                },
                "early_data_header_name": "Sec-WebSocket-Protocol"
              }
            }')
            ;;
        h2|http)
            config=$(echo "$config" | jq '. + {
              "transport": {
                "type": "http",
                "path": "'$H2_PATH'",
                "headers": {
                  "host": "'$HOST_HEADER'"
                }
              }
            }')
            ;;
        quic)
            config=$(echo "$config" | jq '. + {
              "transport": {
                "type": "quic"
              }
            }')
            ;;
    esac

    # 添加TLS配置
    if [[ "$PROTOCOL" =~ "tls" ]]; then
        config=$(echo "$config" | jq '. + {
          "tls": {
            "enabled": true,
            "alpn": ["h2", "http/1.1"]
          }
        }')
    fi

    echo "$config"
}

# 生成Shadowsocks配置
generate_shadowsocks() {
    cat << EOF
{
  "tag": "shadowsocks-$PORT",
  "type": "shadowsocks",
  "listen": "::",
  "listen_port": $PORT,
  "method": "$SS_METHOD",
  "password": "$SS_PASSWORD",
  "sniff": $SNIFF_ENABLED,
  "sniff_override_destination": $SNIFF_OVERRIDE_DESTINATION
}
EOF
}

# 生成Hysteria2配置
generate_hysteria2() {
    cat << EOF
{
  "tag": "hysteria2-$PORT",
  "type": "hysteria2",
  "listen": "::",
  "listen_port": $PORT,
  "users": [
    {
      "password": "$TROJAN_PASSWORD"
    }
  ],
  "tls": {
    "enabled": true,
    "alpn": ["h3"]
  },
  "sniff": $SNIFF_ENABLED,
  "sniff_override_destination": $SNIFF_OVERRIDE_DESTINATION
}
EOF
}

# 生成TUIC配置
generate_tuic() {
    cat << EOF
{
  "tag": "tuic-$PORT",
  "type": "tuic",
  "listen": "::",
  "listen_port": $PORT,
  "users": [
    {
      "uuid": "$UUID",
      "password": "$TROJAN_PASSWORD"
    }
  ],
  "congestion_control": "bbr",
  "tls": {
    "enabled": true,
    "alpn": ["h3"]
  },
  "sniff": $SNIFF_ENABLED,
  "sniff_override_destination": $SNIFF_OVERRIDE_DESTINATION
}
EOF
}

# 生成Socks配置
generate_socks() {
    cat << EOF
{
  "tag": "socks-$PORT",
  "type": "socks",
  "listen": "::",
  "listen_port": $PORT,
  "users": [
    {
      "username": "${SOCKS_USER:-233boy}",
      "password": "${SOCKS_PASS:-$UUID}"
    }
  ],
  "sniff": $SNIFF_ENABLED,
  "sniff_override_destination": $SNIFF_OVERRIDE_DESTINATION
}
EOF
}

# 主配置生成函数
main() {
    echo "生成sing-box配置: $PROTOCOL"

    # 生成基础配置
    generate_base_config

    # 根据协议类型生成inbound配置
    local inbound_config=""

    case "$PROTOCOL" in
        vless-reality)
            inbound_config=$(generate_vless_reality)
            ;;
        vless-ws-tls)
            inbound_config=$(generate_vless_ws_tls)
            ;;
        trojan*)
            inbound_config=$(generate_trojan)
            ;;
        vmess*)
            inbound_config=$(generate_vmess)
            ;;
        shadowsocks)
            inbound_config=$(generate_shadowsocks)
            ;;
        hysteria2)
            inbound_config=$(generate_hysteria2)
            ;;
        tuic)
            inbound_config=$(generate_tuic)
            ;;
        socks)
            inbound_config=$(generate_socks)
            ;;
        *)
            echo "错误: 不支持的协议 $PROTOCOL"
            exit 1
            ;;
    esac

    # 将inbound配置添加到基础配置中
    local temp_config=$(jq --argjson inbound "$inbound_config" '.inbounds += [$inbound]' "$CONFIG_FILE")
    echo "$temp_config" > "$CONFIG_FILE"

    echo "配置生成完成: $CONFIG_FILE"
}

# 执行主函数
main "$@"