#!/usr/bin/env bash
# SessionStart and SubagentStart hook: tells the agents when to reach for Grafana.
# Change only the BRIEF text: name the plugin, when to use it, and what it cannot do.
# Any change here needs a version bump in .claude-plugin/plugin.json.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
EVENT="$(jq -r '.hook_event_name // empty' 2>/dev/null)"
case "$EVENT" in SessionStart|SubagentStart) ;; *) exit 0 ;; esac

BRIEF='Grafana (plugin grafana@example-team) is connected read-only to https://grafana.example.com: mcp__plugin_grafana_grafana__*.
- Before investigating latency, error rates, pod restarts, failed deploys or alerts, check Grafana: search dashboards, then query Prometheus or Loki.
- Cite the dashboard or query you used. It cannot change dashboards, alerts or incidents.'

jq -n --arg e "$EVENT" --arg c "$BRIEF" \
  '{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}}'
exit 0
