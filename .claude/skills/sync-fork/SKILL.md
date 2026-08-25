---
name: sync-fork
description: Sync this fork with upstream (cursor/plugins) and keep the Claude Code manifests in step. Use whenever the user mentions syncing or rebasing onto upstream, pulling in new Cursor plugins, the fork being behind, or upstream adding, removing, renaming, or editing plugins — even if they don't name this skill.
---

# Sync Fork with Upstream

## Overview

This repo is a fork of `cursor/plugins` that adds `.claude-plugin/` manifests for Claude Code compatibility. The fork maintains a single custom commit on top of upstream. Syncing means rebasing that commit onto the latest `upstream/main` and updating all Claude Code manifests to match.

Almost everything the fork adds is *derived* from upstream's `.cursor-plugin/` files, so most of this workflow is mechanical. Two bundled scripts do it: `scripts/sync-manifests.sh` regenerates every derived artifact, and `scripts/check-manifests.sh` verifies the whole derivation and is the fastest way to find what still needs doing.

## What counts as a plugin directory

A directory containing `.cursor-plugin/plugin.json`, either at the top level or one level under `third_party/` (where upstream keeps the third-party MCP plugins). Everything else at the top level — `schemas/`, `scripts/`, `third_party/` itself — is upstream infrastructure, not a plugin, and must not get a Claude manifest or a marketplace entry. Any check that globs `*/` without this filter will report false positives and miss every `third_party/` plugin.

The authoritative list is `.cursor-plugin/marketplace.json` → `.plugins[].source`, which carries each plugin's path relative to the repo root. Its `.name` is the bare slug, not the path.

## Scope

**The fork ships a plugin only if it carries authored content: a `skills/`, `agents/`, `commands/`, or `hooks/` directory.** That content is what a Claude Code manifest makes usable, and porting it is the whole point of the repo.

A plugin with none of those is an MCP server config in a wrapper — typically a `type` and a `url`, which `claude mcp add --transport http <name> <url>` handles directly. A manifest around it buys the user a name in a marketplace and nothing else, while costing the fork a manifest, a marketplace entry, and a README row per plugin. Six of upstream's also carry a Cursor-specific `auth` block (OAuth client id plus scopes) with no counterpart in Claude Code's MCP config, so shipping them would assert a compatibility nobody has verified.

Today that rule leaves out 49 of upstream's plugins, all under `third_party/`. Both scripts derive it from the filesystem rather than from a list, so a plugin that gains a `skills/` directory upstream starts shipping on the next sync with no bookkeeping — and the check script fails if an out-of-scope plugin still carries a manifest.

This is a different mechanism from `excluded.txt` and the two don't overlap: scope is a structural property of the plugin, while an exclusion is a judgment call about a plugin that *does* carry content. All eight current exclusions have skills. `third_party/x` is the case that shows the seam — it is upstream's only MCP plugin with a skill, so it passes the scope rule and is then excluded on its merits, not by structure.

The directories stay in the tree either way. Nothing about being out of scope makes an upstream file worth deleting — the fork only adds.

## Excluded plugins

`.claude/skills/sync-fork/excluded.txt` lists upstream plugins the fork deliberately does not ship. Three things put a plugin here: it is built around a piece of Cursor's own runtime that Claude Code has no equivalent of; Anthropic already ships an equivalent, so the fork's copy would be the worse of two options; or the port would cost more in permanent rebase burden than the plugin is worth. They get no `.claude-plugin/` manifest, no marketplace entry, and no README table row, and they are out of scope for compatibility fixes: don't "repair" a plugin that's on this list.

So the fork's shipped set is upstream's plugin set minus the out-of-scope plugins above and minus this file, and every derivation below operates on that shipped set. The check script enforces both directions — an excluded plugin that still carries a manifest fails, and so does an entry naming a plugin upstream has since deleted.

Adding to the list is a judgment call and a user-visible removal; the README's "Not ported" table is where that reasoning is published, so update it in the same change.

## Patched upstream files

