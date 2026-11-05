#!/usr/bin/env bash
# ~/.claude/scripts/block-mcp-mutations.sh
#
# PreToolUse hook for MCP tools, matched with the regex "mcp__.*".
# block-mutations.sh guards Bash and never sees these calls. tests/guards.sh
# holds the cases this is checked against — run it after any change here.
#
# There is no command string to parse here. Every MCP server has its own input
# schema, so the decision keys on the tool NAME. That is sturdier than the Bash
# side rather than weaker: a name cannot hide behind `bash -c` or a pipe.
#
# Verdicts mirror block-mutations.sh: "ask" for the interactive session, "deny"
# for a subagent, since only the main session publishes. Who is asking
# is decided the same way there, and the reasoning lives in that script.
#
# Order of the checks, and why:
#   1. A shell-shaped tool (execute_shell_command, run_terminal, ...) is judged
#      even on an allowlisted server: a server trusted for reads is not trusted
#      to hand out a shell that bypasses both guards and the sandbox.
#   2. An allowlisted server passes: the built-in list, a server the user names
#      in MORPH_READ_ONLY_SERVERS, or a plugin server its plugin declares
#      read-only (see below). None of them overrides check 1.
#   3. A write marker anywhere in the tool name asks.
#   4. A read marker passes. Checked after writes, so get_and_delete is a write.
#   5. Anything else asks: an unclassified tool gets no free pass.
#
# Requires jq. Fails CLOSED (exit 2) if jq is missing or the input is not a
# JSON object.
set -uo pipefail

# Servers whose whole surface is read-only, or whose writes are working-tree
# edits the implementer is meant to make (serena). Matched on the server
# segment of the tool name. The match is exact, never a prefix: another plugin's
# server must not be able to borrow a trusted name (a plugin server is named
# plugin_<plugin>_<server>, so only the morph plugin itself can produce
# plugin_morph_context7). devops declares its server in
# plugins/devops/.claude-plugin/read-only-servers.json instead (see below).
# The devops-core pair stays until every machine has migrated.
READ_ONLY_SERVERS=(
  "context7"
  "awslabs_aws-documentation-mcp-server"
  "plugin_morph_context7"
  "plugin_devops-core_context7"
  "plugin_devops-core_aws-documentation"
  "headroom"
  "serena"
)
# The user can extend the list with servers they trust, space-separated and exact
# (no globs, no prefixes), in MORPH_READ_ONLY_SERVERS: `env` of
# claude/settings.json or .claude/settings.local.json, managed settings, or their
# own shell. Same pattern as MORPH_INTERACTIVE_AGENTS below. It never overrides
# the shell-marker check, which runs first.
EXTRA_READ_ONLY_SERVERS=()
_extra_servers="${MORPH_READ_ONLY_SERVERS-}"
read -ra EXTRA_READ_ONLY_SERVERS <<<"${_extra_servers//$'\n'/ }" || true
for i in ${EXTRA_READ_ONLY_SERVERS[@]+"${EXTRA_READ_ONLY_SERVERS[@]}"}; do
  READ_ONLY_SERVERS+=("$i")
done

# Marketplaces whose plugins may declare their own servers read-only, in
# <installPath>/.claude-plugin/read-only-servers.json. Space-separated, exact
# names. Unset means "morph"; set but empty trusts none. Anyone who can publish
# to a trusted marketplace can mark a server read-only, so trust only reviewed ones.
TRUSTED_MARKETPLACES="${MORPH_TRUSTED_MARKETPLACES-morph}"
TRUSTED_MARKETPLACES="${TRUSTED_MARKETPLACES//$'\n'/ }"

