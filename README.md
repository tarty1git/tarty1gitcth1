# Self-hosted team chat: Ollama + Open WebUI

Ollama runs the models on the host. Open WebUI is the web interface, running in Docker.
Your team reaches it over HTTPS through Caddy, or over a VPN. Neither service is reachable
from the network directly: both listen on `127.0.0.1` only.

| File | What it does |
|---|---|
| `setup.sh` | Installs everything, pulls models, starts Open WebUI and checks it can reach Ollama. Safe to run again. Also migrates an install made with the plain `docker run` command. |
| `update.sh` | Updates Open WebUI (`--ollama` updates Ollama too). Accounts, chats and logins are kept. |
| `diagnose.sh` | Read-only health check. Explains why models are missing, and whether a port is exposed. |
| `docker-compose.yml` | The Open WebUI container. |
| `Caddyfile.example` | HTTPS reverse proxy. |

## Quick start (Ubuntu/Debian server)

```bash
git clone <this repo> ai && cd ai
sudo ./setup.sh                          # default model: qwen2.5:7b
sudo ./setup.sh llama3.1:8b qwen2.5:7b   # or name one or more models
```

Then, **straight away**, create the admin account. The first account to sign up becomes
admin, and public sign-up closes after that. From your laptop:

```bash
ssh -L 3000:127.0.0.1:3000 you@your-server     # then open http://localhost:3000
```

