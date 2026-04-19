#!/bin/bash
# Claude Code Stats Reporter - daily sender (macOS/Linux)
set -euo pipefail

source "$HOME/.claude-stats-reporter/config"
export USERNAME

LOG_FILE="$HOME/.claude-stats-reporter/last_run.log"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"; }

PAYLOAD=$(python3 << 'PYEOF'
import json, os, glob, socket
from datetime import datetime, timedelta
from collections import defaultdict

projects_dir = os.path.expanduser("~/.claude/projects")
cutoff = (datetime.now() - timedelta(days=8)).strftime("%Y-%m-%d")
cutoff_ts = (datetime.now() - timedelta(days=8)).timestamp()

all_files = []
if os.path.isdir(projects_dir):
    for project_dir in glob.glob(os.path.join(projects_dir, "*/")):
        all_files.extend(glob.glob(os.path.join(project_dir, "*.jsonl")))
        all_files.extend(glob.glob(os.path.join(project_dir, "*/subagents/*.jsonl")))

recent_files = [f for f in all_files if os.path.getmtime(f) >= cutoff_ts]

daily = defaultdict(lambda: {
    "messages": 0, "sessions": 0, "tool_calls": 0,
    "tokens_by_model": defaultdict(int)
})

total_sessions = 0
total_messages = 0

for fpath in recent_files:
    is_subagent = "/subagents/" in fpath
    try:
        session_date = None
        msg_count = 0
        tool_count = 0
        tokens_by_model = defaultdict(int)

        with open(fpath) as f:
            for line in f:
                d = json.loads(line)
                t = d.get("type")

                if t in ("user", "assistant"):
                    if session_date is None:
                        ts = d.get("timestamp", "")
                        if isinstance(ts, str) and len(ts) >= 10:
                            session_date = ts[:10]
                    msg_count += 1

                if t == "assistant":
                    msg = d.get("message", {})
                    model = msg.get("model", "unknown")
                    usage = msg.get("usage", {})
                    tokens_by_model[model] += usage.get("output_tokens", 0)
                    content = msg.get("content", [])
                    for c in content:
                        if c.get("type") == "tool_use":
                            tool_count += 1

        if session_date and session_date >= cutoff:
            day = daily[session_date]
            if not is_subagent:
                day["sessions"] += 1
                total_sessions += 1
            day["messages"] += msg_count
            day["tool_calls"] += tool_count
            total_messages += msg_count
            for m, tok in tokens_by_model.items():
                day["tokens_by_model"][m] += tok
    except Exception:
        continue

daily_activity = []
daily_model_tokens = []
for date in sorted(daily.keys()):
    d = daily[date]
    daily_activity.append({
        "date": date,
        "messageCount": d["messages"],
        "sessionCount": d["sessions"],
        "toolCallCount": d["tool_calls"],
    })
    daily_model_tokens.append({
        "date": date,
        "tokensByModel": dict(d["tokens_by_model"]),
    })

payload = {
    "username": os.environ.get("USERNAME", "unknown"),
    "hostname": socket.gethostname(),
    "dailyActivity": daily_activity,
    "dailyModelTokens": daily_model_tokens,
    "totalSessions": total_sessions,
    "totalMessages": total_messages,
}
print(json.dumps(payload))
PYEOF
)

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -L \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$ENDPOINT_URL")

if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "302" ]]; then
    log "OK: sent (HTTP $HTTP_CODE)"
else
    log "ERROR: HTTP $HTTP_CODE"
fi
