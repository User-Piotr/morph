#!/usr/bin/env bash
# Generates ~/.claude/settings.json from the tracked template plus a personal
# overlay that lives outside the repository. Sourced by install.sh and by
# claude/tests/settings.sh; not run directly. See ../docs/reference.md.
#
# The caller provides: CONF_DIR (this directory), CLAUDE_HOME, BACKUP_DIR, log().
#
#   template   $CONF_DIR/settings.json                    tracked, shared policy
#   overlay    $CLAUDE_HOME/settings.personal.json        this machine only
#   output     $CLAUDE_HOME/settings.json                 regular file Claude Code reads
#   last copy  $CLAUDE_HOME/.settings.generated.json      what was generated last time

# Merge rules. Objects merge deeply, arrays are the ordered union without
# duplicates (template first), a scalar from the overlay wins. Not `jq '*'`,
# which replaces arrays.
#   merge($b)  . merged with $b
#   delta($g)  what . adds to or changes in $g, or null when nothing
#   gone($g)   what $g has that . lacks, or null when nothing
#   lp         the changed keys as dotted paths, for the log (never values)
SETTINGS_JQ_DEFS='
def dedup: reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
def merge($b): . as $a
  | if ($a | type) == "object" and ($b | type) == "object" then
      reduce ($b | keys_unsorted[]) as $k ($a;
        .[$k] = (if has($k) then (.[$k] | merge($b[$k])) else $b[$k] end))
    elif ($a | type) == "array" and ($b | type) == "array" then ($a + $b) | dedup
    else $b end;
def delta($g): . as $c
  | if ($c | type) == "object" and ($g | type) == "object" then
      reduce ($c | keys_unsorted[]) as $k ({};
        if ($g | has($k) | not) then .[$k] = $c[$k]
        else ($c[$k] | delta($g[$k])) as $d | if $d == null then . else .[$k] = $d end end)
      | if . == {} then null else . end
    elif ($c | type) == "array" and ($g | type) == "array" then
      [$c[] | select(. as $x | ($g | any(.[]; . == $x)) | not)]
      | if length == 0 then null else . end
    elif $c == $g then null
    else $c end;
def gone($g): . as $c
  | if ($c | type) == "object" and ($g | type) == "object" then
      reduce ($g | keys_unsorted[]) as $k ({};
        if ($c | has($k) | not) then .[$k] = $g[$k]
        else ($c[$k] | gone($g[$k])) as $d | if $d == null then . else .[$k] = $d end end)
      | if . == {} then null else . end
    elif ($c | type) == "array" and ($g | type) == "array" then
      [$g[] | select(. as $x | ($c | any(.[]; . == $x)) | not)]
      | if length == 0 then null else . end
    else null end;
def lp($p): if type == "object" and length > 0
    then (to_entries[] | .key as $k | .value | lp($p + [$k]))
    else ($p | join(".")) + (if type == "array" then " (\(length) entries)" else "" end) end;
'

# Each takes two files. merge: A then B. delta: A against B. gone: A against B.
settings_merge() { jq -s "$SETTINGS_JQ_DEFS . as [\$x, \$y] | \$x | merge(\$y)" "$1" "$2"; }
settings_delta() { jq -s "$SETTINGS_JQ_DEFS . as [\$x, \$y] | \$x | delta(\$y)" "$1" "$2"; }
settings_gone()  { jq -s "$SETTINGS_JQ_DEFS . as [\$x, \$y] | \$x | gone(\$y)" "$1" "$2"; }
settings_keys()  { jq -r "$SETTINGS_JQ_DEFS lp([])" "$1"; }

# Keep a copy of a file before it is replaced, under the install's backup directory.
settings_backup() {
  mkdir -p "$BACKUP_DIR"
  cp -L "$1" "$BACKUP_DIR/$2"
  log "backed up $2 to $BACKUP_DIR"
}

# Install a file atomically; mv replaces a symlink at the destination itself.
settings_put() {
  cp "$1" "$2.new"
  chmod 644 "$2.new"
  mv -f "$2.new" "$2"
}

# Fold a delta file into the overlay working copy and name the keys.
settings_fold() {
  local delta="$1" overlay="$2" why="$3" merged
  merged="$(mktemp "$overlay.XXXXXX")"
  settings_merge "$overlay" "$delta" > "$merged"
  mv -f "$merged" "$overlay"
  log "$why:"
  settings_keys "$delta" | while IFS= read -r k; do log "    $k"; done
}

