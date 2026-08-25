#!/usr/bin/env bash
# Verify the fork's .claude-plugin manifests against upstream's .cursor-plugin manifests.
# Run from the repo root. Exits non-zero if anything is out of sync.
set -u

CM=.claude-plugin/marketplace.json
UM=.cursor-plugin/marketplace.json
EX=.claude/skills/sync-fork/excluded.txt
PF=.claude/skills/sync-fork/patched.txt
fail=0

err() { printf '  FAIL: %s\n' "$1"; fail=1; }

for f in "$CM" "$UM" README.md "$EX" "$PF"; do
  [ -f "$f" ] || { echo "missing $f — run from the repo root"; exit 2; }
done

# A plugin directory is one containing .cursor-plugin/plugin.json, at the top
# level or one level under third_party/. Anything else (schemas/, scripts/) is not.
all_dirs=$(for d in */ third_party/*/; do [ -f "${d}.cursor-plugin/plugin.json" ] && echo "${d%/}"; done | sort)
excluded=$(awk -F'\t' '!/^#/ && NF {print $1}' "$EX" | sort)
# A plugin with no skills, agents, commands, or hooks is an MCP server config in
# a wrapper — out of scope, see SKILL.md "Scope".
authored() { for s in skills agents commands hooks; do [ -d "$1/$s" ] && return 0; done; return 1; }
mcp_only=$(for d in $all_dirs; do authored "$d" || echo "$d"; done | sort)
# Everything below derives the fork's own manifests, so it works from the shipped
# set — upstream's plugins minus the out-of-scope ones and the excluded ones.
out=$(cat <(echo "$excluded") <(echo "$mcp_only") | sort -u)
dirs=$(comm -23 <(echo "$all_dirs") <(echo "$out"))
upstream_src=$(jq -r '.plugins[].source' "$UM" | sort)
upstream=$(comm -23 <(jq -r '.plugins[].name' "$UM" | sort) <(echo "$out" | sed 's#.*/##' | sort))
fork=$(jq -r '.plugins[].name' "$CM" | sort)

echo "== plugin sets =="
[ "$all_dirs" = "$upstream_src" ] || err "plugin dirs != upstream marketplace sources:
$(diff <(echo "$all_dirs") <(echo "$upstream_src") | sed 's/^/    /')"
[ "$fork" = "$upstream" ] || err ".claude-plugin/marketplace.json != upstream marketplace minus $EX:
$(diff <(echo "$fork") <(echo "$upstream") | sed 's/^/    /')"

echo "== exclusions =="
# An exclusion for a plugin upstream has since deleted is dead weight that
# silently keeps subtracting a name nothing produces.
while IFS= read -r x; do
  [ -n "$x" ] || continue
  echo "$all_dirs" | grep -qxF "$x" || err "$x is listed in $EX but no longer exists upstream — drop the entry"
  [ -e "$x/.claude-plugin" ] && err "$x is excluded but still has a .claude-plugin/ manifest — remove it"
done <<EOF
$excluded
EOF

echo "== patched upstream files =="
# The fork's whole claim is that it only adds manifests, with these named
# exceptions. Verified in both directions: a patch silently reverted by a
# rebase, and an edit to an upstream file nobody declared.
if git rev-parse --verify -q upstream/main >/dev/null; then
  # Merge base, not upstream/main: between fetch and rebase every file upstream
  # just added would otherwise read as an undeclared local edit.
  base=$(git merge-base HEAD upstream/main)
  patched=$(awk -F'\t' '!/^#/ && NF {print $1}' "$PF" | sort)
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || { err "$f is listed in $PF but does not exist"; continue; }
    git diff --quiet "$base" -- "$f" && err "$f is listed in $PF but matches upstream — a rebase probably took upstream's copy, reverting the port"
  done <<EOF
$patched
EOF
  # Manifests are the fork's own additions; upstream has no copy to differ from.
  paths=(. ':(exclude).claude' ':(exclude)*.claude-plugin/*' ':(exclude)README.md' ':(exclude).gitignore')
  # Untracked too — git diff cannot see a file the fork added but never staged.
  changed=$({ git diff --name-only "$base" -- "${paths[@]}"
              git ls-files --others --exclude-standard -- "${paths[@]}"; } | sort -u)
  undeclared=$(comm -23 <(echo "$changed") <(echo "$patched"))
  [ -z "$undeclared" ] || err "upstream files modified but not declared in $PF:
$(echo "$undeclared" | sed 's/^/    /')"
else
  echo "  (skipped — no upstream/main ref)"
fi

echo "== per-plugin manifests =="
for p in $dirs; do
  slug=$(basename "$p")
  cj="$p/.claude-plugin/plugin.json"
  uj="$p/.cursor-plugin/plugin.json"
  [ -f "$cj" ] || { err "$p: missing $cj"; continue; }
  jq -e . "$cj" >/dev/null 2>&1 || { err "$p: $cj is not valid JSON"; continue; }

  [ "$(jq -r '.name' "$cj")" = "$slug" ] || err "$p: name field != directory basename"

  # Deriving author wholesale from a plugin with no upstream email writes
  # "email": null, which every other check here reads as equal to upstream.
  jq -e 'any(..; . == null)' "$cj" >/dev/null && err "$p: $cj has a null-valued key — omit the key instead"

  ud=$(jq -r '.description // ""' "$uj")
  cd_=$(jq -r '.description // ""' "$cj")
  [ "$ud" = "$cd_" ] || err "$p: description drifted from upstream
    upstream: $ud
    fork:     $cd_"

  ua=$(jq -Sc '.author // {}' "$uj")
  ca=$(jq -Sc '.author // {}' "$cj")
  [ "$ua" = "$ca" ] || err "$p: author drifted from upstream ($ua vs $ca)"

  # A declared version pins the plugin — installs stop updating until it changes,
  # and upstream rarely bumps it. See SKILL.md "Field derivation".
  [ "$(jq -r 'has("version")' "$cj")" = "false" ] || err "$p: manifest declares version — that pins installs against future syncs"

  # Claude Code does not auto-discover mcp.json — an MCP plugin needs the pointer
  # or it installs as a no-op.
  if [ -f "$p/mcp.json" ]; then
    [ "$(jq -r '.mcpServers // ""' "$cj")" = "./mcp.json" ] || err "$p: has mcp.json but manifest does not point mcpServers at it"
  fi
done

# A manifest whose upstream plugin was deleted drops out of $dirs entirely, so the
# loops above can never reach it. Sweep the filesystem instead.
for cj in */.claude-plugin/plugin.json third_party/*/.claude-plugin/plugin.json; do
  [ -f "$cj" ] || continue
  d=${cj%/.claude-plugin/plugin.json}
  echo "$excluded" | grep -qxF "$d" && continue   # already reported under "exclusions"
  echo "$mcp_only" | grep -qxF "$d" && { err "$d: MCP-only plugin with a manifest — out of scope, remove $cj"; continue; }
  case "
$dirs
" in
    *"
$d
"*) ;;
    *) err "$d: stale $cj — no .cursor-plugin/plugin.json (removed upstream?)" ;;
  esac
done

echo "== marketplace entries =="
for p in $dirs; do
  slug=$(basename "$p")
  e=$(jq -c --arg n "$slug" '.plugins[] | select(.name==$n)' "$CM")
  ud=$(jq -r --arg n "$slug" '.plugins[] | select(.name==$n) | .description // ""' "$UM")
  cd_=$(echo "$e" | jq -r '.description // ""')
  [ "$ud" = "$cd_" ] || err "$slug: marketplace description drifted from upstream
    upstream: $ud
    fork:     $cd_"
  [ "$(echo "$e" | jq -r '.source // ""')" = "./$p" ] || err "$slug: marketplace source must be \"./$p\" or the plugin cannot be installed"
  [ "$(echo "$e" | jq -r '.category // ""')" = "developer-tools" ] || err "$slug: marketplace category must be developer-tools"
  ua=$(jq -Sc '.author // {}' "$p/.cursor-plugin/plugin.json")
  [ "$(echo "$e" | jq -Sc '.author // {}')" = "$ua" ] || err "$slug: marketplace author != upstream plugin author"
done
jq -e '[.plugins[] | ..] | any(. == null)' "$CM" >/dev/null && err "$CM has a null-valued key — omit the key instead"

echo "== README fork sections =="
# Rebuilding README.md from upstream's copy drops every fork-only section at once,
# and none of them show up as a conflict.
while IFS= read -r h; do
  grep -qxF "## $h" README.md || err "README is missing the fork-only \"## $h\" section — re-apply it after taking upstream's README"
done <<'EOF'
Quick start
Not ported
What changed from upstream
Known gaps
Credits
Keeping up to date
EOF

echo "== README table =="
# Other tables ("Not ported", "Known gaps") also open rows with a backticked
# slug, and their cells may carry links too — so scope to the section rather
# than trying to tell the rows apart by shape.
plugin_table=$(awk '/^## Available plugins$/{s=1; next} s && /^## /{exit} s' README.md)
rows=$(printf '%s\n' "$plugin_table" | grep '^| `' | grep -F '](' | cut -d'`' -f2 | sort)
[ "$rows" = "$fork" ] || err "README plugin table != marketplace:
$(diff <(echo "$rows") <(echo "$fork") | sed 's/^/    /')"
trim() { printf '%s' "$1" | sed 's/^ *//; s/ *$//'; }

for p in $dirs; do
  slug=$(basename "$p")
  row=$(printf '%s\n' "$plugin_table" | grep -F "| \`$slug\` |" | head -1)
  [ -n "$row" ] || { err "$slug: no README table row"; continue; }

  oldifs=$IFS; IFS='|'; read -r -a cells <<<"$row"; IFS=$oldifs
  link=$(trim "${cells[2]-}")
  author=$(trim "${cells[3]-}")
  category=$(trim "${cells[4]-}")
  desc=$(trim "${cells[5]-}")

  dn=$(jq -r '.displayName // .name' "$p/.cursor-plugin/plugin.json")
  [ "$link" = "[$dn]($p/)" ] || err "$slug: README link must be \"[$dn]($p/)\", got \"$link\""

  ua=$(jq -r '.author.name // ""' "$p/.cursor-plugin/plugin.json")
  [ "$author" = "$ua" ] || err "$slug: README author must be \"$ua\", got \"$author\""

  [ "$category" = "Developer Tools" ] || err "$slug: README category must be \"Developer Tools\", got \"$category\""

  md=$(jq -r --arg n "$slug" '.plugins[] | select(.name==$n) | .description' "$CM")
  [ "$desc" = "$md" ] || err "$slug: README description does not match its marketplace description verbatim
    marketplace: $md
    README:      $desc"
done

echo "== README counts =="
# Counts written as prose go stale without conflicting with anything: "all 20
# third-party MCP plugins" survived the sync that made it 50.
count_claim() {   # <label> <expected> <sed extraction script>
  got=$(sed -nE "$3" README.md | head -1)
  [ -n "$got" ] || { err "README: no \"$1\" count found — did the sentence get reworded?"; return; }
  [ "$got" = "$2" ] || err "README says $got $1, actual count is $2"
}
count_claim "excluded plugins" "$(echo "$excluded" | grep -c .)" \
  's/^([0-9]+) upstream plugins are deliberately absent.*/\1/p'
count_claim "MCP-only plugins" "$(echo "$mcp_only" | grep -c .)" \
  's/^([0-9]+) further upstream plugins are only an MCP server config.*/\1/p'
# Anchored, and excluding the fork's own skills: prose *about* the flag is not a
# skill carrying it.
count_claim "skills with disable-model-invocation" "$(git grep -lE '^disable-model-invocation: true' -- '*/SKILL.md' ':(exclude).claude/*' | grep -c .)" \
  's/.* ([0-9]+) upstream skills ship .disable-model-invocation.*/\1/p'

np_rows=$(awk '/^## Not ported$/{s=1; next} s && /^## /{exit} s' README.md | grep -c '^| `')
[ "$np_rows" = "$(echo "$excluded" | grep -c .)" ] || err "README \"Not ported\" table has $np_rows rows but $EX lists $(echo "$excluded" | grep -c .) plugins"

if [ "$fail" -eq 0 ]; then
  echo
  echo "All manifests in sync ($(echo "$dirs" | wc -w | tr -d ' ') plugins)."
fi
exit "$fail"
