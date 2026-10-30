# Plugin-declared read-only MCP servers — 2026-10-30

## Summary

Let a domain plugin from a trusted marketplace declare which of its own MCP servers are read-only, so the MCP guard trusts them without a pull request to this repository. Also document how a team repository points at the `morph` marketplace from its own `.claude/settings.json`.

## Context

- `claude/scripts/block-mcp-mutations.sh` trusts a server wholesale only when its name segment is on the hardcoded `READ_ONLY_SERVERS` array (lines 35–44). Any other server is judged by tool-name markers: shell markers ask or deny, write markers ask or deny, read markers pass, anything else asks or denies.
- A plugin server's segment is `plugin_<plugin>_<server>`. Today only `morph` and `devops` produce trusted names.
- Installed plugins and their paths are in `~/.claude/plugins/installed_plugins.json` (`version: 2`, `plugins["<name>@<marketplace>"] = [{scope, installPath, version}]`). Enabled state is `enabledPlugins` in the merged settings. Both are Claude Code internals, not a documented contract.
- Tests: `claude/tests/guards.sh`.

## Steps

1. **Declaration format.** A plugin may ship `.claude-plugin/read-only-servers.json` with `{"servers": ["<server>", ...]}`. Each entry is a server the plugin defines itself, in its own `mcpServers`. Document the file in `docs/reference.md` under "Your own plugin", next to the `plugin.json` example, using `grafana` as the example.
2. **Trusted marketplaces.** In `claude/scripts/block-mcp-mutations.sh`, read `MORPH_TRUSTED_MARKETPLACES` (space-separated, default `morph`). Set it through `env` in `claude/settings.json` or, later, managed settings. Both are files the sandbox already keeps agents from writing. Do not add a separate trust file that an agent could reach with Edit.
3. **Guard lookup.** Run it only when the server segment starts with `plugin_` and is not already on `READ_ONLY_SERVERS`. With one `jq` call over `installed_plugins.json`:
   - find the entries whose `plugin_<name>_` is a prefix of the segment, where the rest is `<server>`;
   - require every installed plugin with that `<name>` to come from a marketplace in `MORPH_TRUSTED_MARKETPLACES`. This closes the case of a same-named plugin from another marketplace;
   - read `<installPath>/.claude-plugin/read-only-servers.json` and pass only on an exact `<server>` match.

   Keep the shell-marker check first, as it is today. On any read or parse failure, fall through to the existing marker rules rather than failing open. Log the trust decision as `allow (declared read-only by <name>@<marketplace>)`.
4. **devops as the reference.** Add `plugins/devops/.claude-plugin/read-only-servers.json` declaring `aws-documentation`. Keep `plugin_devops_aws-documentation` in `READ_ONLY_SERVERS` until the declaration path has shipped to every machine, then remove it in a follow-up.
5. **Tests.** Extend `claude/tests/guards.sh` with a fixture `installed_plugins.json` and plugin directories under a temporary `CLAUDE_CONFIG_DIR`. Cover:
   - (a) a declared server from a trusted marketplace passes;
   - (b) the same declaration from an untrusted marketplace falls through to the markers;
   - (c) a same-named plugin installed from both a trusted and an untrusted marketplace is not trusted;
   - (d) an undeclared server of a trusted plugin falls through;
   - (e) a shell-shaped tool on a declared server still asks for the main session and denies for a subagent;
   - (f) a missing or corrupt `installed_plugins.json` falls through;
   - (g) a server name that only shares a prefix with a declared one is not trusted;
   - (h) a main session started as an overridden agent named in `MORPH_INTERACTIVE_AGENTS` is asked, not denied.

   The guard must read `installed_plugins.json` from `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/` so the fixture works.
6. **Interactive agent detection.** `INTERACTIVE_AGENTS` is hardcoded in both `claude/scripts/block-mcp-mutations.sh` and `claude/scripts/block-mutations.sh`, yet `docs/reference.md` tells users to override `agent` per repository. A main session started as any other agent is then treated as a subagent and denied every write. Append the space-separated `MORPH_INTERACTIVE_AGENTS` from `env` to the built-in list in both guards. Additions only: the built-in names stay. Document it next to the `agent` override in `docs/reference.md`.
7. **Team repository pointing at morph.** In `docs/reference.md`, add a short subsection under "Your own plugin": a team repository's `.claude/settings.json` with `extraKnownMarketplaces` (`morph` from `User-Piotr/morph`, plus the team marketplace) and `enabledPlugins` (`morph@morph`, `team@team-plugins`), so cloning that repository offers the plugins. Also add one paragraph on the lighter path: a project `.mcp.json` plus `.claude/skills/`. Such servers are never trusted wholesale and stay on the tool-name markers.

## Risks & Mitigations

- **Self-trust.** A plugin could declare a write-capable server read-only. Mitigation: only marketplaces listed in `MORPH_TRUSTED_MARKETPLACES` count, trusting a marketplace is a reviewed settings change, and shell-shaped tools are judged before any trust.
- **Name collision.** `plugin_<a>_<b_c>` and `plugin_<a_b>_<c>` produce the same segment, and two marketplaces can ship a plugin with the same name. Mitigation: step 3 requires every installed plugin of that name to be trusted, and test (g) covers prefix collisions. Add an ambiguity case to the tests if two trusted plugins could produce the same segment.
- **Undocumented internals.** The shape of `installed_plugins.json` may change between Claude Code versions. Mitigation: check `.version == 2`. On anything unexpected, fall through to the markers, which is fail-safe: a trusted plugin's tools may prompt more, never less.
- **Hot path.** The guard runs on every MCP call. Mitigation: the extra `jq` call runs only for `plugin_*` servers not already on the list. Keep it to one `jq` invocation.
- **Blast radius.** Every machine with this policy runs the guard, and both the main session and subagents depend on it. A bug that fails open would remove MCP write protection everywhere. Mitigation: tests (b)–(g) and the independent review.

## References

- `claude/scripts/block-mcp-mutations.sh`
- `claude/scripts/block-mutations.sh` (who-is-asking logic)
- `claude/tests/guards.sh`
- `docs/reference.md` sections "MCP servers" and "Your own plugin"
- `plugins/devops/.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`
- Claude Code docs for `extraKnownMarketplaces`, `enabledPlugins` and the plugin manifest, to be checked via context7 before step 6

## Validation Plan

```bash
bash claude/tests/guards.sh
shellcheck claude/scripts/block-mcp-mutations.sh
claude plugin validate plugins/devops
jq . plugins/devops/.claude-plugin/read-only-servers.json
```

In a new session, call one `mcp__plugin_devops_aws-documentation__*` tool and one `mcp__plugin_morph_context7__*` tool, then check that `~/.claude/logs/mcp-guard.log` shows `allow`.
