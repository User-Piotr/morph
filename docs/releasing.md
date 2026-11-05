# Releasing

Machines follow the `stable` branch, not `main`. `stable` moves only when a
release is cut, and nothing else writes to it. The commands below publish; run
them yourself.

## Cut a release

1. On a branch, bump `version` in `plugins/morph/.claude-plugin/plugin.json`
   and `plugins/devops/.claude-plugin/plugin.json`, both to `X.Y.Z`. CI fails a
   pull request that changes a plugin without bumping its version relative to
   `origin/stable`.
2. Merge the pull request to `main`.
3. Tag the merge commit and fast-forward `stable` to it:

   ```bash
   git switch main && git pull --ff-only
   git tag vX.Y.Z
   git tag morph--vX.Y.Z
   git tag devops--vX.Y.Z
   git push origin vX.Y.Z morph--vX.Y.Z devops--vX.Y.Z
   git push origin vX.Y.Z:refs/heads/stable   # fast-forward only; rejected otherwise
   ```

   `vX.Y.Z` names the repository. `morph--vX.Y.Z` and `devops--vX.Y.Z` are the
   per-plugin tags that dependency ranges resolve against.
4. Switch the clone to the same tag, so the policy files and guards that
   `install.sh` links into `~/.claude` match the plugins:

   ```bash
   git fetch --tags && git switch --detach vX.Y.Z
   ```
5. Run `./install.sh`. It runs `claude plugin update` for both plugins itself.
   Check that both versions in `installed_plugins.json` equal `X.Y.Z` and that
   `/mcp` shows headroom connected:

   ```bash
   jq -r '.plugins | to_entries[] | select(.key | endswith("@morph")) | "\(.key) \(.value[0].version)"' \
     ~/.claude/plugins/installed_plugins.json
   ```

## First release (v1.0.0)

Machines registered before the channel existed follow `main` until the
marketplace is re-added at the ref. Re-running `./install.sh` does that once
and logs it. Do it on one machine first and check that the plugins resolve from
`stable` before announcing:

```bash
claude plugin marketplace update morph
jq '.plugins["morph@morph"][0].version' ~/.claude/plugins/installed_plugins.json
```

The migration removes the marketplace, which takes `morph@morph` and
`devops@morph` with it until the installer adds them back. A machine that kept
them stays on the old commit until the installer's `claude plugin update`
moves it; confirm both report `1.0.0`, and that `/mcp` shows headroom connected. Pick a trial machine
whose context7 key was set with `/plugin configure morph@morph`, not from
`.env`, and confirm one context7 call still works afterwards. If the key is
gone, set it again with `/plugin configure` before announcing, and say so in
the announcement.

The CI version check skips while `stable` does not exist. After this release,
prove it once: a pull request that changes a plugin without a version bump must
fail the `versions` job.

## Branch protection

Protect `stable`: restrict pushes to the release owner, and block force pushes
and deletion. The release step above is a fast-forward push by that owner, so
"no direct pushes at all" would reject every release and freeze the channel.
