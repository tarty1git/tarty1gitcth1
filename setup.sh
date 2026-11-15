#!/usr/bin/env bash
# Installs Ollama, pulls a model and starts Open WebUI. Safe to run again.
# Also migrates an install made with the plain 'docker run' command (keeps all data).
#
# Usage: sudo ./setup.sh [model ...]     default model: qwen2.5:7b
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

MODELS=("${@:-qwen2.5:7b}")

[[ $EUID -eq 0 ]] || die "Run as root: sudo $0 $*"
[[ $(uname -s) == Linux ]] || die "This script is for Linux servers. On Mac/Windows, use the installers at ollama.com and see the README's Docker Desktop section."

# --- Prerequisites ----------------------------------------------------------
missing=()
for c in curl zstd; do command -v "$c" >/dev/null || missing+=("$c"); done
if ((${#missing[@]})); then
  log "Installing ${missing[*]}"   # The Ollama installer needs zstd to unpack.
  if command -v apt-get >/dev/null; then
    apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}" ca-certificates >/dev/null
  elif command -v dnf >/dev/null; then
    dnf install -y -q "${missing[@]}"
  else
    die "Please install: ${missing[*]}"
  fi
fi

# --- Ollama -----------------------------------------------------------------
if ! command -v ollama >/dev/null; then
  log "Installing Ollama"
  curl -fsSL https://ollama.com/install.sh | sh
fi

log "Starting Ollama"
start_ollama || die "Ollama isn't responding on $OLLAMA_URL. Check: journalctl -u ollama -n 50 (or /var/log/ollama.log)"
echo "Ollama $(curl -fsS "$OLLAMA_URL/api/version" | sed 's/.*"version":"\([^"]*\)".*/\1/') is running."

if has_systemd && systemctl show ollama -p Environment 2>/dev/null | grep -q 'OLLAMA_HOST=0.0.0.0'; then
  warn "Ollama listens on all interfaces (OLLAMA_HOST=0.0.0.0). It has no login. Firewall port 11434, or remove that override."
fi

for m in "${MODELS[@]}"; do
  log "Pulling model $m"
  ollama pull "$m"
done

# --- Docker -----------------------------------------------------------------
if ! command -v docker >/dev/null; then
  log "Installing Docker"
  curl -fsSL https://get.docker.com | sh
fi
if ! docker info >/dev/null 2>&1; then
  has_systemd && systemctl enable --now docker >/dev/null 2>&1 || true
  docker info >/dev/null 2>&1 || die "The Docker daemon isn't running. Start it and rerun this script."
fi
if docker info --format '{{.OperatingSystem}}' 2>/dev/null | grep -qi 'docker desktop'; then
  die "Docker Desktop detected. Host networking won't reach Ollama there. See the README's Docker Desktop section."
fi
docker compose version >/dev/null 2>&1 || die "The Docker Compose plugin is missing. Install it: apt-get install docker-compose-plugin"

# --- Open WebUI -------------------------------------------------------------
log "Pulling the Open WebUI image (about 2-5 GB, can take a few minutes)"
docker compose pull -q

# A container created by the plain 'docker run' command blocks the name. Its data is in the volume, so it can go.
if docker container inspect open-webui >/dev/null 2>&1 &&
   [[ -z $(docker container inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' open-webui) ]]; then
  mounts=$(docker container inspect -f '{{range .Mounts}}{{.Name}}:{{.Destination}} {{end}}' open-webui)
  [[ $mounts == *"open-webui:/app/backend/data"* ]] ||
    die "A container named open-webui exists but doesn't keep its data in the 'open-webui' volume ($mounts). Back it up, remove it, and rerun."
  log "Replacing the old 'docker run' container (data in the open-webui volume is kept)"
  docker rm -f open-webui >/dev/null
fi

# An earlier version of these files stored data in '<folder>_open-webui'. Carry it over.
legacy="$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')_open-webui"
if docker volume inspect "$legacy" >/dev/null 2>&1; then
  if docker volume inspect open-webui >/dev/null 2>&1; then
    warn "Both volumes 'open-webui' and '$legacy' exist. Using 'open-webui'. If your accounts are missing, see 'Moving data between volumes' in the README."
  else
    log "Copying data from volume '$legacy' to 'open-webui'"
    docker compose down >/dev/null 2>&1 || true
    docker volume create open-webui >/dev/null
    docker run --rm --entrypoint sh -v "$legacy":/from:ro -v open-webui:/to "$WEBUI_IMAGE" -c 'cp -a /from/. /to/'
    echo "Done. The old volume is left in place; remove it later with: docker volume rm $legacy"
  fi
fi

log "Starting Open WebUI"
docker volume create open-webui >/dev/null
docker compose up -d
echo "Waiting for it to become healthy (the first start downloads a few small models)..."
wait_for webui_up 300 || die "Open WebUI didn't become healthy. Check: docker logs open-webui"

fix_stored_ollama_url

# --- Verify -----------------------------------------------------------------
log "Checking that Open WebUI can reach Ollama"
tags=$(docker exec open-webui curl -fsS --max-time 10 "$OLLAMA_URL/api/tags") ||
  die "The Open WebUI container can't reach Ollama at $OLLAMA_URL. Run ./diagnose.sh"
count=$(grep -o '"name"' <<<"$tags" | wc -l)
echo "OK: Open WebUI reaches Ollama and sees $count model(s)."
urls=$(stored_ollama_urls)
[[ -z $urls || $urls == *127.0.0.1:11434* || $urls == *localhost:11434* ]] ||
  warn "Open WebUI is set to use $urls. If models are missing, check Admin Settings > Connections."

cat <<MSG

All set. Open WebUI is running on $WEBUI_URL (this machine only).

Next steps:
  1. Create your admin account now. The first account to sign up becomes admin,
     and public sign-up closes after that. From your laptop:
         ssh -L 3000:127.0.0.1:3000 <user>@<this-server>
     then open http://localhost:3000
  2. Give your team access: put it behind Caddy (Caddyfile.example) or a VPN (Tailscale).
  3. Add teammates in Admin Panel > Users > "+" (Add User).
MSG
