#!/bin/bash
set -e

LOG_FILE="/var/log/vpn-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "===== Запуск установки: $(date) ====="

trap 'echo "❌ Ошибка на строке $LINENO. Смотри лог: $LOG_FILE"; exit 1' ERR

if [[ $EUID -ne 0 ]]; then
  echo "Запусти от root (sudo bash setup_vpn.sh)"
  exit 1
fi

# ============================================================
# 0. Создание нового пользователя (опционально)
# ============================================================
read -p "Создать нового пользователя? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  read -p "Имя пользователя: " username
  if id "$username" &>/dev/null 2>&1; then
    echo "Пользователь $username уже существует"
  else
    useradd -m -s /bin/bash "$username"
    usermod -aG sudo "$username"
    echo "Пользователь $username создан с правами sudo"
    echo "Установи пароль вручную: passwd $username"
  fi
fi

echo "=== 1. Обновление и установка необходимых пакетов ==="
apt update && apt install -y jq curl wget build-essential make git ufw gettext-base

# ============================================================
# 2. Установка Xray
# ============================================================
echo "=== 2. Установка Xray-core ==="
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

SCRIPT_DIR=/usr/local/etc/xray
mkdir -p "$SCRIPT_DIR"

# --- генерация переменных ---
xray_uuid_vrv=$(xray uuid)

domains=(www.theregister.com www.20minutes.fr www.dealabs.com www.manomano.fr www.caradisiac.com www.techadvisor.com www.computerworld.com teamdocs.su wikiportal.su docscenter.su www.bing.com github.com tradingview.com)
xray_dest_vrv=${domains[$RANDOM % ${#domains[@]}]}
xray_dest_vrv222=${domains[$RANDOM % ${#domains[@]}]}

key_output=$(xray x25519)
xray_privateKey_vrv=$(echo "$key_output" | awk -F': ' '/PrivateKey/ {print $2}')
xray_publicKey_vrv=$(echo "$key_output" | awk -F': ' '/Password/ {print $2}')

xray_shortIds_vrv=$(openssl rand -hex 8)
xray_sspasw_vrv=$(openssl rand -base64 15 | tr -dc 'A-Za-z0-9' | head -c 20)

ipserv=$(hostname -I | awk '{print $1}')

export xray_uuid_vrv xray_dest_vrv xray_dest_vrv222 xray_privateKey_vrv xray_publicKey_vrv xray_shortIds_vrv xray_sspasw_vrv

cat << 'EOF' | envsubst > "$SCRIPT_DIR/config.json"
{
  "log": {
    "dnsLog": false,
    "loglevel": "none"
  },
  "dns": {
    "servers": [
      "https+local://8.8.4.4/dns-query",
      "https+local://8.8.8.8/dns-query",
      "https+local://1.1.1.1/dns-query",
      "localhost"
    ],
    "queryStrategy": "UseIPv4"
  },
  "inbounds": [
    {
      "tag": "VLESStcpREALITY",
      "port": 443,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "flow": "xtls-rprx-vision",
            "id": "${xray_uuid_vrv}"
          }
        ],
        "decryption": "none"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "xver": 0,
          "target": "${xray_dest_vrv}:443",
          "spiderX": "/",
          "shortIds": ["${xray_shortIds_vrv}"],
          "privateKey": "${xray_privateKey_vrv}",
          "serverNames": ["${xray_dest_vrv}"],
          "limitFallbackUpload": {
            "afterBytes": 0,
            "bytesPerSec": 65536,
            "burstBytesPerSec": 0
          },
          "limitFallbackDownload": {
            "afterBytes": 5242880,
            "bytesPerSec": 262144,
            "burstBytesPerSec": 2097152
          }
        }
      }
    },
    {
      "tag": "Vless8443",
      "port": 8443,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "flow": "xtls-rprx-vision",
            "id": "${xray_uuid_vrv}"
          }
        ],
        "decryption": "none"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "xver": 0,
          "target": "${xray_dest_vrv222}:443",
          "spiderX": "/",
          "shortIds": ["${xray_shortIds_vrv}"],
          "privateKey": "${xray_privateKey_vrv}",
          "serverNames": ["${xray_dest_vrv222}"],
          "limitFallbackUpload": {
            "afterBytes": 0,
            "bytesPerSec": 65536,
            "burstBytesPerSec": 0
          },
          "limitFallbackDownload": {
            "afterBytes": 5242880,
            "bytesPerSec": 262144,
            "burstBytesPerSec": 2097152
          }
        }
      }
    },
    {
      "tag": "ShadowsocksTCP",
      "port": 2040,
      "listen": "0.0.0.0",
      "protocol": "shadowsocks",
      "settings": {
        "clients": [
          {
            "password": "${xray_sspasw_vrv}",
            "method": "chacha20-ietf-poly1305"
          }
        ]
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      },
      "streamSettings": {
        "network": "raw"
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": { "domainStrategy": "ForceIPv4" }
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    }
  ],
  "routing": {
    "rules": [
      {
        "domain": ["geosite:category-ads", "geosite:win-spy", "geosite:private"],
        "outboundTag": "block"
      },
      {
        "ip": ["geoip:private"],
        "outboundTag": "block"
      }
    ]
  }
}
EOF

systemctl enable xray
systemctl restart xray
echo "Xray готов."

# ============================================================
# 3. Firewall (ufw)
# ============================================================
echo "=== 3. Настройка firewall ==="
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 443/tcp    comment 'xray vless reality'
ufw allow 8443/tcp   comment 'xray vless reality 2'
ufw allow 2040/tcp   comment 'xray shadowsocks'
ufw --force enable

# ============================================================
# 4. Вывод итоговых конфигов
# ============================================================
link1="vless://${xray_uuid_vrv}@${ipserv}:443?security=reality&sni=${xray_dest_vrv}&fp=chrome&pbk=${xray_publicKey_vrv}&sid=${xray_shortIds_vrv}&type=tcp&flow=xtls-rprx-vision&encryption=none&spx=%2F#VPN-vless-443"
link2="vless://${xray_uuid_vrv}@${ipserv}:8443?security=reality&sni=${xray_dest_vrv222}&fp=chrome&pbk=${xray_publicKey_vrv}&sid=${xray_shortIds_vrv}&type=tcp&flow=xtls-rprx-vision&encryption=none&spx=%2F#VPN-vless-8443"
ss_encoded=$(echo -n "chacha20-ietf-poly1305:${xray_sspasw_vrv}" | base64)
link3="ss://${ss_encoded}@${ipserv}:2040#VPN-ShadowS-2040"

echo -e "
================== ГОТОВО ==================

VLESS+REALITY (443):
${link1}

VLESS+REALITY (8443, резерв):
${link2}

Shadowsocks (резерв):
${link3}

============================================
"
