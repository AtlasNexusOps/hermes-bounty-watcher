# Hermes Bounty Watcher 🏆

Autonomous bounty scanner pipeline powered by [Hermes Agent](https://github.com/NousResearch/hermes-agent).

Scans Superteam Earn and GitHub for freelance bounties every 3-6 hours. Filters by relevance, deduplicates, and delivers results to Telegram — silently when there's nothing new.

## How It Works

```
cron (Hermes Agent) → shell script → API fetch → Python filter → Telegram delivery
```

- **Zero LLM cost for scanning** — scripts run with `no_agent: true`, no tokens consumed
- **Silent when empty** — zero-delivery watchdog pattern; only notified when something relevant appears
- **Persistent dedup cache** — tracks seen bounties, highlights new ones with 🆕

## Platforms Scanned

| Platform | Frequency | Filter |
|----------|-----------|--------|
| Superteam Earn | Every 6h | AGENT_ALLOWED + crypto/solana relevance |
| GitHub Issues | Every 3h | Bounty label + keyword scoring |

## Quick Start

### Prerequisites

- Hermes Agent installed: `pip install hermes-agent`
- GitHub CLI: `gh auth login`
- Telegram bot connected to Hermes Agent

### Install

```bash
mkdir -p ~/.hermes/scripts
cp scripts/superteam_bounties.sh ~/.hermes/scripts/
cp scripts/github_bounties.sh ~/.hermes/scripts/
chmod +x ~/.hermes/scripts/*.sh

mkdir -p ~/.hermes/cache
```

### Schedule

```bash
hermes cron add "every 360m" \
  --name "Superteam Bounties" \
  --script ~/.hermes/scripts/superteam_bounties.sh \
  --no-agent \
  --deliver origin

hermes cron add "every 180m" \
  --name "GitHub Bounty Scan" \
  --script ~/.hermes/scripts/github_bounties.sh \
  --no-agent \
  --deliver origin
```

### Verify

```bash
hermes cron list
```

You'll receive your first digest in Telegram at the next scheduled interval.

## Customization

Edit the `RELEVANCE` and `SKIP` lists in each script to match your domain:

```python
RELEVANCE = ['solana', 'defi', 'rust', 'python', ...]
SKIP = ['translation', 'typo', ...]
```

## Architecture

Both scanners follow the same pattern:

1. **Fetch** — curl/gh CLI queries the source API
2. **Filter** — Python script scores results against relevance keywords
3. **Dedup** — compares against persistent cache, marks new entries
4. **Format** — produces Markdown output for Telegram rendering
5. **Deliver or stay silent** — Hermes Agent's cron delivers stdout; empty output = no message

## License

MIT — use it, fork it, ship it.