`.claude/skills/sync-fork/patched.txt` lists the upstream files the fork modifies for Claude Code compatibility. Everything else must stay byte-identical to upstream, and the check script enforces both halves: a listed file that no longer differs from upstream (a rebase took upstream's copy and silently reverted the port), and an unlisted file that does differ.

These are the only files that will genuinely conflict on a rebase. Resolve them by re-applying the fork's change on top of upstream's new text — never by taking a side wholesale. Taking "theirs" reverts the port; taking "ours" drops whatever upstream just fixed.

Keep the list short. Every entry is a permanent rebase cost, so a port is worth it only when the change is mechanical and the plugin is otherwise sound; anything needing a redesign belongs in the README's "Known gaps" table until someone decides to do it properly.

When a port would need several entries to make one plugin work, weigh excluding the plugin instead. A plugin whose value depends entirely on the patched files is a bad trade: the fork pays the rebase cost forever, and a single "take theirs" resolution silently returns it to broken. Prefer patches that are one line each and independent of one another, like the `model:` fixes currently listed.

## Field derivation

Two upstream files feed the fork, and they carry *different* descriptions for the same plugin — a long one in the plugin manifest, a short one in the marketplace. That's intentional upstream, so don't reconcile them.

`<p>` below is the plugin's path (`pstack`, or `third_party/<slug>` for a third-party plugin); `<slug>` is its basename.

| Fork field | Source |
|:--|:--|
| `<p>/.claude-plugin/plugin.json` → `name` | `<slug>` — the directory *basename*, never the path |
| `<p>/.claude-plugin/plugin.json` → `description` | `<p>/.cursor-plugin/plugin.json` → `description` (the long text) |
| `<p>/.claude-plugin/plugin.json` → `author` | `<p>/.cursor-plugin/plugin.json` → `author` |
| `<p>/.claude-plugin/plugin.json` → `mcpServers` | `./mcp.json`, but only when `<p>/mcp.json` exists |
| marketplace entry → `description` | root `.cursor-plugin/marketplace.json` (the short text) |
| marketplace entry → `author` | `<p>/.cursor-plugin/plugin.json` → `author` |
| marketplace entry → `source` | `./<p>` |
| marketplace entry → `category` | always `developer-tools` |
| README table row | name, plugin dir link, author, category, marketplace description verbatim |

Traps in that table:

- **`author` is per-plugin, not always Cursor.** `pstack` is authored by Lauren Tan. Copying a hardcoded Cursor author into a third-party plugin mis-attributes it in the manifest *and* the README column.
- **`author` may have no `email`.** `pstack` is the only one today. Build the object from the keys upstream actually has rather than from a fixed `{name, email}` shape: a derivation that reaches for a missing key writes `"email": null`, which the author comparison reads as matching upstream. The check script now fails on any null-valued key.
- **`category` deliberately ignores upstream.** Upstream's per-plugin `category` varies (`teaching` says `utilities`, the MCP plugins say `productivity`/`integrations`); Claude Code's marketplace wants `developer-tools` across the board, in the manifest *and* the README column.
- **`mcpServers` has no upstream analogue worth copying verbatim.** Claude Code auto-discovers `skills/`, `commands/`, and `agents/`, so those keys stay out — but it does not auto-discover a file named `mcp.json`. Without the explicit pointer an MCP plugin installs as a working no-op, which nothing else in the checks would catch.
- **`version` is deliberately absent, and copying upstream's is a regression.** In Claude Code a declared `version` *pins* the plugin: installs only update when that string changes. Upstream leaves most plugins at `1.0.0` while rewriting their skills, so a copied version would freeze every user at whatever they first pulled. Leaving it out makes each sync deliver current content. The check script fails if one appears.

The root manifest's own `name`, `description`, and `owner` are *not* derived from upstream — `owner` is the fork maintainer, since a Claude Code user who hits a broken manifest is looking at the fork's work, not Cursor's. Per-plugin `author` stays upstream's. Don't let a conflict resolution pull Cursor's marketplace `owner` back in.

## Before you start

Two preconditions, both of which the rebase will otherwise enforce the hard way.

**The working tree must be clean.** `git rebase upstream/main` refuses to run with unstaged changes, so decide up front where in-flight work goes.

**There must be exactly one commit on top of upstream** (`git log --oneline upstream/main..HEAD`). The single-commit shape is what makes the force-push model safe and keeps `git diff upstream/main` readable as "just the fork's additions."

Those two combine into one move: fork work in progress belongs *in* the existing commit, not stacked on top of it.

```sh
git add .gitignore .claude .claude-plugin README.md '**/.claude-plugin/plugin.json' $(awk -F'\t' '!/^#/ && NF {print $1}' .claude/skills/sync-fork/patched.txt)
git commit --amend --no-edit
```

Amending rewrites an already-pushed commit, which sounds alarming but costs nothing here — step 7 force-pushes regardless.

If the work is worth reviewing as its own commit first, commit it normally and collapse before rebasing:

```sh
git reset --soft $(git merge-base HEAD upstream/main)
git commit -m "Add Claude Code marketplace compatibility"
```

## Workflow

### 1. Fetch and analyze

```sh
git fetch upstream
git log --oneline HEAD..upstream/main        # new upstream commits
git log --oneline upstream/main..HEAD        # our commits — exactly 1, see "Before you start"
git diff --stat $(git merge-base HEAD upstream/main) upstream/main   # what changed upstream
bash .claude/skills/sync-fork/scripts/check-manifests.sh             # pre-existing drift?
```

If `HEAD..upstream/main` is empty, there's nothing to sync — but still run the check, since drift can predate this sync and you don't want to attribute it to the rebase later.

Diff from the merge base, not from `HEAD` — a plain `git diff HEAD upstream/main` also renders every fork manifest as deleted and the README rewrite as reverted, which reads like upstream removed things it never touched.

Then sweep the incoming content for Cursor-isms. New upstream prose is how the port rots: nothing conflicts, no check fires, and the plugin just quietly stops working under Claude Code.

```sh
git diff --name-only $(git merge-base HEAD upstream/main) upstream/main \
  | xargs -r git grep -nE 'generalPurpose|subagent_type: *.?(shell|explore)|model: *.?fast|^readonly:|^is_background:|~/\.cursor' upstream/main --
```

Each hit is a known incompatibility: `generalPurpose` and lowercase `shell`/`explore` are subagent types Claude Code doesn't have (`general-purpose`, `Explore`); `model: fast` is `unrecognized_model`; `readonly:` and `is_background:` are silently ignored frontmatter. Two more can't be grepped for and need reading: a `Skill` call by name to a skill shipping `disable-model-invocation: true` (unresolvable — it must be read as a file by path), and transcript-slug prose that omits `_` from the `/`, `.`, `_` → `-` transform.

Write that path as `${CLAUDE_PLUGIN_ROOT}/skills/<name>/SKILL.md`, which Claude Code substitutes anywhere in skill and agent content. Do **not** hand the agent a `find ~/.claude/plugins -path '*/<plugin>/skills/…'` glob: an installed plugin lives under a commit-sha directory (`cache/<marketplace>/<plugin>/<sha>/skills/…`), so that glob matches only a marketplace clone that happens to be on disk — and a looser glob matches every cached commit, letting `head -1` pick a stale one. Either way the read fails or reads the wrong copy, the agent falls through to its "if the skill is not available" clause, and it returns a plausible improvised audit instead of the rubric's. Where a parent agent spawns the subagent, have the parent read the file and pass it inline too; a rubric already in the prompt can't be missed.

A hit in a file already in `patched.txt` means upstream rewrote around the fix — re-apply it. A hit in a new file is a new patch-or-exclude decision, so weigh it against "Patched upstream files" above before committing to carrying it.

### 2. Rebase

```sh
git rebase upstream/main
```

We maintain exactly one commit on top of upstream. Rebase keeps history linear.

### 3. Resolve conflicts

**README.md** will almost always conflict. Resolution approach:

- Start from **upstream's content** as the base (it has the current plugin list)
- Re-apply our fork-specific sections on top: title, description, "Quick start", "Not ported", "What changed from upstream", "Known gaps", "Credits", "Keeping up to date". None exist upstream, so every one of them is lost the moment you take upstream's file as the base — the check script fails if any is missing.
- The quick-start's `/plugin marketplace add <owner>/cursor-plugins-claude` names *this* checkout's `origin` owner. Read it rather than recalling it: `git remote get-url origin` → take the owner segment. Never take upstream's.
- Update the plugin tables and install examples to reflect the current plugin set

**Do NOT** just keep "our version" — upstream's plugin list changes must be incorporated.

**The table's row *set* comes from `.cursor-plugin/marketplace.json`, not from upstream's README.** Upstream's README lags its own manifest — at `fdf357f` it was missing Outlook, Outlook Calendar, and OneDrive, all three of which upstream had already shipped. Taking its rows as the base silently drops whatever it forgot. Derive the set from the manifest (minus `excluded.txt`), and every cell from the sources in "Field derivation" above; the check script asserts all four cells of every row, so a row copied from upstream's README will fail on Category regardless.

In practice: resolve the conflict by keeping the *prose* right and letting `sync-manifests.sh` (step 4) rebuild the table. Taking either side's table wholesale is fine as an intermediate state — the generator replaces it either way.

Row *order* is cosmetic and not checked. Existing rows keep their place and new plugins are appended, which is what the generator does; don't re-sort the table to match the manifest.

Two things to fix by hand if you do resolve the table manually: rows taken from upstream carry upstream's Category values (`Productivity`, `Integrations`, `Utilities`), which all become `Developer Tools`, and upstream trails its table with an "Author values match…" footnote that the fork drops.

Three sentences in the fork's prose carry counts (plugins excluded, MCP-only plugins out of scope, skills with `disable-model-invocation`). The check script derives all three and fails on a mismatch, so update them here rather than discovering it in step 6.

### 4. Handle plugin changes

Check the upstream diff for added, removed, renamed, and **edited** plugin directories. The last case is the easiest to miss: upstream rewrites a plugin's description far more often than it adds or drops one, and nothing about that shows up as a conflict — the fork's copy just quietly goes stale. The check script exists mostly to catch this.

Every case below except renames is mechanical, so run the generator rather than doing it by hand:

```sh
bash .claude/skills/sync-fork/scripts/sync-manifests.sh            # dry run — shows the diff
bash .claude/skills/sync-fork/scripts/sync-manifests.sh --write    # apply
```

It rewrites all three derived artifacts — every per-plugin manifest, the root marketplace's `.plugins` array, and the README plugin table — from upstream's files, adding and dropping plugins as the shipped set requires. It preserves README row order and touches nothing else: the root manifest's own `name`, `description`, `owner`, and `renames` survive, and so does every line of README prose. It is idempotent, so a clean dry run means the fork is already fully derived.

Four things it does *not* do, and they are the whole of the manual work left:

- **Renames.** It treats a rename as a drop plus an add; the `renames` entry is a judgment call, so add it yourself (see below).
- **Orphan manifest files.** A dropped plugin loses its marketplace entry and README row, but `<plugin>/.claude-plugin/plugin.json` stays on disk. The check script reports it; remove it with `git rm -f`.
- **The `excluded.txt` decision.** It ships whatever upstream ships minus that file. Deciding a new plugin belongs on the list is step 1 work, not this step's.
- **Prose.** The fork's counts and "Not ported" table are yours; the check script's `README counts` section says when they no longer match.

The rest of this step is the specification the generator implements — read it when a result looks wrong, when you are resolving a conflict by hand mid-rebase, or when changing the generator itself.

**For each ADDED plugin** (first check it carries authored content and is not in `excluded.txt` — if either fails, there is nothing to do):
- Create `<path>/.claude-plugin/plugin.json`:
  ```json
  {
    "name": "<plugin-slug>",
    "description": "<long description from upstream's <path>/.cursor-plugin/plugin.json>",
    "author": { "name": "<from that same file>", "email": "<from that same file, omitted when absent>" },
    "mcpServers": "./mcp.json"
  }
  ```
  Drop `mcpServers` unless `<path>/mcp.json` exists.
- Add entry to `.claude-plugin/marketplace.json`:
  ```json
  {
    "name": "<plugin-slug>",
    "description": "<short description from upstream's root .cursor-plugin/marketplace.json>",
    "source": "./<path>",
    "category": "developer-tools",
    "author": { "name": "<from the plugin's .cursor-plugin/plugin.json>", "email": "<same>" }
  }
  ```
  Without `source`, the marketplace parses but the plugin can't be installed. For a third-party plugin the path segment is `third_party/<slug>`, so `source` is `./third_party/<slug>` while `name` stays the bare slug.
- Add row to README.md plugin table, copying the description verbatim from the marketplace entry

**For each REMOVED plugin:**
- Delete `<plugin>/.claude-plugin/plugin.json` (use `git rm -f` during rebase)
- Remove entry from `.claude-plugin/marketplace.json`
- Remove row from README.md plugin table

**For each RENAMED plugin:**
- Treat as remove old + add new
- Also add `"<old-name>": "<new-name>"` to the root manifest's `renames` object, so anyone who already installed the old name follows the rename instead of losing the plugin

**For each MODIFIED plugin** (present before and after, but upstream edited its metadata):
- Re-copy `description` and `author` into `<plugin>/.claude-plugin/plugin.json` from upstream's plugin manifest
- Re-copy the short `description` and `author` into the marketplace entry
- Update the README row if the marketplace description changed

The fork adds no wording of its own to any of these fields — a shortened or reworded description is stale, not a local edit, so always take upstream's text wholesale.

### 5. Complete rebase

Only if step 2 stopped on conflicts — a clean rebase is already done, and `git rebase --continue` will error with "no rebase in progress".

```sh
git add .claude .claude-plugin README.md '**/.claude-plugin/plugin.json' $(awk -F'\t' '!/^#/ && NF {print $1}' .claude/skills/sync-fork/patched.txt)   # stage what you actually touched, not -A
git rebase --continue
```

### 6. Verify

```sh
bash .claude/skills/sync-fork/scripts/check-manifests.sh
git log --oneline -5                    # our commit on top
git diff upstream/main --stat           # the four fork-owned areas plus exactly the patched.txt set
```

The script checks the plugin-dir set against both marketplaces, the exclusion list against upstream and against stray manifests, every patched upstream file against upstream in both directions, every per-plugin manifest against upstream's (including a sweep for null-valued keys), every marketplace entry's description/source/category/author, all four cells of every README row (link target, author, category, description), and the three derived counts in the fork's prose. It also sweeps for `.claude-plugin/plugin.json` files whose plugin upstream deleted — those vanish from the plugin-dir set, so nothing else would reach them. It exits non-zero and names each mismatch, so a clean run is the real gate.

The `git diff` is a sanity check on *scope*: the fork owns `.claude/`, `.claude-plugin/`, per-plugin `.claude-plugin/`, `.gitignore`, and `README.md`, and touches nothing else except the files named in `patched.txt` — which is exactly what the script's "patched upstream files" section asserts, so read the diff for surprises rather than as the gate. `.claude/skills/sync-fork/SKILL.md` lives in the fork commit too, so it always shows up.

### 7. Push

```sh
git branch --show-current               # must be main
git push --force-with-lease origin main
```

If you did the rebase on a temporary branch (see below), fast-forward `main` to it first — `git push origin main` pushes the local `main` ref, not `HEAD`, so pushing from the temp branch silently force-pushes the stale pre-rebase `main`.

## Key files

| File | Purpose |
|:-----|:--------|
| `.claude-plugin/marketplace.json` | Root manifest — must list all plugins |
| `<plugin>/.claude-plugin/plugin.json` | Per-plugin manifest for Claude Code |
| `README.md` | Fork-specific docs with plugin tables |
| `.cursor-plugin/marketplace.json` | Upstream's manifest (source of the short descriptions) |
| `<plugin>/.cursor-plugin/plugin.json` | Upstream's manifest (source of the long descriptions and authors) |
| `.claude/skills/sync-fork/excluded.txt` | Upstream plugins the fork deliberately does not ship |
| `.claude/skills/sync-fork/patched.txt` | Upstream files the fork deliberately modifies |
| `.claude/skills/sync-fork/scripts/sync-manifests.sh` | Regenerates every derivation below (`--write` to apply) |
| `.claude/skills/sync-fork/scripts/check-manifests.sh` | Verifies every derivation above |

## Why rebase + force push (not PRs)

This fork maintains a single commit on top of upstream. Rebase keeps that structure clean. PRs don't work well here because:

- GitHub PRs can't fast-forward merge — they'd create merge commits, breaking the single-commit structure
- A PR diff would show the entire upstream changeset as "changes", not just our manifest updates
- `git merge upstream/main` would accumulate merge commits over time

The verification step (step 6) serves as the review gate. If you want an extra safety net, do the rebase on a temporary branch first, inspect the diff, then fast-forward main to it.

## Common mistakes

- Letting an existing plugin's description drift when upstream rewrites it — invisible without the check script
- Keeping stale `.claude-plugin/plugin.json` files for plugins upstream removed
- Taking "our" README.md wholesale during conflicts instead of merging upstream's plugin changes
- Forgetting to update marketplace.json when plugins are added or removed
- Stamping a Cursor author onto a third-party plugin
- Treating an excluded or MCP-only plugin as a gap and generating a manifest for it during an "add the missing plugins" pass
- Flagging `schemas/`, `scripts/`, or `third_party/` itself as plugins missing a manifest
- Globbing only `*/` and silently skipping every plugin under `third_party/`
- Putting the path in a plugin's `name`, or the bare slug in its marketplace `source`
- Omitting `mcpServers` from an MCP plugin's manifest — it installs cleanly and does nothing
- Exploring upstream feature branches — only sync from `upstream/main`
