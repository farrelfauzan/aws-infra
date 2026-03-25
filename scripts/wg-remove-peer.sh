#!/usr/bin/env bash
# Usage: sudo ./wg-remove-peer.sh <name>
# Example: sudo ./wg-remove-peer.sh john
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: sudo $0 <name>"
  exit 1
fi

NAME="$1"
CONF="/etc/wireguard/wg0.conf"

# Find the peer's public key by name comment
PUB_KEY=$(grep -A1 "# $NAME" "$CONF" | grep "PublicKey" | awk '{print $3}')

if [ -z "$PUB_KEY" ]; then
  echo "ERROR: Peer '$NAME' not found in $CONF"
  exit 1
fi

# Remove peer from running WireGuard
wg set wg0 peer "$PUB_KEY" remove

# Remove peer block from config file (comment + PublicKey + AllowedIPs + blank line)
sed -i "/# $NAME/{N;N;N;d}" "$CONF"

# Remove client config
rm -f "/etc/wireguard/clients/${NAME}.conf"

echo "Removed peer: $NAME ($PUB_KEY)"
