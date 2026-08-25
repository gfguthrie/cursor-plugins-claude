# cursor-plugins-claude

[Cursor's official plugins](https://github.com/cursor/plugins) adapted for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

Cursor ships a set of high-quality agent plugins — skills, agents, and rules — but they target Cursor's own runtime. This fork adds the `.claude-plugin/` manifests that Claude Code needs, so you can install the same plugins with a single command.

It ships the plugins whose value is the authoring: skills, agents, commands, and hooks. Upstream's [MCP-only plugins](#mcp-servers) are not in the marketplace, since `claude mcp add` already does that job better than a manifest can.

## Quick start

```sh
# 1. Add the marketplace
/plugin marketplace add gfguthrie/cursor-plugins-claude

# 2. Install any plugin
/plugin install cursor-team-kit@cursor-plugins-claude
```

You can install as many plugins as you need:

```sh
/plugin install teaching@cursor-plugins-claude
/plugin install thermos@cursor-plugins-claude
```

## Available plugins

| `name` | Plugin | Author | Category | `description` (from marketplace) |
|:-------|:-------|:-------|:---------|:-------------------------------------|
| `teaching` | [Teaching](teaching/) | Cursor | Developer Tools | Skill mapping, practice plans, and learning retrospectives. |
| `cursor-team-kit` | [Cursor Team Kit](cursor-team-kit/) | Cursor | Developer Tools | Internal team workflows for CI, code review, shipping, local automation, and verification. |
| `thermos` | [Thermos](thermos/) | Cursor | Developer Tools | Thermo-nuclear branch review: deep security/correctness audits, harsh code-quality rubrics, parallel subagents, thermos orchestration, and optional merge-ready PR flows. |
| `agent-compatibility` | [Agent Compatibility](agent-compatibility/) | Cursor | Developer Tools | CLI-backed repo compatibility scans plus agents that audit startup, validation, and docs against reality. |
| `cli-for-agent` | [CLI for Agents](cli-for-agent/) | Cursor | Developer Tools | Patterns for designing CLIs that coding agents can run reliably: flags, help with examples, pipelines, errors, idempotency, dry-run. |
| `pstack` | [pstack](pstack/) | Lauren Tan | Developer Tools | if you want to go fast, go deep first. pstack helps you write less, but higher quality code. rigorous agent workflows you can parallelize with confidence. |

## Not ported

8 upstream plugins are deliberately absent — 6 because they are built around a piece of Cursor's own runtime that Claude Code has no equivalent of, and 2 because the port is not worth what it costs:

| Plugin | Why |
|:-------|:----|
| `create-plugin` | Scaffolds `.cursor-plugin/` manifests and `.mdc` rules into `~/.cursor/plugins/local/`. Claude Code authors plugins natively. |
| `cursor-sdk` | Reference material for the `@cursor/sdk` npm package, which drives Cursor agents rather than Claude Code. |
| `orchestrate` | Fans work out across Cursor cloud agents via `@cursor/sdk` and `CURSOR_API_KEY`. |
| `docs-canvas` | Needs `~/.cursor/skills-cursor/canvas`, which ships inside the Cursor app. Upstream also marks it a placeholder. |
| `pr-review-canvas` | Same in-app canvas dependency. |
| `ralph-loop` | Anthropic ships its own `ralph-loop` in [`claude-plugins-official`](https://github.com/anthropics/claude-plugins-official) (and `ralph-wiggum` in [`claude-code`](https://github.com/anthropics/claude-code)). Install one of those rather than reworking Cursor's `afterAgentResponse` + done-flag design. |
| `continual-learning` | Its cadence-gated `Stop` hook is the whole product, and its skill is `disable-model-invocation`, so without the hook nothing can trigger it. Porting the hook means owning three upstream files across every future rebase. |
| `x` | The only MCP plugin upstream ships with a skill attached, but both halves are Cursor-shaped: its `mcp.json` carries an `auth` block (OAuth client id plus scopes) with no Claude Code counterpart, and the skill's connect flow and error taxonomy are written around Cursor's Connect UI. Since the guidance exists to explain sign-in and billing failures, misdirecting on exactly those is worse than not shipping it. Add the server with `claude mcp add` and read [the skill](third_party/x/skills/x-api-mcp-guide/SKILL.md) in place — it's worth reading for the credit costs alone. |

The list lives in [`excluded.txt`](.claude/skills/sync-fork/excluded.txt) and is enforced during every sync.

### MCP servers

49 further upstream plugins are only an MCP server config — a `type` and a `url` in an `mcp.json`, with no skills, agents, commands, or hooks. Claude Code adds an MCP server directly, so a manifest around one of those would add nothing but a name in a marketplace:

```sh
claude mcp add --transport http gmail https://gmailmcp.googleapis.com/mcp/v1
```

Their directories are still here under `third_party/`, so the URLs are easy to lift from `mcp.json`. Six also carry a Cursor-specific `auth` block — an OAuth client id and scope list — that has no counterpart in Claude Code's MCP config, so presenting them as ported would overstate what a manifest achieves. `x` is the only one of the fifty that ships a skill; it is excluded on that `auth` block, per the row above.

## What changed from upstream

This fork adds a `.claude-plugin/` directory at the repo root and inside each plugin, containing the marketplace and plugin manifests required by Claude Code. Beyond that the fork changes as little as possible: every upstream file is byte-identical except those listed in [`patched.txt`](.claude/skills/sync-fork/patched.txt), which each carry a Claude Code fix described below.

The fork ships the plugins that carry authored content — skills, agents, commands, or hooks — because that is the part a manifest actually makes usable. Upstream's MCP-only plugins are left in the tree but unshipped, so nothing under `third_party/` currently ships.

## Known gaps

Adding a manifest makes a plugin *installable*; it doesn't translate the parts written against Cursor's runtime. Claude Code discovers `skills/`, `commands/`, and `agents/` on its own, so the bulk of every plugin works — but these pieces don't, and are left as-is rather than silently half-ported:

| Plugin | What doesn't carry over |
|:-------|:------------------------|
| `cursor-team-kit` | `rules/*.mdc` (Cursor's rules format) are not loaded. The `pr-review-canvas` skill needs Cursor's in-app browser; `workflow-from-chats` needs host chat transcripts. |
| `pstack` | Paths and the model config are ported (below), but `automations/` still has no Claude Code equivalent, and the `autopilot-stack`, `autopilot-full`, `shipping`, and `multi-phase-plan` playbooks are written around fleets of Cursor cloud agents. Several skills also route skill-authoring to Cursor's built-in `create-skill`. |
| `agent-compatibility`, `create-plugin`, `cursor-team-kit`, `pstack` | Agent frontmatter keys `readonly:` and `is_background:` are Cursor-only and are ignored — those agents run, but without the intended isolation. Claude Code warns once per file on load. |

Everything not listed here — `teaching` and `cli-for-agent` — has no known Cursor-specific dependency. Their remaining mentions of Cursor are prose in a README, a copyright line, or the CSS property `cursor: pointer`.

**Three sets of upstream changes are patched in**, all listed in `patched.txt`.

`model: fast` → `model: sonnet` on five agents. `fast` is a Cursor model tier; Claude Code rejects it outright (`unrecognized_model`) and the agent terminates with an API error instead of running, so this is a fix rather than a preference.

**`pstack` paths and model config.** Its skills read chat transcripts, write generated verification skills, and look up per-role model choices — all at `~/.cursor/` paths that don't exist under Claude Code. Those failed *silently*: `recall`, `reflect`, and `show-me-your-work` returned a confident empty result rather than an error, and `create-verification-skill` wrote into a directory Claude Code never loads. All of them now point at the Claude Code equivalents, and `/setup-pstack` writes `~/.claude/pstack-models.md` using real Claude model aliases.

**Cursor-only `subagent_type` values.** `generalPurpose` in nine pstack files, and `shell` / `explore` in the three thermo-nuclear review agents, name agent types Claude Code does not have — every fan-out died on its first spawn. They now use `general-purpose` and `Explore`, with the diff collection that `shell` did folded into the parent's own Bash call. The slug rule that maps a workspace path to its transcript directory also now maps `_` to `-`, matching Claude Code; without it any repo path containing an underscore resolved to a directory that doesn't exist.

**Skills reached by name, not by path.** 49 upstream skills ship `disable-model-invocation: true` — all of `pstack` and `thermos`, plus `orchestrate`, `continual-learning`, and two `cursor-team-kit` skills. Claude Code reads that flag as *absent from the model's catalog*, slash-command-only, so a subagent cannot resolve any of those names. Upstream's own agents assume it can, which only works if Cursor's flag merely suppresses proactive triggering while keeping the name resolvable on request.

The three thermo-nuclear review agents hit this hardest: told to *load* their rubric skill, the call could never resolve, and each fell through to its own "if that skill is not available" clause — returning an unrubricked audit that still read like a thermo-nuclear one. pstack degrades more gently, since it says *read the `SKILL.md`* rather than load the skill, but it named files without paths and left the agent searching for them. All of them now name a path: `${CLAUDE_PLUGIN_ROOT}/skills/<name>/SKILL.md`, which Claude Code substitutes inside skill and agent content, and `../principle-<name>/SKILL.md` for poteto-mode's leaf principles. A `find` under `~/.claude/plugins` was the first attempt and was not enough — an installed plugin lives under a commit-sha directory, so the glob matched only a marketplace clone that happened to be on disk, and both reviewers went on improvising. `/thermos` now also reads each rubric itself and passes it in the subagent's prompt, so the one that matters can't be missed. The flag itself is left alone in every case, so a deliberately harsh, expensive review still never auto-triggers.

Run `/setup-pstack` once after installing pstack. Sixteen skill files still name Cursor model slugs as their inline fallback; the generated config overrides every one of them, and patching prose in sixteen more files was not worth the permanent rebase cost. One caveat on that config: upstream fans its review panels across vendors so each reviewer's blind spots differ, and a Claude-only panel varies capability rather than lineage — so don't read panel agreement as cross-vendor corroboration.

## Credits

The Claude Code manifest layout and the first version of the sync workflow come from [Kamil Doroszewicz](https://github.com/kdoroszewicz)'s [cursor-plugins-claude](https://github.com/kdoroszewicz/cursor-plugins-claude), which this fork descends from.

## Keeping up to date

This repo tracks [cursor/plugins](https://github.com/cursor/plugins). When upstream publishes new plugins or updates, this fork will be rebased to include them. The sync workflow is documented in the [sync-fork skill](.claude/skills/sync-fork/SKILL.md) — use it to ensure all manifests stay in sync.

## License

MIT