# `execute` alone is left off: execute_query and execute_workflow are writes,
# not shells, and are caught by WRITE_MARKERS with an honest reason.
SHELL_MARKERS='(^|_)(shell|exec|command|commands|terminal|spawn|process|subprocess)(_|$)'
WRITE_MARKERS='(^|_)(write|create|update|delete|remove|merge|complete|queue|run|trigger|deploy|apply|sync|restart|scale|set|put|post|patch|invoke|abandon|publish|push|approve|vote|execute|exec|insert|drop|replace|install|uninstall|terminate|kill|stop|start|reboot|cancel|archive|rename|move|upload|send|assign|grant|revoke|reset|rollback|restore|enable|disable|attach|detach)(_|$)'
READ_MARKERS='(^|_)(list|get|show|search|read|describe|find|view|status|diff|query|fetch|history)(_|$)'

LOG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/logs/mcp-guard.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null

INPUT_JSON="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "block-mcp-mutations.sh: jq not found on PATH; failing closed." >&2
  exit 2
fi
# One jq call for validation and every field: this runs on every MCP call.
# @sh quotes each value as a single shell word, so the eval only ever assigns.
# A field that is neither a string nor absent fails closed like bad JSON.
if ! FIELDS="$(printf '%s' "$INPUT_JSON" | jq -r '
    def str: if . == null then "" elif type == "string" then . else error("not a string") end;
    if type != "object" then error("not an object") else
      @sh "TOOL_NAME=\(.tool_name | str)",
      @sh "AGENT_TYPE=\(.agent_type | str)",
      @sh "AGENT_ID=\(.agent_id | str)"
    end' 2>/dev/null)" || [[ -z "$FIELDS" ]]; then
  echo "block-mcp-mutations.sh: cannot read the hook input; failing closed." >&2
  exit 2
fi
eval "$FIELDS"

[[ "$TOOL_NAME" == mcp__* ]] || exit 0

