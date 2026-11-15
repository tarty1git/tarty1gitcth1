#!/usr/bin/env bash
# Pulls the newest Open WebUI image and recreates the container. Data stays in the volume.
set -euo pipefail
cd "$(dirname "$0")"
docker compose pull
docker compose up -d
docker image prune -f
