#!/usr/bin/env bash
# Every pinned version must match versions.env. Run after bumping a pin:
#
#   bash claude/tests/versions.sh
#
# Exit status is the number of mismatches.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../versions.env
. "$ROOT/versions.env"

FAIL=0
check() {
  local what="$1" want="$2" got="$3"
  if [[ "$want" == "$got" ]]; then
    printf 'ok    %s %s\n' "$what" "$got"
  else
    printf 'FAIL  %s: versions.env says %s, found %s\n' "$what" "$want" "${got:-nothing}"
    FAIL=$((FAIL + 1))
  fi
}

check "context7 (plugins/morph/.claude-plugin/plugin.json)" "$CONTEXT7_MCP_VERSION" \
  "$(jq -r '.mcpServers.context7.args[] | select(startswith("@upstash/context7-mcp@")) | ltrimstr("@upstash/context7-mcp@")' \
     "$ROOT/plugins/morph/.claude-plugin/plugin.json")"

check "aws-documentation (plugins/devops/.claude-plugin/plugin.json)" "$AWS_DOCUMENTATION_MCP_VERSION" \
  "$(jq -r '.mcpServers["aws-documentation"].args[] | select(startswith("awslabs.aws-documentation-mcp-server@")) | ltrimstr("awslabs.aws-documentation-mcp-server@")' \
     "$ROOT/plugins/devops/.claude-plugin/plugin.json")"

check "caveman ref (claude/settings.json)" "$CAVEMAN_REF" \
  "$(jq -r '.extraKnownMarketplaces.caveman.source.ref // empty' "$ROOT/claude/settings.json")"

exit "$FAIL"
