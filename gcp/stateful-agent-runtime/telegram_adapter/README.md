# Telegram Status-Only Adapter

This package implements the AI Operations Platform Telegram operator channel
for status reads only.

## Supported Commands

- `/status`
- `/health`
- `/whoami`
- `/help`

The adapter does not implement `/ask`, GitHub write actions, PR workflows,
Terraform actions, shell execution, browser automation, MCP, DevBox execution,
self-upgrade flows, interactive approvals, or incident workflows.

## Runtime Model

- runs on the private Stateful VM as `openclaw-telegram`
- reaches OpenClaw through the VM-local endpoint only
- reads the bot token from `/run/openclaw/secrets/TELEGRAM_BOT_TOKEN`
- uses an environment-specific Telegram chat allowlist
- is disabled by default in Terraform

Do not commit real bot tokens, real chat IDs, raw logs, local Terraform files,
or private operator notes.

## Local Tests

```bash
python -m unittest discover -s telegram_adapter/tests
```
