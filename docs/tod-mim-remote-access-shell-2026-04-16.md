# TOD MIM Remote Access Shell

This objective uses the existing TOD UI and MIM command surface as the remote entrypoint. It does not expose a raw listener directly to the Internet.

## What it does

- Starts a local-only TOD UI instance with `Start-TOD-UI.ps1 -LocalOnly`
- Installs `cloudflared` into `tools/cloudflared/cloudflared.exe` if it is not already available on `PATH`
- Launches a Cloudflare quick tunnel to the local TOD UI
- Validates both `GET /api/project-status` and `POST /api/mim-command` locally and through the remote tunnel URL
- Writes live status artifacts to `tod/out/remote-access/mim-shell`

## Start

```powershell
.\scripts\Start-TODMimRemoteAccessShell.ps1
```

The status artifact is written to `tod/out/remote-access/mim-shell/mim-remote-access-shell.latest.json` and includes the current public URL.

## Stop

```powershell
.\scripts\Stop-TODMimRemoteAccessShell.ps1
```

## Health evidence

- Remote shell status: `tod/out/remote-access/mim-shell/mim-remote-access-shell.latest.json`
- Human-readable summary: `tod/out/remote-access/mim-shell/mim-remote-access-shell.latest.md`
- Cloudflare logs: `tod/out/remote-access/mim-shell/logs/cloudflared.stdout.log`
- Local UI logs: `tod/out/remote-access/mim-shell/logs/tod-ui.stdout.log`

## Mobile usability

The existing TOD UI already ships a viewport meta tag and responsive media-query layout in `ui/index.html`. The remote access shell validates those markers before it publishes success.

## Constraints

- This uses a secure outbound Cloudflare tunnel only.
- It preserves the existing TOD UI and MIM command behavior by tunneling the supported local API surface.
- Cloudflare quick tunnels are suitable for validation and operator use, but they are not a named production tunnel with an SLA-backed hostname.