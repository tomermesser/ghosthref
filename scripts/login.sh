#!/usr/bin/env bash
# Writes AWS credentials from .env to ~/.aws/credentials and verifies them. Run from repo root.
# Created: 2026-09-16

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Copy .env.example to .env and fill in your AWS credentials." >&2
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID not set in .env}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY not set in .env}"
: "${AWS_DEFAULT_REGION:?AWS_DEFAULT_REGION not set in .env}"

mkdir -p "$HOME/.aws"

cat > "$HOME/.aws/credentials" <<CREDS
[default]
aws_access_key_id=$AWS_ACCESS_KEY_ID
aws_secret_access_key=$AWS_SECRET_ACCESS_KEY
CREDS
chmod 600 "$HOME/.aws/credentials"

cat > "$HOME/.aws/config" <<CONFIG
[default]
region=$AWS_DEFAULT_REGION
CONFIG

echo "Wrote ~/.aws/credentials and ~/.aws/config. Verifying..."
aws sts get-caller-identity
