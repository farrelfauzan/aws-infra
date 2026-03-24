#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/performa"
COMPOSE_FILE="$APP_DIR/docker-compose.yml"
ENV_FILE="$APP_DIR/.env"

# --- Preflight ---
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: $ENV_FILE not found. Copy .env.example and fill in values."
  exit 1
fi

# Source env for ECR_REGISTRY
set -a
source "$ENV_FILE"
set +a

REGION="${AWS_REGION:-ap-southeast-1}"

echo "==> Logging into ECR..."
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"

echo "==> Pulling latest images..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull

echo "==> Starting services..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --remove-orphans

echo "==> Cleaning up old images..."
docker image prune -f

echo "==> Done. Running containers:"
docker compose -f "$COMPOSE_FILE" ps
