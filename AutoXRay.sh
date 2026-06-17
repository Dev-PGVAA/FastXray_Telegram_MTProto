#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/vpn-setup.log"
SCRIPT_DIR="/usr/local/etc/xray"
CLIENT_DIR="$SCRIPT_DIR/client_configs"
KEY_DIR="$SCRIPT_DIR/ssh_keys"
SERVER_IP_DEFAULT="62.171.228.97"

exec > >(tee -a "$LOG_FILE") 2>&1

trap 'echo "❌ Ошибка на строке $LINENO. Смотри лог: $LOG_FILE"; exit 1' ERR

print_section() {
  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Запусти от root: sudo bash setup_vpn.sh"
    exit 1
  fi
}

get_server_ip() {
  local ip
  ip="$(hostname -I | awk '{print $1}' || true)"
  if [[ -z "${ip:-}" ]]; then
    ip="$SERVER_IP_DEFAULT"
  fi
  echo "$ip"
}

make_dirs() {
  mkdir -p "$SCRIPT_DIR" "$CLIENT_DIR" "$KEY_DIR"
  chmod 700 "$KEY_DIR"
}

install_packages() {
  apt update
  apt install -y jq curl wget build-essential make git ufw gettext-base openssl
}

install_xray() {
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
}

generate_xray_data() {
  xray_uuid_vrv="$(xray uuid)"

  domains=(
    www.theregister.com
    www.20minutes.fr
    www.dealabs.com
    www.manomano.fr
    www.caradisiac.com
    www.techadvisor.com
    www.computerworld.com
    teamdocs.su
    wikiportal.su
    docscenter.su
    www.bing.com
    github.com
    tradingview.com
  )

  xray_dest_vrv="${domains[$RANDOM % ${#domains[@]}]}"
  xray_dest_vrv222="${domains[$RANDOM % ${#domains[@]}]}"

  key_output="$(xray x25519)"
  xray_privateKey_vrv="$(awk -F': ' '/PrivateKey/ {print $2}' <<< "$key_output")"
  xray_publicKey_vrv="$(awk -F': ' '/PublicKey/ {print $2}' <<< "$key_output")"
  xray_shortIds_vrv="$(openssl rand -hex 8)"
  xray_sspasw_vrv="$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 20)"
  ipserv="$(get_server_ip)"

  export xray_uuid_vrv xray_dest_vrv xray_dest_vrv222 xray_privateKey_vrv xray_publicKey_vrv xray_shortIds_vrv xray_sspasw_vrv ipserv
}

write_xray_config() {
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
      "tag": "VLESS443",
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
          "serverNames": ["${xray_dest_vrv}"]
        }
      }
    },
    {
      "tag": "VLESS8443",
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
          "serverNames": ["${xray_dest_vrv222}"]
        }
      }
    },
    {
      "tag": "Shadowsocks2040",
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
      "settings": {
        "domainStrategy": "ForceIPv4"
      }
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
}

start_xray() {
  systemctl enable xray
  systemctl restart xray
}

setup_ufw() {
  if ss -tlnp | grep -q ':443'; then
    echo "⚠️ Порт 443 уже занят. Освободи его перед запуском Xray."
  fi

  ufw default deny incoming
  ufw default allow outgoing
  ufw allow OpenSSH
  ufw allow 443/tcp comment 'xray vless reality'
  ufw allow 8443/tcp comment 'xray vless reality backup'
  ufw allow 2040/tcp comment 'xray shadowsocks'
  ufw --force enable
}

setup_ssh() {
  local username="${1:-}"
  local server_pubkey_file="$KEY_DIR/server_ed25519.pub"
  local server_privkey_file="$KEY_DIR/server_ed25519"
  local auth_keys="/root/.ssh/authorized_keys"

  ssh-keygen -t ed25519 -N "" -f "$server_privkey_file" -C "server@$(hostname)" >/dev/null

  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  cat "$server_pubkey_file" > "$auth_keys" 2>/dev/null || true
  cat "$server_privkey_file.pub" > "$server_pubkey_file"
  cp "$server_privkey_file" "$KEY_DIR/root_private_key_DO_NOT_LEAVE_ON_SERVER"
  cp "$server_privkey_file.pub" "$KEY_DIR/root_public_key.pub"
  chmod 600 "$auth_keys" "$KEY_DIR/root_private_key_DO_NOT_LEAVE_ON_SERVER" "$KEY_DIR/root_public_key.pub"

  if [[ -n "${username:-}" ]] && id "$username" &>/dev/null; then
    mkdir -p "/home/$username/.ssh"
    chmod 700 "/home/$username/.ssh"
    cp "$KEY_DIR/root_public_key.pub" "/home/$username/.ssh/authorized_keys"
    chown -R "$username:$username" "/home/$username/.ssh"
    chmod 600 "/home/$username/.ssh/authorized_keys"
  fi

  sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config || true
  sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config || true
  grep -q '^PubkeyAuthentication ' /etc/ssh/sshd_config || echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config
  grep -q '^UsePAM ' /etc/ssh/sshd_config || echo 'UsePAM yes' >> /etc/ssh/sshd_config
  systemctl restart sshd
}

