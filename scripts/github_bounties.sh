#!/data/data/com.termux/files/usr/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  GitHub Bounty Scanner — no-agent cron                    ║
# ║  Cherche les issues bounty sur GitHub, filtre pertinence  ║
# ║  Sortie silencieuse si aucun nouveau résultat             ║
# ╚══════════════════════════════════════════════════════════════╝

CACHE_FILE="$HOME/.hermes/cache/github_bounties.txt"
TMP_FILE="$HOME/.hermes/cache/gh_bounties.json"
mkdir -p "$(dirname "$CACHE_FILE")"

# Broad search: bounty + open issues only
gh search issues "bounty is:open" --limit 30 --json url,title,repository,state,createdAt,labels,commentsCount,updatedAt > "$TMP_FILE" 2>/dev/null

if [ ! -s "$TMP_FILE" ]; then
    exit 0
fi

python3 << 'PYEOF'
import json, os, sys
from datetime import datetime, timezone

cache_file = os.environ['HOME'] + '/.hermes/cache/github_bounties.txt'
tmp_file = os.environ['HOME'] + '/.hermes/cache/gh_bounties.json'

with open(tmp_file) as f:
    results = json.load(f)

if not results:
    sys.exit(0)

seen = set()
if os.path.exists(cache_file):
    with open(cache_file) as f:
        seen = set(line.strip() for line in f if line.strip())

# Relevance keywords — issues matching ANY are kept
RELEVANCE = [
    'solana', 'agent', 'defi', 'crypto', 'trading', 'blockchain',
    'smart contract', 'usdc', 'usdt', 'API', 'web3', 'rust', 'python',
    'typescript', 'nft', 'token', 'dex', 'amm', 'oracle', 'bridge',
    'validator', 'staking', 'airdrop', 'spl', 'jupiter', 'raydium',
    'sdk', 'CLI', 'cli tool', 'automation', 'bot', 'scraper',
    '$', '💰', 'reward', 'prize', 'earn', 'grants',
]

SKIP = ['translation', 'translate', 'typo', 'watchlist', 'parity']

output = []
new_urls = []

for issue in results:
    title = issue.get('title', '')
    url = issue.get('url', '')
    repo = issue.get('repository', {}).get('nameWithOwner', '?')
    created = issue.get('createdAt', '')[:10]
    comments = issue.get('commentsCount', 0)
    
    title_lower = title.lower()
    
    # Skip
    if any(kw in title_lower for kw in SKIP):
        continue
    
    # Check relevance
    labels = [l.get('name','').lower() for l in issue.get('labels', []) if isinstance(l, dict)]
    all_text = title_lower + ' ' + ' '.join(labels)
    
    score = sum(1 for kw in RELEVANCE if kw.lower() in all_text)
    
    if score == 0:
        continue  # Not relevant enough
    
    # Amount from labels
    amount_labels = [l.get('name','') for l in issue.get('labels', []) if isinstance(l, dict) 
                     if any(c.isdigit() for c in l.get('name','')) 
                     and any(s in l.get('name','').upper() for s in ['$','USD','USDC'])]
    
    is_new = url not in seen
    marker = '🆕 ' if is_new else '  '
    amt = f' [{", ".join(amount_labels[:2])}]' if amount_labels else ''
    
    output.append((score, f"{marker}**{title}**{amt}\n   └─ {repo} | {created} | 💬{comments} | {url}"))
    
    if is_new:
        new_urls.append(url)

output.sort(key=lambda x: -x[0])
output_lines = [line for _, line in output]

# Save cache
all_urls = [i.get('url','') for i in results if i.get('url')]
with open(cache_file, 'w') as f:
    for u in all_urls:
        f.write(u + '\n')

if not output_lines:
    sys.exit(0)

now = datetime.now(timezone.utc)
new_count = len(new_urls)

print(f'🐙 **GitHub Bounty Scan** — {len(output_lines)} pertinents dont {new_count} nouveau(x)')
print('')
for line in output_lines[:10]:
    print(line)
if len(output_lines) > 10:
    print(f'  _(+{len(output_lines)-10} autres)_')
print('')
print(f'📅 {now.strftime("%d/%m %H:%M UTC")}')
PYEOF

rm -f "$TMP_FILE"
