# shellcheck shell=bash
# Shared helpers for setup.sh, update.sh and diagnose.sh. Source this file; don't run it.

OLLAMA_URL=http://127.0.0.1:11434
WEBUI_URL=http://127.0.0.1:3000
export WEBUI_IMAGE=ghcr.io/open-webui/open-webui:main

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

has_systemd() { [[ -d /run/systemd/system ]]; }

ollama_up() { curl -fsS --max-time 3 "$OLLAMA_URL/api/version" >/dev/null 2>&1; }
webui_up()  { curl -fsS --max-time 3 "$WEBUI_URL/health" >/dev/null 2>&1; }

# wait_for <check-function> <seconds>
wait_for() {
  local fn=$1 secs=$2 i
  for ((i = 0; i < secs; i += 2)); do "$fn" && return 0; sleep 2; done
  "$fn"
}

# Starts Ollama via systemd, or directly when systemd isn't running (WSL, LXC, containers).
start_ollama() {
  ollama_up && return 0
  if has_systemd; then
    systemctl enable --now ollama >/dev/null 2>&1 || true
  else
    warn "systemd is not running; starting 'ollama serve' in the background (log: /var/log/ollama.log)."
    warn "It will not restart on reboot. Rerun setup.sh after a reboot."
    if id ollama >/dev/null 2>&1; then
      runuser -u ollama -- env HOME=/usr/share/ollama nohup ollama serve >>/var/log/ollama.log 2>&1 &
    else
      nohup ollama serve >>/var/log/ollama.log 2>&1 &
    fi
  fi
  wait_for ollama_up 60
}

# Prints the Ollama URL(s) Open WebUI has saved in its database.
stored_ollama_urls() {
  docker exec open-webui python3 -c "
import sqlite3
c = sqlite3.connect('/app/backend/data/webui.db')
r = c.execute(\"select value from config where key='ollama.base_urls'\").fetchone()
print(r[0] if r else '')" 2>/dev/null
}

# The original 'docker run' guide saves host.docker.internal:11434. With host networking
# that address can't reach Ollama, so it's rewritten to 127.0.0.1. Other custom URLs
# (such as a remote Ollama server) are left alone.
# Also turns off the default OpenAI connection when it has no API key: it can't work
# and only fills the log with errors.
fix_stored_ollama_url() {
  local changed
  changed=$(docker exec open-webui python3 -c "
import sqlite3
c = sqlite3.connect('/app/backend/data/webui.db')
get = lambda k: (c.execute('select value from config where key=?', (k,)).fetchone() or [''])[0]
out = []
if 'host.docker.internal' in str(get('ollama.base_urls')):
    out.append('Ollama URL %s -> 127.0.0.1' % get('ollama.base_urls'))
    for k in ('ollama.base_urls', 'rag.ollama.base_url'):
        c.execute(\"update config set value = replace(value, 'host.docker.internal', '127.0.0.1') where key = ?\", (k,))
if str(get('openai.enable')) == 'true' and str(get('openai.api_keys')).replace(' ', '') in ('', '[\"\"]'):
    out.append('turned off the OpenAI connection (no API key)')
    c.execute(\"update config set value = 'false' where key = 'openai.enable'\")
c.commit()
print('; '.join(out))") || return 0
  [[ -n $changed ]] || return 0
  log "Fixing saved settings: $changed"
  docker restart open-webui >/dev/null
  wait_for webui_up 300 || die "Open WebUI didn't come back after the restart. Check: docker logs open-webui"
}
