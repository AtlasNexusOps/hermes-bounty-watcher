#!/data/data/com.termux/files/usr/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Superteam Bounty Scanner — no-agent cron                  ║
# ║  Appelle l'API Superteam, filtre par agentAccess           ║
# ║  Sortie silencieuse si aucun nouveau bounty pertinent      ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Cron: no_agent=true, script only → stdout delivered verbatim
# Fréquence recommandée: every 6h

API_URL="https://earn.superteam.fun/api/listings?type=bounty&take=50"
CACHE_FILE="$HOME/.hermes/cache/superteam_bounties.txt"
TMP_FILE="$HOME/.hermes/cache/superteam_tmp.json"
mkdir -p "$(dirname "$CACHE_FILE")"

# Fetch to temp file
curl -sfL "$API_URL" -H "User-Agent: AtlasNexus-BountyScanner/1.0" -o "$TMP_FILE" 2>/dev/null

if [ ! -s "$TMP_FILE" ]; then
    echo "⚠️ Superteam API: pas de données"
    rm -f "$TMP_FILE"
    exit 0
fi

# Process with Python
python3 << 'PYEOF'
import json, sys, os
from datetime import datetime, timezone

cache_file = os.environ['HOME'] + '/.hermes/cache/superteam_bounties.txt'
tmp_file = os.environ['HOME'] + '/.hermes/cache/superteam_tmp.json'

with open(tmp_file) as f:
    data = json.load(f)

# Load previously seen bounty IDs
seen = set()
if os.path.exists(cache_file):
    with open(cache_file) as f:
        seen = set(line.strip() for line in f if line.strip())

now = datetime.now(timezone.utc)
agent_allowed = []
human_only = []

for b in data:
    bid = b.get('id', '')
    if not bid:
        continue
    
    deadline_str = b.get('deadline', '')
    try:
        deadline = datetime.fromisoformat(deadline_str.replace('Z', '+00:00'))
        hours_left = (deadline - now).total_seconds() / 3600
    except:
        hours_left = 999
    
    # Skip expired
    if hours_left <= 0:
        continue
    
    entry = {
        'id': bid,
        'title': b.get('title', '?'),
        'reward': b.get('rewardAmount', 0),
        'agent': b.get('agentAccess', 'HUMAN_ONLY'),
        'deadline': deadline_str[:10],
        'hours_left': int(hours_left),
        'submissions': b.get('_count', {}).get('Submission', 0),
        'sponsor': b.get('sponsor', {}).get('name', '?'),
    }
    
    if entry['agent'] == 'AGENT_ALLOWED':
        agent_allowed.append(entry)
    else:
        human_only.append(entry)

# Save all seen IDs
with open(cache_file, 'w') as f:
    for b in data:
        if b.get('id'):
            f.write(b['id'] + '\n')

total_active = len(agent_allowed) + len(human_only)

if total_active == 0:
    sys.exit(0)

# Build output
lines = []
lines.append(f'🏆 **Superteam Bounties** — {total_active} actifs')
lines.append('')

# AGENT ALLOWED section
if agent_allowed:
    lines.append(f'### 🤖 AGENT ALLOWED ({len(agent_allowed)})')
    for b in sorted(agent_allowed, key=lambda x: x['hours_left']):
        marker = '🆕 ' if b['id'] not in seen else '  '
        reward_str = f"${b['reward']:,}" if b['reward'] else '?'
        lines.append(f"{marker}**{b['title']}** — {reward_str} | ⏰ {b['hours_left']}h | {b['submissions']} subm | {b['sponsor']}")
    lines.append('')

# HUMAN ONLY — only interesting ones
if human_only:
    interesting = [b for b in human_only if b['reward'] >= 1000 and b['submissions'] < 50]
    if interesting:
        lines.append(f'### 👤 HUMAN ONLY — Pertinents ({len(interesting)}/{len(human_only)})')
        for b in sorted(interesting, key=lambda x: -x['reward'])[:5]:
            marker = '🆕 ' if b['id'] not in seen else '  '
            lines.append(f"{marker}**{b['title']}** — ${b['reward']:,} | ⏰ {b['hours_left']}h | {b['submissions']} subm")
        lines.append(f'  _(+{len(human_only)-len(interesting)} autres filtrés)_')
        lines.append('')

lines.append(f'📅 {now.strftime("%d/%m %H:%M UTC")}')

print('\n'.join(lines))
PYEOF

rm -f "$TMP_FILE"
