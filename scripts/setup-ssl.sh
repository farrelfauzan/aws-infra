#!/usr/bin/env bash
# Run this ONCE after DNS is pointing to the server.
# Usage: sudo ./setup-ssl.sh <email>
# Example: sudo ./setup-ssl.sh farrel@example.com
set -euo pipefail

DOMAIN="hls-conversion.farrel-space.online"

if [ $# -lt 1 ]; then
  echo "Usage: sudo $0 <email>"
  echo "Example: sudo $0 farrel@example.com"
  exit 1
fi

EMAIL="$1"

echo "==> Verifying DNS for $DOMAIN..."
RESOLVED_IP=$(dig +short "$DOMAIN" @8.8.8.8 | head -1)
MY_IP=$(curl -s https://api.ipify.org)

if [ "$RESOLVED_IP" != "$MY_IP" ]; then
  echo "ERROR: $DOMAIN resolves to $RESOLVED_IP, but this server's IP is $MY_IP"
  echo "Update your DNS A record first, then retry."
  exit 1
fi

echo "==> DNS OK ($DOMAIN → $MY_IP)"
echo "==> Requesting SSL certificate..."

certbot --nginx \
  -d "$DOMAIN" \
  --non-interactive \
  --agree-tos \
  --email "$EMAIL" \
  --redirect

echo "==> SSL setup complete!"
echo "    https://$DOMAIN"
echo ""
echo "    Auto-renewal is enabled via systemd timer."
echo "    Test with: sudo certbot renew --dry-run"
