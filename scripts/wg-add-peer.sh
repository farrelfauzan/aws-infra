#!/usr/bin/env bash
# Usage: sudo ./wg-add-peer.sh <name> <vpn-ip>
# Example: sudo ./wg-add-peer.sh farrel 10.200.200.2
#          sudo ./wg-add-peer.sh john 10.200.200.3
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: sudo $0 <name> <vpn-ip>"
  echo "Example: sudo $0 farrel 10.200.200.2"
  exit 1
fi

NAME="$1"
PEER_IP="$2"
SERVER_PUB=$(cat /etc/wireguard/server_public.key)
SERVER_ENDPOINT=$(curl -s https://api.ipify.org):51820

# Generate client keypair
PEER_PRIV=$(wg genkey)
PEER_PUB=$(echo "$PEER_PRIV" | wg pubkey)

# Add peer to server
cat >> /etc/wireguard/wg0.conf << EOF

[Peer]
# $NAME
PublicKey = $PEER_PUB
AllowedIPs = ${PEER_IP}/32
EOF

# Reload without downtime
wg syncconf wg0 <(wg-quick strip wg0)

# Generate client config
CLIENT_CONF="/etc/wireguard/clients/${NAME}.conf"
mkdir -p /etc/wireguard/clients
cat > "$CLIENT_CONF" << EOF
[Interface]
PrivateKey = $PEER_PRIV
Address = ${PEER_IP}/24
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $SERVER_ENDPOINT
AllowedIPs = 10.200.200.0/24
PersistentKeepalive = 25
EOF

chmod 600 "$CLIENT_CONF"

echo ""
echo "================================================"
echo " WireGuard config for: $NAME ($PEER_IP)"
echo "================================================"
echo ""
cat "$CLIENT_CONF"
echo ""
echo "Config saved to: $CLIENT_CONF"
echo ""

# QR code for mobile
if command -v qrencode &> /dev/null; then
  echo "Scan this QR code with WireGuard mobile app:"
  echo ""
  qrencode -t ansiutf8 < "$CLIENT_CONF"
else
  echo "Install qrencode for mobile QR: sudo apt-get install -y qrencode"
fi
