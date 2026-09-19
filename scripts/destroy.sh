#!/usr/bin/env bash
# Destroys the AWS stack, then checks the region for any leftover ghosthref instance. Run from repo root.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../terraform"
terraform destroy -auto-approve

echo ""
echo "Sweeping us-east-1 for anything still tagged ghosthref-*..."
LEFTOVER=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=ghosthref-*" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0],State.Name]' \
  --output text)

if [ -z "$LEFTOVER" ]; then
  echo "Clean — no ghosthref instances remain."
else
  echo "WARNING: instances still exist:"
  echo "$LEFTOVER"
  exit 1
fi
