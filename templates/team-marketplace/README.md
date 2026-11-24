# Example team plugins

Private Claude Code marketplace `example-team`. Copied from the morph template
in `templates/team-marketplace/`; see morph's `docs/your-plugin.md` for the
reasoning behind each file.

## grafana

Read-only Grafana MCP server for https://grafana.example.com
(`mcp-grafana --disable-write --disable-api`). A short brief at session and
subagent start tells agents to check Grafana for latency, errors, restarts,
failed deploys and alerts.

### Install

Requires `uv` (for `uvx`, https://docs.astral.sh/uv/) and `jq`.

Git must reach this repository without prompting, because Claude Code turns git
prompts off when it clones a marketplace. Check with:

```bash
git -c core.askPass= ls-remote <repository URL>
```

If that asks for a username, set up a credential helper first. For Azure DevOps
over HTTPS, Git Credential Manager:

```bash
brew install --cask git-credential-manager   # or your platform's package
git-credential-manager configure
git ls-remote <repository URL>               # one browser login
```

On macOS answer the Keychain prompts with **Always Allow**, or background
marketplace updates will hang.

Then:

```bash
claude plugin marketplace add <repository URL>
claude plugin install grafana@example-team
read -rs t && jq -nc --arg t "$t" '{grafana_token:$t}' \
  | claude plugin configure grafana@example-team --values-stdin; unset t
```

Or configure the token in a session: `/plugin` -> `grafana@example-team` ->
configure. `claude plugin configure` without `--values-stdin` only shows the
options; it saves nothing.

The token is a Grafana service account with the **Viewer** role. Claude Code
stores it in its secure storage; it is never written to this repository or a
settings file. Start a new session and check `/mcp`: `plugin:grafana:grafana`
should be connected.

### Update

```bash
claude plugin marketplace update example-team
claude plugin update grafana@example-team
```

Restart Claude Code afterwards. The token stays configured.

### Changing the plugin

Every change under `plugins/grafana/` needs a `version` bump in
`plugins/grafana/.claude-plugin/plugin.json`. Clients update only when the
version changes.

Protect `main` with a required reviewer for `plugins/*/scripts/`: anyone who can
push there can remove `--disable-write` from the launcher.

## Renaming this template

Replace, in every file:

| Template value | Yours |
|---|---|
| `example-team` | your marketplace name |
| `Example Team` | your team name |
| `grafana.example.com` | your Grafana host |

Keep the plugin and server name `grafana` unless you have a reason to change it:
the tool names (`mcp__plugin_grafana_grafana__*`) and the brief depend on it.
Then run `claude plugin validate .` and `claude plugin validate plugins/grafana`.
