#!/usr/bin/env bash
# Shows why Open WebUI isn't listing Ollama models. Run on the server: ./diagnose.sh
# Read-only: it changes nothing.
set -u
hr() { printf '\n==> %s\n' "$1"; }

hr "1. Models Ollama has (host)"
if command -v ollama >/dev/null; then ollama list; else echo "ollama is not installed"; fi

hr "2. Ollama API on the host (127.0.0.1:11434)"
curl -fsS --max-time 5 http://127.0.0.1:11434/api/tags || echo "FAIL: Ollama is not answering on the host"
echo
systemctl is-active ollama 2>/dev/null | sed 's/^/ollama service: /'
ss -ltnp 2>/dev/null | grep 11434 || echo "nothing listening on 11434"

hr "3. Docker"
docker info --format 'Docker: {{.OperatingSystem}}' 2>/dev/null || echo "docker not reachable (try sudo)"
docker ps -a --filter name=open-webui --format 'container: {{.Names}}  status: {{.Status}}  image: {{.Image}}'
docker inspect open-webui --format 'network mode: {{.HostConfig.NetworkMode}}' 2>/dev/null
docker inspect open-webui --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -E '^(OLLAMA|HOST|PORT)'

hr "4. Ollama API from inside the container"
docker exec open-webui curl -fsS --max-time 5 http://127.0.0.1:11434/api/tags \
  || echo "FAIL: the container can't reach Ollama at 127.0.0.1:11434"
echo

hr "5. Recent Open WebUI log lines about Ollama/connections"
docker logs --tail 300 open-webui 2>&1 | grep -iE 'ollama|connect|error' | tail -20
