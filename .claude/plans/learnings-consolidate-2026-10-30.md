# Add `morph:learnings-consolidate`: keep agent memory short, current and consistent — 2026-10-30

## Summary

The learnings loop only appends. Every long session can add a proposal to `.claude/claude-md-review.md`, and applied proposals grow the agent-maintained section of `AGENTS.md`. Nothing merges duplicates, drops what stopped being true, or catches contradictions.

Add a skill that reviews that memory against the repository as it is now and returns a consolidation proposal — never a direct edit — through the same review flow the learnings loop already uses.

Prior art: Databricks MemCurrent (a "dreaming" pass). Memory there is distilled offline, then merged, split and de-conflicted; curated memory beat full history at ~12x fewer tokens. Not adopted from it: automatic writes and a database. Here memory is shared, reviewed text in git, and a wrong line reaches every session that reads it.

## Current state (read before changing anything)

- `plugins/morph/skills/learnings/SKILL.md` — the policy: what qualifies, the review file, the `## YYYY-MM-DD — title` heading contract, and the `— APPLIED` marker.
- `plugins/morph/scripts/learnings-queue.sh` — SessionEnd: a headless child returns PROPOSAL or NOTHING, and the hook writes the review file. It skips digests under 40 lines.
- `plugins/morph/scripts/learnings-pending.sh` — SessionStart: counts unapplied dated headings and asks the session to raise them.
- Agent-maintained section: any `## … (agent-maintained)` heading in `AGENTS.md`. Older repositories use `## DevOps Conventions (agent-maintained)`.

## Design

**Input, per repository:**
- the agent-maintained section(s) of `AGENTS.md`;
- `.claude/claude-md-review.md`, both pending and applied entries;
- `.claude/rules/*.md`, if the repository has already split memory there.

**Checks, per bullet:**
1. **Duplicate or overlap.** Two bullets say the same thing, or one subsumes the other: propose one merged bullet.
2. **Stale.** Verify against the repository: referenced paths exist (Glob/Read), commands and flags still appear in scripts, CI or docs (Grep), and pinned versions match lockfiles or constraints. Unverifiable is its own outcome: flag it, never drop it on absence of evidence.
3. **Conflict.** Two bullets give incompatible instructions: show both, say which one the repository supports now, and ask. Never pick silently.
4. **Event, not fact.** A bullet records what happened rather than how the place works (see the learnings policy): rewrite it as a rule or drop it.
5. **Review-file hygiene.** Applied entries older than 90 days, and pending entries already present in `AGENTS.md` (applied but never marked): propose marking or removing them.
6. **Size.** When the section passes ~60 bullets or ~8 KB, propose a split into `.claude/rules/<topic>.md` with a short index left in `AGENTS.md`.

**Output:** one dated entry at the top of the review file, headed `## YYYY-MM-DD — Consolidation`.
- Items are grouped by action: merge, drop, rewrite, conflict, split.
- Each item gives the exact before and after text and the evidence: `file:line`, or "not found in <paths>".
- A count line on top: bullets before → after, and how many were flagged unverifiable.

The skill edits nothing else. Applying it is the normal path: the user approves, Morph edits `AGENTS.md` on a branch per `morph:delivery`, and marks the entry `— APPLIED`.

**How it runs:**
- On request ("consolidate learnings", "clean up AGENTS.md") in a Morph session.
- Suggested by `learnings-pending.sh` when there are more than 5 pending entries or the section is past the size threshold. This is a suggestion, never automatic.
- Later, optional: a `/schedule` routine per repository that opens a pull request adding the proposal only.

## Steps

0. Read the current-state files above. Confirm the heading contract and the review-file format the pending hook parses. Build a fixture repository in `$TMPDIR` with:
   - two duplicate bullets;
   - one bullet citing a deleted path;
   - one bullet citing a command that no longer exists;
   - two conflicting bullets;
   - one event;
   - one applied review entry older than 90 days;
   - one pending entry already in `AGENTS.md`.
1. Write `plugins/morph/skills/learnings-consolidate/SKILL.md`. It holds the checks, the evidence rule (no drop without proof; unverifiable is flagged), the output format, and "edit nothing but the review file". The description names the triggers. Reuse wording from `skills/learnings` rather than restating the policy.
2. In `plugins/morph/skills/learnings/SKILL.md`, add one line pointing to the new skill for cleanup, so the two do not drift.
3. In `plugins/morph/scripts/learnings-pending.sh`, when there are more than 5 pending entries or the section is past the size threshold, add one sentence suggesting `morph:learnings-consolidate`. Keep it to the SessionStart stdout; add no new hook.
4. In `plugins/morph/agents/morph.md`, Step 6 (Propose Learnings), add one line mentioning the skill for when the section has grown.
5. Docs: leave the README's "How a task goes" unchanged. Add a short "Consolidation" paragraph to the learnings section of `docs/reference.md`.

## Risks & Mitigations

- **A true fact dropped as stale.** Drop only with evidence. The absence of a match counts as "unverifiable" and is flagged for the human.
- **Large proposals nobody reviews.** Group items by action and put the counts on top. Cap one run at ~30 items and say what was left for the next run.
- **Wrong conflict resolution.** The skill never resolves a conflict. It only presents both bullets with what the repository supports.
- **Pending hook noise.** Threshold-based, one sentence, in the same hook.

## Validation Plan

- Fixture run, headless, with `--plugin-dir ./plugins/morph --agent morph:morph` and the prompt "consolidate learnings in this repository". Check that:
  - every planted case appears under the right action, with evidence;
  - `git -C <fixture> diff` shows only `.claude/claude-md-review.md` changed;
  - the new heading passes the pending hook's dated-heading count.
- `bash -n` and `shellcheck` on `learnings-pending.sh`. Run the pending hook on the fixture and check that it prints the suggestion only past the thresholds.
- `claude plugin validate plugins/morph`.
- One real repository with a populated section (e.g. `gitops-apps-mcd`): run the skill, review the proposal by hand, and apply one item through the normal path.

## Decisions assumed (confirm before starting)

- Output is always a proposal in the review file, never a direct edit, as for the whole learnings loop today.
- Clean-up thresholds: more than 5 unreviewed proposals, or a section above ~60 bullets or ~8 KB. The start hook only suggests; it runs nothing itself.
