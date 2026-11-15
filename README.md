# Self-hosted team chat: Ollama + Open WebUI

Ollama runs the models on the host. Open WebUI is the web interface, running in Docker.
Your team reaches it over HTTPS through Caddy, or over a VPN.

## Quick start (Ubuntu/Debian)

```bash
git clone <this repo> && cd <repo>
sudo ./setup.sh            # or: sudo ./setup.sh llama3.1:8b
```

The script installs Ollama, pulls a model, installs Docker if it's missing, and starts Open WebUI on `127.0.0.1:3000`.

**Make your admin account straight away.** The first account that signs up becomes admin. Open an SSH tunnel and sign up:

```bash
ssh -L 3000:127.0.0.1:3000 you@your-server    # then open http://localhost:3000
```

Then add your team in **Admin Settings → Users**, and turn off open sign-ups.

## Manual steps

1. Install Ollama: `curl -fsSL https://ollama.com/install.sh | sh` (Windows and Mac: installer at ollama.com)
2. Pull a model: `ollama pull qwen2.5:7b`. Choose a size that fits your hardware.
3. Test it: `ollama run qwen2.5:7b`
4. Install Docker, then run `docker compose up -d` in this folder.

## Why this differs from the usual `docker run -p 3000:8080` recipe

- **Ollama connections.** On Linux, Ollama listens on `127.0.0.1` only. From a bridged container, `host.docker.internal` goes to the Docker bridge IP, so the connection is refused and no models show up. Here the container uses host networking and connects to `127.0.0.1:11434` directly. You don't need to open Ollama to the network, and you shouldn't: it has no authentication.
- **Firewall bypass.** Docker-published ports go around UFW, so `-p 3000:8080` stays open to the internet even when UFW blocks port 3000. Here Open WebUI binds to `127.0.0.1:3000` and doesn't publish a port.

If you prefer the bridged `docker run` command, use `-p 127.0.0.1:3000:8080`. Then set `OLLAMA_HOST=0.0.0.0` for Ollama with `sudo systemctl edit ollama` and block port 11434 from outside.

## HTTPS with Caddy

You need a domain name pointed at your server's IP.

1. Install Caddy: `sudo apt install caddy`. This works on Ubuntu 24.04+ and Debian 12+. On older releases, use Caddy's own apt repo (caddyserver.com/docs/install).
2. Copy `Caddyfile.example` to `/etc/caddy/Caddyfile` and set your domain.
3. Run `sudo systemctl reload caddy`.
4. Open ports 80 and 443: `sudo ufw allow 80,443/tcp`. Caddy gets and renews the certificate itself.

**Alternative:** use Tailscale or WireGuard and skip the public exposure entirely. For a small team this is often the safest choice. With Tailscale, `tailscale serve --bg 3000` gives you HTTPS on your tailnet with no open ports.

## GPU (NVIDIA)

1. Install the driver and reboot: `sudo ubuntu-drivers autoinstall`
2. Check that `nvidia-smi` lists your GPU.
3. Load a model, then run `ollama ps`. The PROCESSOR column should say `100% GPU`.
4. A split like `40%/60% CPU/GPU` means the model doesn't fit in VRAM and will be much slower. Pick a smaller model or a more quantized one.

Only Ollama needs the GPU; Open WebUI doesn't. AMD GPUs work with Ollama through ROCm.

## Updating

```bash
./update.sh                  # Open WebUI: pull the new image and recreate. Data stays in the volume.
curl -fsSL https://ollama.com/install.sh | sh   # Ollama: rerun the installer
```

## Troubleshooting

- **No models in the dropdown:** run `curl http://127.0.0.1:11434/api/tags` on the host. It should list your models. Also check the connection URL under Admin Settings → Connections.
- **Logs:** `docker logs -f open-webui` and `journalctl -u ollama -f`.
