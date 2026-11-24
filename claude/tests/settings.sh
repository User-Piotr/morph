#!/usr/bin/env bash
# Tests for the settings.json generator (claude/settings-lib.sh): merge rules,
# folding edits into the overlay, migration from the old symlink, idempotence.
# Everything runs in a temporary directory; ~/.claude is never touched.
#
#   bash claude/tests/settings.sh
#
# Exit status is the number of failing checks.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/../settings-lib.sh"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset CLAUDE_CONFIG_DIR

FAIL=0
PASS=0
ok()   { PASS=$((PASS + 1)); printf 'ok    %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n' "$1"; }
# eq NAME WANT GOT: JSON equality, key order ignored
eq() {
  if [ "$(jq -cS . <<<"$2")" = "$(jq -cS . <<<"$3")" ]; then ok "$1"; else fail "$1: want $2, got $3"; fi
}
check() { if "${@:2}"; then ok "$1"; else fail "$1"; fi; }

log() { :; }
CONF_DIR="" CLAUDE_HOME="" BACKUP_DIR=""
# shellcheck source=../settings-lib.sh
. "$LIB"

# A fresh fixture: a git repository whose claude/settings.json is the template,
# and an empty config directory.
fixture() {
  rm -rf "${T:?}/repo" "${T:?}/home"
  mkdir -p "$T/repo/claude" "$T/home"
  CONF_DIR="$T/repo/claude"; CLAUDE_HOME="$T/home"; BACKUP_DIR="$T/home/.config-backup/t"
  cat > "$CONF_DIR/settings.json" <<'JSON'
{"model":"opus","env":{"A":"1"},"permissions":{"allow":["x","y"]},"enabledPlugins":{"morph@morph":true}}
JSON
  git -C "$T/repo" init -q
  git -C "$T/repo" add -A
  git -C "$T/repo" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m init
}
J() { printf '%s' "$1" > "$T/$2"; }
# edit FILE JQ-FILTER: rewrite a JSON file in place
edit() { jq "${@:2}" "$1" > "$T/edit.tmp" && cp "$T/edit.tmp" "$1"; }
state() { cat "$CLAUDE_HOME/settings.json" "$CLAUDE_HOME/settings.personal.json" "$CLAUDE_HOME/.settings.generated.json" 2>/dev/null | cksum; }

# --- merge rules ---------------------------------------------------------
J '{"a":{"b":1,"c":[1,2]},"s":"t","arr":["x","y"]}' a.json
J '{"a":{"b":2,"d":3,"c":[2,3]},"s":"o","arr":["y","z"],"n":1}' b.json
eq "merge: deep objects, overlay scalar wins, arrays are a union" \
  '{"a":{"b":2,"c":[1,2,3],"d":3},"s":"o","arr":["x","y","z"],"n":1}' "$(settings_merge "$T/a.json" "$T/b.json")"
check "merge: array order is template first" \
  test "$(settings_merge "$T/a.json" "$T/b.json" | jq -c .arr)" = '["x","y","z"]'
J '{"arr":[{"k":1}]}' c.json; J '{"arr":[{"k":1},{"k":2}]}' d.json
eq "merge: object elements are deduplicated" '{"arr":[{"k":1},{"k":2}]}' "$(settings_merge "$T/c.json" "$T/d.json")"

# --- drift fold ----------------------------------------------------------
fixture
settings_sync
check "first run: settings.json is a regular file" test -f "$CLAUDE_HOME/settings.json" -a ! -L "$CLAUDE_HOME/settings.json"
eq "first run: output equals the template" "$(cat "$CONF_DIR/settings.json")" "$(cat "$CLAUDE_HOME/settings.json")"
check "first run: no overlay when nothing is personal" test ! -e "$CLAUDE_HOME/settings.personal.json"
edit "$CLAUDE_HOME/settings.json" '.extraKnownMarketplaces.team={"source":"x"} | .enabledPlugins["grafana@team"]=true | .enabledPlugins["morph@morph"]=false | .permissions.allow+=["z"]'
settings_sync
eq "drift: edits land in the overlay" \
  '{"extraKnownMarketplaces":{"team":{"source":"x"}},"enabledPlugins":{"grafana@team":true,"morph@morph":false},"permissions":{"allow":["z"]}}' \
  "$(cat "$CLAUDE_HOME/settings.personal.json")"
