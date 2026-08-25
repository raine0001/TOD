# TODBOX fixed service IP and startup verification

This emergency infrastructure repair gives TODBOX a stable LAN service address while retaining DHCP for the Starlink-provided default route and DNS.

- Host guard: `tod-ai-01`
- Interface guard: `enp7s0f0`
- MAC guard: `08:60:6e:00:62:7d`
- Fixed service address: `192.168.1.10/24`
- DHCP: retained
- Primary model port: `8101`

The verifier checks carrier, fixed address, default route, gateway routing, the portable `network-online.target` plus an enabled wait-online implementation, SSH, boot-enabled MIM/TOD model services, local ports, the local Qwen3 model API, public MIM gateway health, and AgentMIM readiness. It writes atomic evidence to `/var/lib/todbox-connectivity/latest.json` and one file per Linux boot ID.

The same 15-minute patrol also writes TOD's authoritative, secret-free system inventory to `/var/lib/todbox-connectivity/system-inventory.latest.json`. The inventory derives service ownership, dependencies, unit fingerprints, active models, the AgentMIM gateway hostname, and tunnel health from live evidence. It deliberately records the tunnel origin as unasserted unless a source proves it. Configuration changes create change-only records under `/var/lib/todbox-connectivity/inventory-changes/`.

Ask the evidence layer which connection serves forum image generation:

```bash
todbox-system-inventory-query forum_image_generation
```

Update this inventory capability on an already-configured TODBOX:

```bash
sudo bash /home/tod/todbox_network_startup_v1/install-system-inventory.sh
```

The Ollama GPU readiness gate handles a separate reboot race observed on August 25, 2026: Docker started `mim-ollama` before NVIDIA access was usable, NVML failed inside the container, and Ollama silently loaded `qwen2.5vl:3b` on CPU. The gate waits for the resident GPU services, restarts only `mim-ollama` when its container cannot initialize NVIDIA, warms the vision model, and requires `size_vram > 0` before the creative worker starts. It rechecks every 15 minutes and writes `/var/lib/todbox-connectivity/ollama-gpu-readiness.latest.json`.

Install or update only that gate on an already-configured TODBOX:

```bash
sudo bash /home/tod/todbox_network_startup_v1/install-ollama-gpu-readiness.sh
```

Install from the TODBOX console after copying this directory to `/home/tod/todbox_network_startup_v1`:

```bash
sudo bash /home/tod/todbox_network_startup_v1/install.sh
```

Rollback:

```bash
sudo /usr/local/sbin/todbox-network-startup-rollback
```

This bundle is Codex-authored emergency infrastructure repair and provides no TOD independence credit.
