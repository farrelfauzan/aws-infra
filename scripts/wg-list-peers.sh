#!/usr/bin/env bash
# List all WireGuard peers and their status
set -euo pipefail

echo "=== WireGuard Peers ==="
echo ""

# Show live status
wg show wg0

echo ""
echo "=== Saved Client Configs ==="
ls -1 /etc/wireguard/clients/ 2>/dev/null || echo "(none)"
