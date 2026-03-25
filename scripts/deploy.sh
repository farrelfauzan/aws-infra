#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_DIR="$REPO_DIR/aws-infra/config"
ENV_FILE="$CONFIG_DIR/.env"
NGINX_CONF="$CONFIG_DIR/nginx.conf"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: $ENV_FILE not found. Copy .env.example to .env and fill in values."
  exit 1
fi

dc() { docker compose -f "$CONFIG_DIR/docker-compose.yml" --env-file "$ENV_FILE" "$@"; }

echo "==> Pulling latest images..."
dc pull

echo "==> Starting services..."
dc up -d --remove-orphans

echo "==> Updating Nginx config..."
sudo cp "$NGINX_CONF" /etc/nginx/sites-available/default
sudo nginx -t && sudo systemctl reload nginx

echo "==> Cleaning up old images..."
docker image prune -f

echo "==> Done. Running containers:"
dc ps
