# Make plugging in a team's own domain plugin easy (Grafana as the worked example) — 2026-10-30

Status: draft, not approved. Steps are outlined; refine in the session that takes it.

## Summary

`morph` does not ship Grafana. It must let any team plug in a domain plugin of its own, from its own marketplace, without changing this repository. Grafana is the worked example. Deliver:
- a template,
- a dedicated documentation page,
- a real end-to-end test of a plugin from a separate repository.

## The scenario, from the team's side (nothing changes in morph)

1. **The team's own repository is its own marketplace,** on any git host it can clone from (ADO, private GitHub, GitLab):
   ```
   team-plugins/                              e.g. dev.azure.com/org/proj/_git/team-plugins
     .claude-plugin/marketplace.json          {"name":"otcf","owner":{"name":"OTCF DevOps"},"plugins":[{"name":"grafana","source":"./plugins/grafana"}]}
     plugins/grafana/
       .claude-plugin/plugin.json             dependency on morph, userConfig, MCP server
       scripts/grafana-mcp.sh                 launches the server
       scripts/brief.sh                       start-up brief for the agents
       hooks/hooks.json                       SessionStart + SubagentStart -> brief.sh
       skills/grafana-triage/SKILL.md         team knowledge: dashboards, symptoms
   ```
2. **`plugin.json`.** It declares `"dependencies": ["morph@morph"]`, so installing the plugin pulls in morph and morph cannot be disabled while the plugin is on. `userConfig` asks each user for `grafana_url` and `grafana_token` (`sensitive: true`), so no secret sits in the repository, a file or a process argument. The `mcpServers.grafana` entry runs `bash ${CLAUDE_PLUGIN_ROOT}/scripts/grafana-mcp.sh` with `GRAFANA_URL` and `GRAFANA_SERVICE_ACCOUNT_TOKEN` taken from `${user_config.*}`.
3. **`grafana-mcp.sh`.** It reads the URL and token from the environment, falls back to the keychain on macOS, and finds `uvx` on PATH.
4. **The brief** copies the pattern in `plugins/devops/hooks/` and `scripts/brief.sh`; only the text changes:
   > Grafana is available (`mcp__plugin_grafana_grafana__*`). Binding: before investigating latency, error rates, pod restarts or alerts, load `grafana:grafana-triage`. Reads (search, get, query, list) are fine; never create or update dashboards or incidents.
5. **The skill** says which dashboards, data sources and queries fit which symptom. Its description names the symptoms, because that is what decides whether the skill gets picked.
6. **Local test before publishing:**
   ```bash
   claude plugin validate ~/Repositories/team-plugins
   claude plugin validate ~/Repositories/team-plugins/plugins/grafana
   claude plugin marketplace add ~/Repositories/team-plugins
   claude plugin install grafana@otcf
   claude plugin configure grafana@otcf
   claude plugin enable grafana@otcf
   claude mcp list | grep grafana
   ```
7. **Publishing.** Each member runs `claude plugin marketplace add <repo url>`, `install` and `configure`. Alternatively, a repository's `.claude/settings.json` lists the marketplace in `extraKnownMarketplaces` and the plugin in `enabledPlugins`, and Claude Code offers the install once the folder is trusted.
8. **Updates.** Without `version`, every commit is a new version, and `autoUpdate: true` on the marketplace picks it up.

## What morph already provides

| Mechanism | Where in morph |
|---|---|
| Domain briefs are binding | `morph:morph` prompt, rule 7 |
| Subagents inherit other plugins' tools | `disallowedTools` instead of `tools` on implementer and investigator |
| Investigator looks for a skill covering the system | `morph:investigator` prompt |
| Live writes and publishing ask; subagents are denied | guards in `claude/settings.json` |
| Brief pattern to copy | `plugins/devops/hooks/` and `scripts/brief.sh` |

## Steps (changes in morph)

1. **Template.** Add `templates/domain-plugin/` with a skeleton: `plugin.json`, `hooks/hooks.json`, `scripts/brief.sh` and one `SKILL.md` with placeholders. Optionally add a `morph:new-plugin` skill that fills it in. Decide between the two in this step.
2. **Docs.** Add `docs/your-plugin.md` holding the scenario above. Shorten "Your own plugin" in `docs/reference.md` to a pointer.
3. **Cross-marketplace test.** Build a real Grafana plugin in a separate repository and verify:
   - `dependencies: ["morph@morph"]` resolving across marketplaces;
   - installing from a private ADO repository;
   - the brief reaching both the main session and `morph:investigator`;
   - the guard verdicts on Grafana's tool names.

   Record the results in the docs.

Out of scope here: trusting a team plugin's MCP servers wholesale. That is `plugin-declared-read-only-servers-2026-10-30.md`.

## Risks & Mitigations

- **Grafana tools that read but do not look like reads.** Names such as `generate_deeplink` and `check_datasources_health` match no read marker, so the main session is asked and subagents are denied. Until trust lands, document this in `docs/your-plugin.md`.
- **The template drifts from `devops`.** Mitigation: generate `devops`'s brief from the same template, or add a CI check that compares the two.

## Validation Plan

```bash
claude plugin validate templates/domain-plugin
bash claude/tests/guards.sh
```

Then run the end-to-end steps 6–7 above against the separate repository.
