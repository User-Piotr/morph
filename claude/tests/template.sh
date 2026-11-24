#!/usr/bin/env bash
# Checks the team plugin template in templates/team-marketplace: the brief hook
# answers only its two events, the launcher refuses to start without a token and
# keeps stdout clean, and hooks.json matches the devops plugin's.
#
#   bash claude/tests/template.sh
#
# Exit status is the number of failing checks.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
P="$ROOT/templates/team-marketplace/plugins/grafana"
FAIL=0
check() {
  if [[ "$2" == "$3" ]]; then printf 'ok    %s\n' "$1"
  else printf 'FAIL  %s: want %s, got %s\n' "$1" "$2" "$3"; FAIL=$((FAIL + 1)); fi
}

for ev in SessionStart SubagentStart; do
  got="$(jq -cn --arg e "$ev" '{hook_event_name:$e}' | bash "$P/scripts/brief.sh" \
    | jq -r --arg e "$ev" 'select(.hookSpecificOutput.hookEventName == $e) | .hookSpecificOutput.additionalContext | split("\n") | length')"
  check "brief on $ev" 3 "$got"
done
check "brief silent on PreToolUse" "" "$(echo '{"hook_event_name":"PreToolUse"}' | bash "$P/scripts/brief.sh")"

# Without a token the launcher must exit 1, print nothing on stdout, and say why
# on stderr. A stub uvx stands in, so the test never downloads the server.
STUB="$(mktemp -d)"; trap 'rm -rf "$STUB"' EXIT
printf '#!/bin/sh\necho started\n' > "$STUB/uvx"; chmod +x "$STUB/uvx"
# shellcheck disable=SC2016  # the placeholder is passed literally on purpose
for tok in "" '${user_config.grafana_token}'; do
  out="$(PATH="$STUB:$PATH" GRAFANA_SERVICE_ACCOUNT_TOKEN="$tok" bash "$P/scripts/grafana-mcp.sh" 2>"$STUB/err")"; rc=$?
  label="launcher with token '${tok:-empty}'"
  check "$label exit" 1 "$rc"
  check "$label stdout" "" "$out"
  check "$label message" yes "$(grep -q 'no token configured' "$STUB/err" && echo yes || echo no)"
done
out="$(PATH="$STUB:$PATH" GRAFANA_SERVICE_ACCOUNT_TOKEN=x bash "$P/scripts/grafana-mcp.sh" 2>/dev/null)"
check "launcher starts the server with a token" started "$out"

check "hooks.json matches devops" same \
  "$(diff <(jq -S . "$P/hooks/hooks.json") <(jq -S . "$ROOT/plugins/devops/hooks/hooks.json") >/dev/null && echo same || echo differs)"

exit "$FAIL"
