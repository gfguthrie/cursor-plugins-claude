---
name: setup-pstack
description: Configure which models pstack uses per role. Detects your available models and writes the config that overrides the skill defaults. Use for /setup-pstack, "configure pstack models", or changing pstack's model choices.
---

# Setup pstack

Write `~/.claude/pstack-models.md`, the file that sets pstack's model per role. The skills read it and fall back to their inline defaults when a line is absent, so this is an override layer, not a requirement.

Those inline defaults name Cursor's model slugs (`grok-4.6-fast-xhigh`, `gpt-5.6-sol-max`), which Claude Code cannot spawn. Running this skill once replaces all of them, so treat it as setup rather than as tuning.

## Steps

### 1. Detect available models

Enumerate the model values you can pass to a subagent in this session; that is the dependable source. Claude Code accepts the aliases `opus`, `sonnet`, `haiku`, and `fable`, plus full model IDs. If you cannot confirm a value, ask the user which models they have access to. Never write a slug you have not confirmed is available — a role pointing at an unavailable model fails with `unrecognized_model` and the subagent never runs. The alias `inherit` is always valid.

### 2. Load current state

The default role-to-model mapping is the rule shape shown in step 5 below. If `~/.claude/pstack-models.md` already exists, read it and treat its values as the current choices. Otherwise start from those defaults.

### 3. Map and confirm

Show every role with its current model, marking any real slug not in the detected set as needing a choice. Ask whether to accept as-is or change specific roles, offering the detected models plus `inherit` (this role runs on the parent chat model) as the options. Prefer AskUserQuestion over free text. For panel roles (how critics, arena runners, architect runners, interrogate reviewers) the value is a list, and one subagent runs per entry, alias entries included, so the list length sets the count. `arena cross-judge pool` is also a list, but Arena selects one value from it whose model family differs from the parent's when possible. `swarm workers` is the default model for every worker unless a race or comparison assigns another model per arm.

### 4. Validate

Every real slug written must be in the detected set; `inherit` always passes. If a chosen real slug is not available, stop and ask again. A config pointing at a model the user cannot use breaks every delegation that reads it.

### 5. Write the rule

Write `~/.claude/pstack-models.md` as one line per role, using the same labels poteto-mode uses. Overwrite the whole file so re-runs stay idempotent. Shape:

```
# pstack model configuration. One line per role. Delete a line to fall back to the skill default.
# `inherit` as a value: the role runs on the parent chat model (omit the subagent `model`). Alias entries in a panel list still count toward its fan-out.
feature, refactoring: sonnet
bug-fix: opus
perf-issue: opus
hillclimb: opus
judgment and prose: fable
hardest tasks: opus
how explorer: sonnet
how explainer: fable
how critics: opus, fable, sonnet, haiku
why investigators: sonnet
why synthesizer: fable
reflect tooling: opus
reflect judgment, divergent, synthesizer: fable
arena runners: opus, fable, sonnet, haiku
arena cross-judge pool: opus, fable, sonnet, haiku
swarm workers: sonnet
architect runners: opus, fable, sonnet, haiku
interrogate reviewers: opus, fable, sonnet, haiku
```

Panel roles are the one place this mapping loses something. Upstream fans them across vendors so a reviewer's blind spots are not the parent's; every value here is a Claude model, so the panels vary capability and cost rather than lineage. Keep the entry count — the fan-out is still worth it — but do not read a panel's agreement as cross-vendor corroboration.

### 6. Confirm

Tell the user the config was written. The skills read it when they run, so it takes effect immediately. Re-running this skill updates it.

### 7. Offer a verification skill (optional)

Check whether the project has a way to drive the real app for proof (a `verify-*` skill, or an existing harness). If not, offer once: "want a project-local verification skill, so agents can drive the app the way a user does and prove changes work? I can generate one with /create-verification-skill." On yes, invoke `/create-verification-skill` (resolves wherever pstack is installed — workspace, user, or plugin). On no, move on without pushing.
