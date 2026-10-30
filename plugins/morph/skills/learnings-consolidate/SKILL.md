---
name: learnings-consolidate
description: Review a repository's agent memory against the repository as it is now and propose a consolidation. Use when asked to "consolidate learnings" or "clean up AGENTS.md", when the agent-maintained section has grown past ~60 bullets or ~8 KB, or when more than 5 learnings proposals sit unreviewed.
---

# Consolidating Learnings

`morph:learnings` only appends. This skill is the other half: it merges what overlaps, drops what stopped being true, and surfaces what contradicts. Read `morph:learnings` first — its rules on what qualifies, the heading contract and the `— APPLIED` marker apply here unchanged.

The result is always a proposal in `.claude/claude-md-review.md`. **Edit nothing but that file.** Not `AGENTS.md`, not `CLAUDE.md`, not `.claude/rules/`. Applying an item is the normal path: the user approves, the main session edits `AGENTS.md` on a branch per `morph:delivery`, and marks the entry ` — APPLIED`.

## Input

Per repository, read:

- the agent-maintained section(s) of `AGENTS.md`: any `## … (agent-maintained)` heading, including `## DevOps Conventions (agent-maintained)`;
- `.claude/claude-md-review.md`, pending and applied entries both;
- `.claude/rules/*.md`, if the repository has already split memory there.

## Checks, per bullet

1. **Duplicate or overlap.** Two bullets say the same thing, or one subsumes the other: propose one merged bullet.
2. **Stale.** Verify against the repository, not from memory:
   - a referenced path exists (Glob or Read);
   - a command or flag still appears in scripts, CI or docs (Grep);
   - a pinned version matches the lockfile or constraint.
3. **Conflict.** Two bullets give incompatible instructions. Show both, say which one the repository supports now, and ask.
4. **Event, not fact.** The bullet records what happened rather than how the place works (see "What qualifies" in `morph:learnings`): rewrite it as a rule, or drop it.
5. **Review-file hygiene.** Propose removing applied entries older than 90 days. Propose marking ` — APPLIED` on a pending entry whose content is already in `AGENTS.md`.
6. **Size.** When the section passes ~60 bullets or ~8 KB, propose a split into `.claude/rules/<topic>.md` with a short index left in `AGENTS.md`.

## Evidence rule

- **No drop without proof.** A bullet is dropped as stale only when you found the thing gone: the path is missing, the command is absent from every script and workflow you searched, the version differs. Quote the evidence.
- **What the repository cannot show is "unverifiable", not "stale".** A bullet you cannot check from the repository (an external system, a cloud console, a team agreement) is flagged unverifiable and left in place. Count it.
- **Never resolve a conflict.** Present both bullets and what the repository supports. The user chooses.
- A bullet that survives every check is not mentioned.

## Output

One dated entry at the top of the review file, newest first, directly under the `#` title. The heading follows the contract in `morph:learnings`:

```
## YYYY-MM-DD — Consolidation
```

Any other shape and the SessionStart count reads zero.

Under the heading:

1. A count line first: `Bullets: <before> → <after> if all applied; <n> flagged unverifiable.`
2. Items grouped by action, in this order: **Merge**, **Drop**, **Rewrite**, **Conflict**, **Split**. Omit an empty group. Review-file hygiene items go under **Drop** (removal) or **Rewrite** (marking applied).
3. Each item gives the exact text before and after — the after is pasted verbatim, so it must read like the target file — and the evidence: `file:line`, or `not found in <paths searched>`.
4. A final **Unverifiable** list: the bullets you kept because you could not check them, one line each with why.

Cap one run at about 30 items. Say what was left for the next run, ordered by confidence, so the strongest findings are not the ones cut.

Run headlessly, you do not write the file (see "Where the draft goes" in `morph:learnings`): return the entry as your whole reply, preceded by a line `PROPOSAL`, or a line `NOTHING` and one sentence on why.
