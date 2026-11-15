#!/usr/bin/env bash
# Installs Ollama, pulls a model and starts Open WebUI (Ubuntu/Debian).
# Usage: sudo ./setup.sh [model]     default model: qwen2.5:7b
set -euo pipefail

MODEL="${1:-qwen2.5:7b}"
cd "$(dirname "$0")"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0 $*" >&2
  exit 1
fi

if ! command -v ollama >/dev/null; then
  echo "==> Installing Ollama"
  curl -fsSL https://ollama.com/install.sh | sh
fi

echo "==> Waiting for Ollama"
for _ in $(seq 1 30); do
  curl -fsS http://127.0.0.1:11434/api/version >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS http://127.0.0.1:11434/api/version >/dev/null || { echo "Ollama is not responding on 127.0.0.1:11434" >&2; exit 1; }

echo "==> Pulling model $MODEL"
ollama pull "$MODEL"

if ! command -v docker >/dev/null; then
  echo "==> Installing Docker"
  curl -fsSL https://get.docker.com | sh
fi

echo "==> Starting Open WebUI"
docker compose up -d

cat <<MSG

Done. Open WebUI is on http://127.0.0.1:3000 (this machine only).
Next:
  1. Make your admin account NOW: the first account to sign up becomes admin.
     From your laptop: ssh -L 3000:127.0.0.1:3000 <user>@<server>, then open http://localhost:3000
  2. Put it behind Caddy (see Caddyfile.example) or a VPN such as Tailscale.
  3. Turn off open sign-ups in Admin Settings once your team has accounts.
MSG