# mcp__<server>__<tool>; the tool segment may itself contain underscores.
REST="${TOOL_NAME#mcp__}"
SERVER="${REST%%__*}"
TOOL="$(printf '%s' "${REST#*__}" | tr '[:upper:]-' '[:lower:]_')"

# Same rule as block-mutations.sh: an agent_id means subagent, and so does an
# agent_type outside the interactive list. Real MCP calls from the main session
# carry agent_type=devops (mcp-guard.log, 2026-09-23..25), so the list is needed,
# and agent_id alone misses a headless top-level `claude -p --agent X`.
# "morph:morph" is the plugin's name for the main agent; "devops"
# and "devops-core:devops" stay until every machine has migrated to morph.
# The list can grow: a main session started as another agent (the `agent` key
# overridden per repository) would otherwise be read as headless and denied
# every live write. The user opts in by naming such agents, space-separated and
# exact (no globs, no prefixes), in MORPH_INTERACTIVE_AGENTS, set in `env` of
# claude/settings.json or .claude/settings.local.json, or in their own shell.
# The agent_id check stays first, so no list entry can unblock a subagent.
INTERACTIVE_AGENTS=("devops" "devops-core:devops" "morph:morph")
# read -a splits on whitespace without globbing; empty words vanish.
EXTRA_INTERACTIVE_AGENTS=()
_extra="${MORPH_INTERACTIVE_AGENTS-}"
read -ra EXTRA_INTERACTIVE_AGENTS <<<"${_extra//$'\n'/ }" || true
for i in ${EXTRA_INTERACTIVE_AGENTS[@]+"${EXTRA_INTERACTIVE_AGENTS[@]}"}; do
  INTERACTIVE_AGENTS+=("$i")
done
IS_HEADLESS=false
if [[ -n "$AGENT_ID" ]]; then
  IS_HEADLESS=true
elif [[ -n "$AGENT_TYPE" ]]; then
  IS_HEADLESS=true
  for i in "${INTERACTIVE_AGENTS[@]}"; do
    [[ "$AGENT_TYPE" == "$i" ]] && IS_HEADLESS=false
  done
fi

# Best effort and silent: a PreToolUse hook's stderr reaches the session.
log() {
  { printf '%s\t%s\tagent_type=%s\tagent_id=%s\t%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TOOL_NAME" "${AGENT_TYPE:-<none>}" \
      "$([[ -n "$AGENT_ID" ]] && echo yes || echo no)" "$1" >>"$LOG"; } 2>/dev/null || true
}

decide() {
  jq -n --arg d "$1" --arg reason "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $reason}}'
  exit 0
}

verdict() {
  if [[ "$IS_HEADLESS" == true ]]; then
    log "deny"
    decide deny "$1 [blocked: only the main session publishes or changes live systems; hand this step back]"
  fi
  log "ask"
  decide ask "$1"
}

if [[ "$TOOL" =~ $SHELL_MARKERS ]]; then
  verdict "MCP tool $TOOL_NAME hands out a shell, which bypasses the Bash guard and the sandbox."
fi

for s in "${READ_ONLY_SERVERS[@]}"; do
  if [[ "$SERVER" == "$s" ]]; then
    log "allow (read-only server)"
    exit 0
  fi
done

# Declared read-only by the plugin that provides the server. Only plugin servers
# (plugin_<plugin>_<server>) not already trusted get here. Every failure to read,
# parse or match falls through to the marker rules: more prompts, never fewer.
# Trust needs: installed_plugins.json version 2; exactly one <plugin> name that
# splits the segment; every installed copy of that plugin from a trusted
# marketplace; and every copy's declaration file listing <server> exactly.
if [[ "$SERVER" == plugin_* ]]; then
  INSTALLED="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json"
  if [[ -r "$INSTALLED" ]] && mapfile -t DECL < <(jq -r --arg seg "$SERVER" --arg tm "$TRUSTED_MARKETPLACES" '
      ($tm | split(" ") | map(select(length > 0))) as $trusted
      | if .version != 2 then empty else
          [ (.plugins // {}) | to_entries[]
            | (.key | capture("^(?<p>.+)@(?<m>[^@]+)$")?) as $k
            | {p: $k.p, m: $k.m, v: .value} ] as $all
          | [ $all[] | select(.p as $p | ($seg | startswith("plugin_" + $p + "_"))
                and (($seg | ltrimstr("plugin_" + $p + "_")) | length > 0)) | .p ] | unique as $names
          | if ($names | length) != 1 then empty else
              $names[0] as $p
              | ($all | map(select(.p == $p))) as $inst
              | if ($inst | all(.m as $m | $trusted | index($m) != null)) then
                  # Built whole before anything is printed: an error here must
                  # leave no partial output for mapfile, which cannot see jq fail.
                  [ $inst[] | .v | if type == "array" and length > 0 then .[] else error("no install") end
                    | .installPath | if type == "string" and length > 0 then . else error("no path") end
                  ] as $paths
                  | ($seg | ltrimstr("plugin_" + $p + "_")),
                    ($inst | map(.p + "@" + .m) | join(",")),
                    $paths[]
                else empty end
            end
        end' "$INSTALLED" 2>/dev/null) && [[ ${#DECL[@]} -ge 3 ]]; then
    DECL_SERVER="${DECL[0]}"
    DECL_FILES=()
    for i in "${DECL[@]:2}"; do DECL_FILES+=("$i/.claude-plugin/read-only-servers.json"); done
    if jq -en --arg s "$DECL_SERVER" '
        [inputs | (.servers | type == "array") and any(.servers[]; . == $s)]
        | length > 0 and all' "${DECL_FILES[@]}" >/dev/null 2>&1; then
      log "allow (declared read-only by ${DECL[1]})"
      exit 0
    fi
  fi
fi

if [[ "$TOOL" =~ $WRITE_MARKERS ]]; then
  verdict "MCP tool $TOOL_NAME looks like a write. Confirm it before it runs."
fi

if [[ "$TOOL" =~ $READ_MARKERS ]]; then
  log "allow (read-shaped name)"
  exit 0
fi

verdict "MCP server '$SERVER' is not on the read-only list, and $TOOL_NAME does not read like a query."
