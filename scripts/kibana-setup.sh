#!/usr/bin/env bash
# Creates the ghosthref-access data view in Kibana. Run from repo root.

set -eu
KB="${KIBANA_HOST:-http://localhost:5601}"

echo "Waiting for Kibana..."
until curl -sf "$KB/api/status" >/dev/null; do sleep 2; done

curl -sf -X POST "$KB/api/data_views/data_view" \
  -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
  -d '{"data_view": {"title": "ghosthref-access", "name": "ghosthref-access", "timeFieldName": "time"}}' \
  >/dev/null || echo "Data view already exists, skipping."

echo "Kibana data view ready. Open http://localhost:5601 to build the dashboard."