Add teammates in **Admin Panel → Users → +** (Add User). Then give them a way in: [Caddy](#https-with-caddy) or a [VPN](#vpn-instead).

Choosing a model: on a CPU or a GPU with 8 GB, use a 7–8B model. With 16–24 GB of VRAM,
14B models fit. Very small models, such as `qwen2.5:0.5b`, are fast but give weak answers.

## What setup.sh does

1. Installs `curl` and `zstd` if missing. The current Ollama installer fails without `zstd`.
2. Installs Ollama and starts it with systemd. Where systemd isn't running (WSL, LXC, containers), it starts `ollama serve` in the background instead.
3. Pulls the models you named.
4. Installs Docker if missing, and refuses to continue on Docker Desktop (see below).
5. If you used the original `docker run -p 3000:8080 ...` command before, it replaces that container. Your accounts and chats carry over, because both use the `open-webui` volume.
6. Starts Open WebUI and waits for it to become healthy.
7. Repairs saved settings that break this setup: a saved Ollama URL of `host.docker.internal:11434`, and the OpenAI connection when it has no key.
8. Checks from inside the container that it can reach Ollama, and reports how many models it sees.

## Why this differs from the usual `docker run -p 3000:8080` recipe

Each item below was reproduced on Ubuntu 24.04 with Open WebUI 0.13 and Ollama 0.40:

- **No models with the original command.** On Linux, Ollama listens on `127.0.0.1` only. From a bridged container, `host.docker.internal` goes to the Docker bridge IP (`172.17.0.1`), so the connection is refused and the model list is empty. Here the container uses host networking and connects to `127.0.0.1:11434`. You don't need to open Ollama to the network, and you shouldn't: it has no login.
- **Changing `OLLAMA_BASE_URL` later does nothing.** Open WebUI reads it only on the first start, then uses the URL saved in its database. `setup.sh` repairs the known-bad value. Otherwise, change it in Admin Settings → Connections.
- **Regular users see no models.** Open WebUI shows models only to admins until each one is shared. For a small team, `BYPASS_MODEL_ACCESS_CONTROL=True` in the compose file makes every model visible to every signed-in user. Remove that line if you want per-model access control.
- **Everyone was logged out after each update.** The session-signing key lived inside the container. It now lives in the data volume (`WEBUI_SECRET_KEY_FILE`).
- **The firewall doesn't block `-p 3000:8080`.** Ports Docker publishes skip UFW's rules, so port 3000 would be open to the internet even with UFW blocking it. Here Open WebUI binds to `127.0.0.1:3000` and publishes no port.

## HTTPS with Caddy

You need a domain name whose DNS points at your server's IP.

1. Install Caddy from its official repository (current version, automatic updates):
   ```bash
   sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
   curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
   curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
   sudo apt update && sudo apt install caddy
   ```
   (`sudo apt install caddy` alone also works on Ubuntu 24.04, but installs an old 2.6 release.)
2. `sudo cp Caddyfile.example /etc/caddy/Caddyfile`, then replace `ai.yourdomain.com` with your domain.
3. Run `sudo systemctl reload caddy`.
4. Open ports 80 and 443: `sudo ufw allow 80,443/tcp`. Caddy gets and renews the certificate itself.

Caddy forwards WebSockets automatically, and Open WebUI needs them for streaming replies. No extra config is required.

## VPN instead

With Tailscale or WireGuard the server is never exposed publicly. For a small team that's
often the safest choice. With Tailscale installed on the server and your team's devices,
`sudo tailscale serve --bg 3000` gives HTTPS on your tailnet with no open ports.

## Docker Desktop (Mac, Windows)

Host networking doesn't reach the real machine under Docker Desktop. Install Ollama with
the installer from ollama.com, then edit `docker-compose.yml`:

- delete the `network_mode`, `HOST` and `PORT` lines
- add `ports: ["127.0.0.1:3000:8080"]` under the service
- set `OLLAMA_BASE_URL: http://host.docker.internal:11434`

Then run `docker volume create open-webui` and `docker compose up -d`. (Not covered by the
tests below; Docker Desktop resolves `host.docker.internal` itself.)

## GPU (NVIDIA)

1. Install the driver and reboot: `sudo ubuntu-drivers autoinstall`
2. Check that `nvidia-smi` lists your GPU.
3. Load a model, then run `ollama ps`. The PROCESSOR column should say `100% GPU`.
4. A split like `40%/60% CPU/GPU` means the model doesn't fit in VRAM and will be much slower. Pick a smaller model or a more quantized one.

Only Ollama needs the GPU; Open WebUI doesn't. AMD GPUs work with Ollama through ROCm.
If you install the driver after Ollama, restart Ollama: `sudo systemctl restart ollama`.

## Updating

```bash
sudo ./update.sh            # Open WebUI only
sudo ./update.sh --ollama   # Open WebUI and Ollama
```

## Troubleshooting

Run `sudo ./diagnose.sh` first. It checks each link in the chain and tells you which one is broken.

- **Logs:** `docker logs -f open-webui`, `journalctl -u ollama -f`
- **Add a model:** `ollama pull <name>`, then reload the page. No restart is needed.
- **Moving data between volumes:** an early version of these files stored data in a volume named `<folder>_open-webui`. `setup.sh` copies it to `open-webui` automatically, unless both exist. In that case, to use the old one:
  ```bash
  docker compose down
  docker run --rm --entrypoint sh -v <folder>_open-webui:/from:ro -v open-webui:/to \
    ghcr.io/open-webui/open-webui:main -c 'rm -rf /to/* /to/.[!.]* ; cp -a /from/. /to/'
  docker compose up -d
  ```

## How this was tested

Tested on Ubuntu 24.04 (no systemd, no GPU) with Docker 29, Ollama 0.40.16, Open WebUI 0.13.3 and `qwen2.5:0.5b`:

- Fresh install from nothing: Ollama, zstd and the volumes all removed first. Run a second time to check it's safe to rerun.
- Migration from the original `docker run` command (empty model list reproduced first). The old admin account carried over and models appeared.
- In a real browser: first sign-up becomes admin, the model appears in the picker, chat replies. Done directly and through Caddy over HTTPS.
- A regular user created by the admin sees models and can chat.
- Logins survive `docker compose up -d --force-recreate`.
- Both ports confirmed bound to `127.0.0.1` only; a second public sign-up is refused.

Not tested: GPU, Docker Desktop, real Let's Encrypt certificates (Caddy was tested with a local certificate), and Tailscale.
