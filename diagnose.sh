#!/usr/bin/env bash
# Finds out why Open WebUI isn't showing Ollama models. Run on the server: sudo ./diagnose.sh
# Read-only: it changes nothing.
set -u
cd "$(dirname "$0")" || exit 1
source ./lib.sh
problems=0
bad() { printf '  PROBLEM: %s\n' "$*"; problems=$((problems + 1)); }
ok()  { printf '  ok: %s\n' "$*"; }

log "Ollama on the host"
if ! command -v ollama >/dev/null; then bad "Ollama isn't installed. Run setup.sh"
elif ! ollama_up; then bad "Ollama isn't answering on $OLLAMA_URL. Try: systemctl restart ollama; journalctl -u ollama -n 50"
else
  n=$(ollama list 2>/dev/null | tail -n +2 | wc -l)
  ((n > 0)) && ok "Ollama is running with $n model(s): $(ollama list | tail -n +2 | awk '{print $1}' | paste -sd' ')" \
            || bad "Ollama has no models. Run: ollama pull qwen2.5:7b"
fi

log "Docker and the Open WebUI container"
if ! docker info >/dev/null 2>&1; then bad "Docker isn't reachable (run with sudo, or start the daemon)"
else
  os=$(docker info --format '{{.OperatingSystem}}')
  [[ $os == *"Docker Desktop"* ]] && bad "Docker Desktop: host networking won't reach Ollama. See the README's Docker Desktop section."
  if ! docker container inspect open-webui >/dev/null 2>&1; then bad "No open-webui container. Run setup.sh"
  else
    ok "container: $(docker container inspect -f '{{.State.Status}}, network {{.HostConfig.NetworkMode}}' open-webui)"
    [[ -z $(docker container inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' open-webui) ]] &&
      bad "The container was made with plain 'docker run', not this compose file. Rerun setup.sh to migrate it."
    env=$(docker container inspect open-webui --format '{{range .Config.Env}}{{println .}}{{end}}')
    grep -q '^BYPASS_MODEL_ACCESS_CONTROL=True' <<<"$env" ||
      printf '  note: non-admin users only see models shared with them (Admin Settings > Models).\n'
    webui_up && ok "Open WebUI is healthy on $WEBUI_URL" || bad "Open WebUI isn't answering on $WEBUI_URL. See: docker logs open-webui"

    log "Connection from Open WebUI to Ollama"
    urls=$(stored_ollama_urls)
    echo "  saved Ollama URL(s): ${urls:-unknown}"
    for u in $(tr -d '[]"' <<<"$urls" | tr ',' ' '); do
      if docker exec open-webui curl -fsS --max-time 5 "$u/api/tags" >/dev/null 2>&1; then ok "container reaches $u"
      else bad "container can't reach $u. Rerun setup.sh, or set $OLLAMA_URL in Admin Settings > Connections."; fi
    done
  fi
fi

log "Exposure"
listeners=$(awk 'NR>1 && $4=="0A" {print $2}' /proc/net/tcp 2>/dev/null)
for p in 3000 11434; do
  hex=$(printf '%04X' $p)
  if grep -q "^00000000:$hex$" <<<"$listeners"; then bad "port $p listens on ALL interfaces. Anyone who can reach this server can use it."
  elif grep -q ":$hex$" <<<"$listeners"; then ok "port $p is local-only"; fi
done

log "Recent Open WebUI errors"
docker logs --since 30m open-webui 2>&1 | grep -iE 'error|exception' | grep -viE "SyntaxWarning|FutureWarning|SAWarning" | tail -8 || true

echo
((problems == 0)) && echo "No problems found. If a user still sees no models, have them reload the page and sign in again." \
                  || echo "$problems problem(s) found above."