write_client_configs() {
  local server_ip="$1"
  local ss_encoded
  ss_encoded="$(printf 'chacha20-ietf-poly1305:%s' "$xray_sspasw_vrv" | base64 -w 0)"

  cat > "$CLIENT_DIR/vless_443_client.json" <<EOF
{
  "inbounds": [{
    "port": 10808,
    "listen": "127.0.0.1",
    "protocol": "socks",
    "settings": { "udp": true }
  }],
  "outbounds": [{
    "protocol": "vless",
    "settings": {
      "vnext": [{
        "address": "$server_ip",
        "port": 443,
        "users": [{
          "id": "$xray_uuid_vrv",
          "flow": "xtls-rprx-vision",
          "encryption": "none"
        }]
      }]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "serverName": "$xray_dest_vrv",
        "fingerprint": "chrome",
        "publicKey": "$xray_publicKey_vrv",
        "shortId": "$xray_shortIds_vrv",
        "spiderX": "/"
      }
    }
  }]
}
EOF

  cat > "$CLIENT_DIR/vless_8443_client.json" <<EOF
{
  "inbounds": [{
    "port": 10809,
    "listen": "127.0.0.1",
    "protocol": "socks",
    "settings": { "udp": true }
  }],
  "outbounds": [{
    "protocol": "vless",
    "settings": {
      "vnext": [{
        "address": "$server_ip",
        "port": 8443,
        "users": [{
          "id": "$xray_uuid_vrv",
          "flow": "xtls-rprx-vision",
          "encryption": "none"
        }]
      }]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "serverName": "$xray_dest_vrv222",
        "fingerprint": "chrome",
        "publicKey": "$xray_publicKey_vrv",
        "shortId": "$xray_shortIds_vrv",
        "spiderX": "/"
      }
    }
  }]
}
EOF

  cat > "$CLIENT_DIR/shadowsocks_client.json" <<EOF
{
  "inbounds": [{
    "port": 10810,
    "listen": "127.0.0.1",
    "protocol": "socks",
    "settings": { "udp": true }
  }],
  "outbounds": [{
    "protocol": "shadowsocks",
    "settings": {
      "servers": [{
        "address": "$server_ip",
        "port": 2040,
        "method": "chacha20-ietf-poly1305",
        "password": "$xray_sspasw_vrv"
      }]
    }
  }]
}
EOF

  cat > "$CLIENT_DIR/README.txt" <<EOF
===========================================
VPN Конфигурации
Сервер IP: $server_ip
Дата установки: $(date)
===========================================

1. VLESS + REALITY (Порт 443)
vless://$xray_uuid_vrv@$server_ip:443?security=reality&sni=$xray_dest_vrv&fp=chrome&pbk=$xray_publicKey_vrv&sid=$xray_shortIds_vrv&type=tcp&flow=xtls-rprx-vision&encryption=none&spx=%2F#VPN-443

2. VLESS + REALITY (Порт 8443)
vless://$xray_uuid_vrv@$server_ip:8443?security=reality&sni=$xray_dest_vrv222&fp=chrome&pbk=$xray_publicKey_vrv&sid=$xray_shortIds_vrv&type=tcp&flow=xtls-rprx-vision&encryption=none&spx=%2F#VPN-8443

3. Shadowsocks (Порт 2040)
ss://$ss_encoded@$server_ip:2040#VPN-2040

SSH files:
- Public key: $KEY_DIR/root_public_key.pub
- Private key: $KEY_DIR/root_private_key_DO_NOT_LEAVE_ON_SERVER
===========================================
EOF
}

final_output() {
  local server_ip="$1"
  local ss_encoded
  ss_encoded="$(printf 'chacha20-ietf-poly1305:%s' "$xray_sspasw_vrv" | base64 -w 0)"

  print_section "SSH KEYS"
  echo "Public key:"
  cat "$KEY_DIR/root_public_key.pub"
  echo
  echo "Private key:"
  cat "$KEY_DIR/root_private_key_DO_NOT_LEAVE_ON_SERVER"
  echo

  print_section "VPN LINKS"
  echo "VLESS 443:"
  echo "vless://$xray_uuid_vrv@$server_ip:443?security=reality&sni=$xray_dest_vrv&fp=chrome&pbk=$xray_publicKey_vrv&sid=$xray_shortIds_vrv&type=tcp&flow=xtls-rprx-vision&encryption=none&spx=%2F#VPN-443"
  echo
  echo "VLESS 8443:"
  echo "vless://$xray_uuid_vrv@$server_ip:8443?security=reality&sni=$xray_dest_vrv222&fp=chrome&pbk=$xray_publicKey_vrv&sid=$xray_shortIds_vrv&type=tcp&flow=xtls-rprx-vision&encryption=none&spx=%2F#VPN-8443"
  echo
  echo "Shadowsocks 2040:"
  echo "ss://$ss_encoded@$server_ip:2040#VPN-2040"
  echo

  print_section "FILES"
  echo "Client dir: $CLIENT_DIR"
  echo "SSH key dir: $KEY_DIR"
  echo "Log: $LOG_FILE"
}

main() {
  need_root
  make_dirs
  install_packages
  install_xray
  generate_xray_data
  write_xray_config
  start_xray
  setup_ufw
  setup_ssh "${1:-serv}"
  write_client_configs "$ipserv"
  final_output "$ipserv"
  echo
  echo "✅ Готово. Скопируй public/private key из вывода выше и перенеси private key на ноутбук."
  echo "⚠️ После этого удали private key с сервера."
}

main "$@"
