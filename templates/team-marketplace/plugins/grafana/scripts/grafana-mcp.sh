#!/usr/bin/env bash
# Launcher for the Grafana MCP server (stdio), started by grafana@example-team.
# Read-only: --disable-write removes every write tool and the raw-SQL tools;
# --disable-api removes grafana_api_request, which bypasses per-tool limits.
# The token comes only from the plugin's userConfig (Claude Code secure storage).
# Diagnostics go to stderr only: stdout carries the MCP JSON-RPC stream.
# Any change here needs a version bump in .claude-plugin/plugin.json.
set -euo pipefail

GRAFANA_BASE_URL="https://grafana.example.com"
MCP_GRAFANA_VERSION="2.2.0"            # pypi.org/project/mcp-grafana
PLUGIN_ID="grafana@example-team"

UVX="$(command -v uvx || true)"
[[ -z "$UVX" && -x /opt/homebrew/bin/uvx ]] && UVX=/opt/homebrew/bin/uvx
if [[ -z "$UVX" ]]; then
  echo "$PLUGIN_ID: uvx not found. Install uv: https://docs.astral.sh/uv/" >&2
  exit 1
fi

token="${GRAFANA_SERVICE_ACCOUNT_TOKEN:-}"
# An unset option may arrive empty or as the literal placeholder; treat both as missing.
# shellcheck disable=SC2016  # the placeholder is matched literally
if [[ -z "$token" || "$token" == '${user_config.'* ]]; then
  echo "$PLUGIN_ID: no token configured. In a session: /plugin -> $PLUGIN_ID -> configure." >&2
  echo "  Or: read -rs t && jq -nc --arg t \"\$t\" '{grafana_token:\$t}' | claude plugin configure $PLUGIN_ID --values-stdin; unset t" >&2
  exit 1
fi

export GRAFANA_URL="$GRAFANA_BASE_URL"
export GRAFANA_USAGE_STATS="disabled"   # no traffic beyond the Grafana instance

exec "$UVX" "mcp-grafana@$MCP_GRAFANA_VERSION" --disable-write --disable-api "$@"
