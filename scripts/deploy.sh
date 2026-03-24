#!/usr/bin/env bash
set -euo pipefail

# Resolve paths relative to the git repo
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_DIR="$REPO_DIR/aws-infra/config"
COMPOSE_FILE="$CONFIG_DIR/docker-compose.yml"
ENV_FILE="$CONFIG_DIR/.env"
NGINX_CONF="$CONFIG_DIR/nginx.conf"

# --- Preflight ---
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: $ENV_FILE not found. Copy .env.example to .env and fill in values."
  exit 1
fi

# Source env for ECR_REGISTRY (save and restore AWS creds so instance role is used for ECR login)
_AWS_AKI="${AWS_ACCESS_KEY_ID:-}"
_AWS_SAK="${AWS_SECRET_ACCESS_KEY:-}"
set -a
source "$ENV_FILE"
set +a

# Use instance role for ECR auth, not .env credentials
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY

REGION="${AWS_REGION:-ap-southeast-1}"

echo "==> Logging into ECR..."
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"

# Restore AWS creds for docker containers that need them (HLS S3 access)
export AWS_ACCESS_KEY_ID="$_AWS_AKI"
export AWS_SECRET_ACCESS_KEY="$_AWS_SAK"

echo "==> Pulling latest images..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull

echo "==> Starting services..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --remove-orphans

echo "==> Updating Nginx config..."
sudo cp "$NGINX_CONF" /etc/nginx/sites-available/default
sudo nginx -t && sudo systemctl reload nginx

echo "==> Cleaning up old images..."
docker image prune -f

echo "==> Done. Running containers:"
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps
