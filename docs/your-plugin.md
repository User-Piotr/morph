# Your own plugin

How a team adds its own MCP server, brief and knowledge next to morph, in a
private marketplace, without changing this repository. The worked example is a
read-only Grafana MCP server; the copyable files are in
[`templates/team-marketplace/`](../templates/team-marketplace/) and validated in
CI. Everything marked here as a gotcha was hit while building the first team
plugin this way.

## How a plugin meets morph

The plugin needs **no dependency on morph** and no morph-specific file. It works
in any Claude Code session; with morph installed it meets it in three places:

- **Tools.** Every enabled plugin's MCP server joins the session as
  `mcp__plugin_<plugin>_<server>__<tool>`. `morph:investigator` and
  `morph:implementer` list what they may not use (`disallowedTools`) rather than
  what they may, so they inherit the new tools automatically.
- **Guard.** `block-mcp-mutations.sh` judges every MCP call by tool name:
  read-shaped names (`list`, `get`, `show`, `search`, `read`, `describe`, `find`,
  `view`, `status`, `diff`, `query`, `fetch`, `history`) pass; write-shaped names
  ask; anything else asks in the main session and is denied to subagents. See
  [Trusting the server](#trusting-the-server) for servers whose read tools are
  named otherwise.
- **Brief.** Tool names say a tool exists, not when to use it. The plugin's own
  `hooks/hooks.json` runs `scripts/brief.sh` at `SessionStart` and
  `SubagentStart`; it returns a three-line brief as
  `hookSpecificOutput.additionalContext`, so the main session and every subagent
  reach for the tool on the right symptoms. Same mechanism as
  `plugins/devops/scripts/brief.sh`; it costs three lines of context per session
  and per subagent, and appears only in sessions started after install.

Dropping `"dependencies": ["morph@morph"]` was deliberate: it forced morph on
everyone who only wanted the server, and pointed across marketplaces.

## Layout

```
.claude-plugin/marketplace.json              marketplace name, owner, plugin list
README.md                                    install, update, change rules
plugins/grafana/.claude-plugin/plugin.json   version, userConfig (token), MCP server
plugins/grafana/hooks/hooks.json             SessionStart + SubagentStart -> brief.sh
plugins/grafana/scripts/brief.sh             three-line brief for agents
plugins/grafana/scripts/grafana-mcp.sh       launcher: pin, read-only flags, token check
```

`hooks.json` is identical to `plugins/devops/hooks/hooks.json`. Copy it rather
than retyping it; a JSON block lost or doubled in transfer is easy to miss.

## Steps

1. **Create an empty repository** on your git host. A repository created with a
   default README already has a commit on `main`, and the first push then needs a
   rebase onto it.
2. **Copy the template** and rename it as its README says (marketplace name,
   team, host).
3. **Validate:**
   ```bash
   claude plugin validate .
   claude plugin validate plugins/grafana
   echo '{"hook_event_name":"SubagentStart"}' | bash plugins/grafana/scripts/brief.sh
   ```
4. **Remove any hand-installed copy of the same server first** (`claude mcp
   remove <name> --scope user`), so a test cannot reach the old one. Keep the old
   token until the new plugin works if it is your only copy.
5. **Test locally** before pushing:
   ```bash
   claude plugin marketplace add <path to the clone>
   claude plugin install grafana@<marketplace>
   read -rs t && jq -nc --arg t "$t" '{grafana_token:$t}' \
     | claude plugin configure grafana@<marketplace> --values-stdin; unset t
   ```
   In a new session `/mcp` shows `plugin:grafana:grafana` connected; a dashboard
   search and one query work; `grep grafana ~/.claude/logs/mcp-guard.log` shows
   `mcp__plugin_grafana_grafana__*`.
6. **Publish** and switch each machine to the remote:
   ```bash
   claude plugin marketplace remove <marketplace>
   claude plugin marketplace add <repository URL>
   claude plugin install grafana@<marketplace>
   ```

## Private repositories

- `claude plugin marketplace add` takes `owner/repo` (GitHub), an HTTPS URL, or
  a local path. An Azure DevOps `…/_git/…` URL works. An SSH `git@…` address is
  rejected (`Invalid marketplace source format`).
- Claude Code turns git prompts and askpass off when it clones, so git must
  authenticate without asking. Check with
  `git -c core.askPass= ls-remote <url>`. For Azure DevOps over HTTPS, Git
  Credential Manager does it after one browser login.
- On macOS the first use raises several Keychain prompts; answer **Always
  Allow**. Background marketplace updates cannot answer a prompt: they fail
  quietly and keep the last synced copy.

## Tokens

- Ask for the token through `userConfig` with `"sensitive": true`. Claude Code
  keeps it in its secure storage and passes it to the server through `env`
  (`${user_config.<key>}`); it is never in the repository, a settings file or a
  process argument.
- `userConfig.<key>.description` is **required**; `claude plugin validate` fails
  without it.
- `claude plugin configure <plugin>` without flags only **shows** the options.
  Save with `--values-stdin` (a JSON object) or `/plugin` in a session. `claude
  plugin install --config KEY=VALUE` also works but puts a secret in shell
  history.
- Before a token is set, `/mcp` shows the server as `✘ failed` with no error
  text. Whether the unset option arrives empty or as the literal
  `${user_config.…}` was not established; the launcher treats both as missing
  and says how to configure it.
- Use the least-privileged role the server needs (Grafana: **Viewer**).

## Read-only by construction

Prefer the server's own read-only switches over trust in morph. For
`mcp-grafana`:

- `--disable-write` removes every create, update and delete tool and the raw-SQL
  tools (`query_sql`, `query_influxdb`), which would pass any statement the
  datasource credentials allow.
- `--disable-api` removes `grafana_api_request`, a raw HTTP tool that bypasses
  per-tool limits.
- `GRAFANA_USAGE_STATS=disabled` stops usage statistics to Grafana Labs.

The launcher pins the server version (`mcp-grafana@2.2.0` through `uvx`) and
keeps stdout for the MCP JSON-RPC stream; every diagnostic goes to stderr.

Write protection then has three independent layers: the flags, the Viewer role,
and the morph guard.

## Trusting the server

With both flags, `mcp-grafana` 2.2.0 exposes 62 tools. 54 have read-shaped names
and pass the guard. The other 8 ask in the main session and are denied to
subagents: `alerting_manage_routing`, `analyze_loki_labels`,
`check_datasources_health`, `generate_deeplink`, `render_grafana_app`,
`suggest_loki_alloy_label_config`, `user_info`, `validate_provisioning_file`.

To let them through, trust the server in morph. Trust passes every tool of the
server, write-shaped names included, so protection then rests on the flags and
the role. Two ways, both set by the user (see
[Trusting more servers](reference.md#trusting-more-servers)):

- **Per user, by server name** (no file in the plugin):
  `MORPH_READ_ONLY_SERVERS="plugin_grafana_grafana"`. Caveat: it also trusts a
  plugin with the same plugin and server names installed from another
  marketplace.
- **Per marketplace, by declaration:** the plugin ships
  `.claude-plugin/read-only-servers.json` (`{"servers": ["grafana"]}`) and users
  set `MORPH_TRUSTED_MARKETPLACES="morph <marketplace>"`. Anyone who can push to
  that marketplace can then declare a server read-only or drop
  `--disable-write`, so require branch protection with a reviewer on
  `plugins/*/scripts/` and the declaration first.

## Updates

Clients update only when `version` in `plugin.json` changes: bump it on every
change under `plugins/<plugin>/`. To pull an update by hand:

```bash
claude plugin marketplace update <marketplace>
claude plugin update <plugin>@<marketplace>
```

and restart Claude Code. The token stays configured.

## Validator notes

`claude plugin validate --profile directory` also asks for a README and a
LICENSE inside the plugin folder and an icon. Those are requirements of the
public plugin directory; a private marketplace can ignore them.

## Checklist for a new plugin

- Pin the server version; use the server's own read-only flags.
- Token through `userConfig`, `sensitive: true`, with a `description`;
  least-privileged role.
- No `dependencies` on morph.
- `claude plugin validate` for the marketplace and the plugin.
- Brief tested with `echo '{"hook_event_name":"SubagentStart"}' | bash …/brief.sh`.
- List the server's tools and note which names are not read-shaped for the guard.
- Git access without prompting (credential helper; Git Credential Manager for
  Azure DevOps over HTTPS).
- Remove any hand-installed copy of the same server before testing.
- Branch protection with a reviewer on `plugins/*/scripts/`, and on the
  declaration if you ship one.
- Bump `version` on every change.
