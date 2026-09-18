#!/usr/bin/env bash
# Prints this month's AWS spend so far. Run from repo root.
# Created: 2026-09-16

set -euo pipefail

START=$(date -u +%Y-%m-01)
END=$(date -u +%Y-%m-%d)

aws ce get-cost-and-usage \
  --time-period Start="$START",End="$END" \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --query 'ResultsByTime[0].Total.UnblendedCost.[Amount,Unit]' \
  --output text
