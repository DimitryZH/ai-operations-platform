# Telegram Status-Only Operator Channel

The Telegram adapter is an optional operator channel for status reads only. It
runs on the private Stateful VM and talks to OpenClaw through the VM-local
runtime endpoint.

## Scope

Supported commands:

- `/status`
- `/health`
- `/whoami`
- `/help`

Unsupported capabilities:

- `/ask`
- GitHub commands or PR/write mode
- Terraform commands
- shell execution
- browser automation
- MCP or DevBox execution
- OpenClaw self-upgrade
- interactive approval workflows
- incident workflows

## Security Posture

- OpenClaw remains private behind the VM and IAP boundary.
- Telegram traffic reaches only the adapter; the adapter reaches OpenClaw
  through `http://127.0.0.1:8080`.
- Bot token and allowed chat IDs are environment-specific.
- No real token or real chat ID belongs in tracked files.
- Terraform keeps the adapter disabled by default.

## Deployment Defaults

The Terraform module exposes `telegram_adapter_enabled = false` by default.
When enabled in a reviewed environment, it installs the package, writes a
systemd unit, maps `TELEGRAM_BOT_TOKEN` from Secret Manager, and starts
`openclaw-telegram-adapter.service`.