eq "drift: output keeps the edits" 'false' "$(jq -c '.enabledPlugins["morph@morph"]' "$CLAUDE_HOME/settings.json")"
check "drift: template untouched" git -C "$T/repo" diff --quiet
edit "$CONF_DIR/settings.json" '.env.B="2"'
settings_sync
eq "template change reaches the output" '{"A":"1","B":"2"}' "$(jq -c .env "$CLAUDE_HOME/settings.json")"
eq "template change leaves overlay entries in place" 'true' "$(jq -c '.enabledPlugins["grafana@team"]' "$CLAUDE_HOME/settings.json")"
edit "$CLAUDE_HOME/settings.json" 'del(.enabledPlugins["grafana@team"])'
settings_sync
eq "a key removed from the output stays in the overlay" 'true' "$(jq -c '.enabledPlugins["grafana@team"]' "$CLAUDE_HOME/settings.personal.json")"

# --- idempotence ---------------------------------------------------------
settings_sync; before="$(state)"; ls -R "$CLAUDE_HOME" > "$T/ls1"
settings_sync
check "idempotence: a second run changes nothing" test "$before" = "$(state)"
ls -R "$CLAUDE_HOME" > "$T/ls2"
check "idempotence: and creates no backups" diff -q "$T/ls1" "$T/ls2"

# --- generate alone ignores edits to the output (plugin command noise) ----
fixture; settings_sync
edit "$CLAUDE_HOME/settings.json" '.model="opus[1m]"'
settings_generate
eq "settings_generate drops plugin-command noise" '"opus"' "$(jq -c .model "$CLAUDE_HOME/settings.json")"
check "settings_generate does not write the overlay" test ! -e "$CLAUDE_HOME/settings.personal.json"

# --- migration -----------------------------------------------------------
fixture
# Link through a symlinked parent, so the link text differs from $CONF_DIR
# while naming the same file (as on macOS /private/var vs /var).
ln -s "$(dirname "$CONF_DIR")" "$CLAUDE_HOME.alias"
ln -s "$CLAUDE_HOME.alias/$(basename "$CONF_DIR")/settings.json" "$CLAUDE_HOME/settings.json"
edit "$CONF_DIR/settings.json" '.extraKnownMarketplaces.team={"source":"x"} | .enabledPlugins["grafana@team"]=true'
printf '{"theme":"dark"}' > "$CLAUDE_HOME/settings.personal.json"
settings_sync
check "migration: output is a regular file" test -f "$CLAUDE_HOME/settings.json" -a ! -L "$CLAUDE_HOME/settings.json"
check "migration: template restored" git -C "$T/repo" diff HEAD --quiet
eq "migration: keys moved to the overlay, existing overlay kept" \
  '{"theme":"dark","extraKnownMarketplaces":{"team":{"source":"x"}},"enabledPlugins":{"grafana@team":true}}' \
  "$(cat "$CLAUDE_HOME/settings.personal.json")"
eq "migration: output has template and overlay" 'true' "$(jq -c '.enabledPlugins["grafana@team"] and .enabledPlugins["morph@morph"]' "$CLAUDE_HOME/settings.json")"
check "migration: the dirty repository file was backed up" test -f "$BACKUP_DIR/settings.json.repository"
before="$(state)"; settings_sync
check "migration: a second run changes nothing" test "$before" = "$(state)"

# a symlink into a clean repository is just replaced
fixture
ln -s "$CONF_DIR/settings.json" "$CLAUDE_HOME/settings.json"
settings_sync
check "clean symlink: replaced by a regular file" test -f "$CLAUDE_HOME/settings.json" -a ! -L "$CLAUDE_HOME/settings.json"
check "clean symlink: no overlay" test ! -e "$CLAUDE_HOME/settings.personal.json"

# an invalid file stops the run before anything is changed
fixture; settings_sync
echo '{' > "$CLAUDE_HOME/settings.json"
if settings_sync; then fail "invalid JSON: refused"; else ok "invalid JSON: refused"; fi
check "invalid JSON: file left as it was" test "$(cat "$CLAUDE_HOME/settings.json")" = '{'

echo "passed $PASS, failed $FAIL"
exit "$FAIL"
