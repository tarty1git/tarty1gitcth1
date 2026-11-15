#!/usr/bin/env bash
# Updates Open WebUI to the newest image. Data stays in the 'open-webui' volume.
# Usage: sudo ./update.sh [--ollama]    --ollama also updates Ollama itself
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

if [[ ${1:-} == --ollama ]]; then
  log "Updating Ollama"
  curl -fsSL https://ollama.com/install.sh | sh
  start_ollama || die "Ollama isn't responding after the update."
fi

log "Updating Open WebUI"
docker compose pull -q
docker compose up -d
wait_for webui_up 300 || die "Open WebUI didn't become healthy. Check: docker logs open-webui"
fix_stored_ollama_url
docker image prune -f >/dev/null
echo "Open WebUI $(curl -fsS "$WEBUI_URL/api/version" | sed 's/.*"version":"\([^"]*\)".*/\1/') is running."