# Regenerate the output from template and overlay without looking at what the
# output holds now. Used on its own after install.sh's plugin commands, which
# rewrite the output (keys reordered, "opus" turned into "opus[1m]"): those
# edits are noise, not choices, and must not reach the overlay.
settings_generate() {
  local out="$CLAUDE_HOME/settings.json" over="$CLAUDE_HOME/settings.personal.json"
  local gen="$CLAUDE_HOME/.settings.generated.json" tpl="$CONF_DIR/settings.json"
  local work empty
  work="$(mktemp -d "$CLAUDE_HOME/.settings-work.XXXXXX")"
  empty="$work/empty.json"; echo '{}' > "$empty"
  settings_merge "$tpl" "$( [ -f "$over" ] && echo "$over" || echo "$empty" )" > "$work/new.json"
  if [ ! -f "$out" ] || [ -L "$out" ] || ! cmp -s <(jq -S . "$out") <(jq -S . "$work/new.json"); then
    [ -e "$out" ] && settings_backup "$out" settings.json
    settings_put "$work/new.json" "$out"
  fi
  cmp -s "$work/new.json" "$gen" 2>/dev/null || settings_put "$work/new.json" "$gen"
  rm -rf "$work"
}

# The full step: migrate a symlink into the repository, fold edits made since
# the last run into the overlay, then generate.
settings_sync() {
  local out="$CLAUDE_HOME/settings.json" over="$CLAUDE_HOME/settings.personal.json"
  local gen="$CLAUDE_HOME/.settings.generated.json" tpl="$CONF_DIR/settings.json"
  local work overlay base f
  command -v jq >/dev/null 2>&1 || { log "jq is required to generate settings.json"; return 1; }
  mkdir -p "$CLAUDE_HOME"
  work="$(mktemp -d "$CLAUDE_HOME/.settings-work.XXXXXX")"
  overlay="$work/overlay.json"
  if [ -f "$over" ]; then cp "$over" "$overlay"; else echo '{}' > "$overlay"; fi

  # Refuse to guess when a file is not JSON: nothing has been changed yet.
  for f in "$tpl" "$over" "$out" "$gen"; do
    [ -f "$f" ] || continue
    jq -e . "$f" >/dev/null 2>&1 || { rm -rf "$work"; log "not valid JSON, fix or remove it and rerun: $f"; return 1; }
  done

  # Migration, once: ~/.claude/settings.json used to be a symlink to the
  # template, so everything `claude plugin …` and /config wrote landed in the
  # repository. Move those edits to the overlay and restore the template.
  # -ef, not a string compare: the old link may name the template through
  # another spelling of the same path (a symlinked parent, macOS /private).
  if [ -L "$out" ] && [ "$out" -ef "$tpl" ]; then
    log "settings.json is a symlink into this repository; replacing it with a generated file"
    if git -C "$CONF_DIR" rev-parse --git-dir >/dev/null 2>&1 \
       && ! git -C "$CONF_DIR" diff HEAD --quiet -- settings.json; then
      git -C "$CONF_DIR" show HEAD:./settings.json > "$work/head.json"
      settings_delta "$tpl" "$work/head.json" > "$work/moved.json"
      settings_gone  "$tpl" "$work/head.json" > "$work/lost.json"
      settings_backup "$tpl" settings.json.repository
      [ -f "$over" ] && settings_backup "$over" settings.personal.json
      if [ "$(cat "$work/moved.json")" != "null" ]; then
        settings_fold "$work/moved.json" "$overlay" "moved from claude/settings.json to settings.personal.json"
        settings_put "$overlay" "$over"
      fi
      if [ "$(cat "$work/lost.json")" != "null" ]; then
        log "removed from the template, not carried over (the overlay cannot remove a template key):"
        settings_keys "$work/lost.json" | while IFS= read -r k; do log "    $k"; done
      fi
      git -C "$CONF_DIR" checkout HEAD -- settings.json
      log "claude/settings.json restored to HEAD"
    fi
    rm -f "$out"
  fi

  # Drift: what Claude Code (`claude plugin …`, /plugin, /config) changed in the
  # output since it was generated belongs to this machine, so it goes to the
  # overlay. Without a previous copy the template is the baseline.
  if [ -f "$out" ]; then
    if [ -f "$gen" ]; then base="$gen"; else base="$tpl"; log "no previous generated copy; comparing settings.json with the template"; fi
    settings_delta "$out" "$base" > "$work/drift.json"
    if [ "$(cat "$work/drift.json")" != "null" ]; then
      [ -f "$over" ] && settings_backup "$over" settings.personal.json
      settings_fold "$work/drift.json" "$overlay" "changed in settings.json since the last install, kept in settings.personal.json"
      settings_put "$overlay" "$over"
    fi
    settings_gone "$out" "$base" > "$work/gone.json"
    if [ "$(cat "$work/gone.json")" != "null" ]; then
      log "removed from settings.json since the last install, not removed from the overlay (a template key cannot be removed from it):"
      settings_keys "$work/gone.json" | while IFS= read -r k; do log "    $k"; done
    fi
  fi
  rm -rf "$work"

  settings_generate
  log "settings.json (template + settings.personal.json)"
}
