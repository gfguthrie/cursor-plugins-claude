#!/usr/bin/env bash
# Pre-rebase triage: what upstream/main brings that needs a human decision.
# Run from the repo root after `git fetch upstream`, before rebasing. Reads
# upstream/main through git, so the working tree can still be on the old base.
# An optional <base> argument replaces the merge base, to replay a past sync.
#
# 1. In-scope upstream plugins the fork neither ships nor excludes — each is a
#    ship / patch / exclude decision (SKILL.md "Excluded plugins").
# 2. Cursor-isms in files upstream changed since the merge base — each is a
#    re-apply (file in patched.txt) or a new patch-or-exclude decision.
set -eu

EX=.claude/skills/sync-fork/excluded.txt
PF=.claude/skills/sync-fork/patched.txt
U=upstream/main

git rev-parse --verify -q "$U" >/dev/null || { echo "no $U ref — git fetch upstream first"; exit 2; }
for f in "$EX" "$PF"; do [ -f "$f" ] || { echo "missing $f — run from the repo root"; exit 2; }; done

base=${1:-$(git merge-base HEAD "$U")}
excluded=$(awk -F'\t' '!/^#/ && NF {print $1}' "$EX")
patched=$(awk -F'\t' '!/^#/ && NF {print $1}' "$PF")

echo "== undecided in-scope plugins =="
undecided=0
for p in $(git show "$U:.cursor-plugin/marketplace.json" | jq -r '.plugins[].source' | sed 's#^\./##'); do
  content=$(git ls-tree --name-only "$U" "$p/" | sed 's#.*/##' | grep -xE 'skills|agents|commands|hooks' | paste -sd, - || true)
  [ -n "$content" ] || continue
  printf '%s\n' "$excluded" | grep -qxF "$p" && continue
  git cat-file -e "HEAD:$p/.claude-plugin/plugin.json" 2>/dev/null && continue
  echo "  $p ($content)"
  undecided=$((undecided + 1))
done
[ "$undecided" -gt 0 ] || echo "  (none)"

echo "== Cursor-isms in incoming changes =="
# Each alternative is a known incompatibility — see SKILL.md step 1.
pattern='generalPurpose|subagent_type: *.?(shell|explore)|model: *.?fast|^readonly:|^is_background:|~/\.cursor|agent-transcripts|AskQuestion|environment: *.?cloud|cloud_base_branch'
hits=$(git diff --name-only "$base" "$U" | xargs -r git grep -nE "$pattern" "$U" -- 2>/dev/null | sed "s#^$U:##" || true)
if [ -z "$hits" ]; then
  echo "  (none)"
else
  printf '%s\n' "$hits" | while IFS= read -r h; do
    f=${h%%:*}
    case "$f" in third_party/*) p=$(printf '%s' "$f" | cut -d/ -f1-2) ;; *) p=${f%%/*} ;; esac
    printf '%s\n' "$excluded" | grep -qxF "$p" && continue
    git ls-tree --name-only "$U" "$p/" | sed 's#.*/##' | grep -qxE 'skills|agents|commands|hooks' || continue
    if printf '%s\n' "$patched" | grep -qxF "$f"; then tag=patched; else tag=unpatched; fi
    printf '  [%s] %s\n' "$tag" "$(printf '%s' "$h" | cut -c1-200)"
  done
fi
