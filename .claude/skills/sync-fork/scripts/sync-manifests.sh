#!/usr/bin/env bash
# Derive every fork artifact from upstream's .cursor-plugin files: per-plugin
# manifests, the root marketplace's .plugins array, and the README plugin table.
# Run from the repo root. Default is a dry run; --write applies the changes.
#
# The derivation rules are the ones in SKILL.md "Field derivation", and
# check-manifests.sh asserts the result — so a clean run here should leave that
# script with nothing to report.
set -eu

write=0
case "${1-}" in
  --write) write=1 ;;
  "") ;;
  *) echo "usage: $0 [--write]"; exit 2 ;;
esac

CM=.claude-plugin/marketplace.json
UM=.cursor-plugin/marketplace.json
EX=.claude/skills/sync-fork/excluded.txt

for f in "$CM" "$UM" README.md "$EX"; do
  [ -f "$f" ] || { echo "missing $f — run from the repo root"; exit 2; }
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
changed=0

report() {   # <generated> <target>
  if cmp -s "$1" "$2" 2>/dev/null; then return; fi
  changed=$((changed + 1))
  if [ "$write" -eq 1 ]; then
    mkdir -p "$(dirname "$2")"
    cp "$1" "$2"
    echo "  wrote $2"
  else
    echo "  would change $2"
    diff -u "$2" "$1" 2>/dev/null | sed -n '3,$p' | sed 's/^/      /' || true
  fi
}

# The shipped set in upstream's marketplace order, which is the order the root
# manifest carries. `.name` is the bare slug; `.source` carries the path.
excluded=$(awk -F'\t' '!/^#/ && NF {print $1}' "$EX" | sed 's#.*/##' | tr '\n' ' ')
# A plugin with no skills, agents, commands, or hooks is an MCP server config in
# a wrapper — out of scope, see SKILL.md "Scope".
authored() { for s in skills agents commands hooks; do [ -d "$1/$s" ] && return 0; done; return 1; }
jq -r '.plugins[] | "\(.name)\t\(.source)"' "$UM" | while IFS="$(printf '\t')" read -r name src; do
  case " $excluded " in *" $name "*) continue ;; esac
  p=${src#./}
  authored "$p" || continue
  printf '%s\t%s\n' "$name" "$p"
done > "$tmp/shipped.tsv"

# author verbatim from upstream, but built from the keys upstream actually has:
# reaching for a missing .email writes "email": null, which reads as a match.
AUTHOR='(.author | {name} + (if (.email // null) != null then {email: .email} else {} end))'

echo "== per-plugin manifests =="
while IFS="$(printf '\t')" read -r name p; do
  up="$p/.cursor-plugin/plugin.json"
  if [ -f "$p/mcp.json" ]; then
    jq --arg n "$name" "{name: \$n, description, author: $AUTHOR, mcpServers: \"./mcp.json\"}" "$up" > "$tmp/plugin.json"
  else
    jq --arg n "$name" "{name: \$n, description, author: $AUTHOR}" "$up" > "$tmp/plugin.json"
  fi
  report "$tmp/plugin.json" "$p/.claude-plugin/plugin.json"
done < "$tmp/shipped.tsv"

echo "== root marketplace =="
# Only .plugins is derived. name, description, owner, and renames are the fork's
# own and must survive untouched.
: > "$tmp/entries.jsonl"
while IFS="$(printf '\t')" read -r name p; do
  desc=$(jq -r --arg n "$name" '.plugins[] | select(.name == $n) | .description' "$UM")
  jq -c --arg n "$name" --arg s "./$p" --arg d "$desc" \
    "{name: \$n, description: \$d, source: \$s, category: \"developer-tools\", author: $AUTHOR}" \
    "$p/.cursor-plugin/plugin.json" >> "$tmp/entries.jsonl"
done < "$tmp/shipped.tsv"
jq -s '.' "$tmp/entries.jsonl" > "$tmp/entries.json"
jq --slurpfile e "$tmp/entries.json" '.plugins = $e[0]' "$CM" > "$tmp/marketplace.json"
report "$tmp/marketplace.json" "$CM"

echo "== README table =="
while IFS="$(printf '\t')" read -r name p; do
  dn=$(jq -r '.displayName // .name' "$p/.cursor-plugin/plugin.json")
  au=$(jq -r '.author.name // ""' "$p/.cursor-plugin/plugin.json")
  desc=$(jq -r --arg n "$name" '.plugins[] | select(.name == $n) | .description' "$UM")
  printf '%s\t| `%s` | [%s](%s/) | %s | Developer Tools | %s |\n' "$name" "$name" "$dn" "$p" "$au" "$desc"
done < "$tmp/shipped.tsv" > "$tmp/rows.tsv"

# Rows are replaced in place and new ones appended, because row order is
# cosmetic and re-sorting the table produces a diff nobody can review.
# A plugin row is a backticked slug plus a link — that also excludes the
# table's own `name` header.
awk -F'\t' '
  NR == FNR { row[$1] = $2; if (!($1 in ord)) { ord[$1] = ++n; seq[n] = $1 }; next }
  function flush() {
    for (i = 1; i <= n; i++) if (!(seq[i] in seen)) { print row[seq[i]]; seen[seq[i]] = 1 }
  }
  /^## Available plugins$/ { insec = 1; print; next }
  insec && /^## / { flush(); insec = 0; print; next }
  insec && /^\| `/ && index($0, "](") {
    slug = $0; sub(/^\| `/, "", slug); sub(/`.*/, "", slug)
    if (slug in row) { print row[slug]; seen[slug] = 1 }
    next
  }
  insec && intable && !/^\|/ { flush(); intable = 0; print; next }
  { if (insec && /^\|/) intable = 1; print }
  END { if (insec) flush() }
' "$tmp/rows.tsv" README.md > "$tmp/README.md"
report "$tmp/README.md" README.md

echo
if [ "$changed" -eq 0 ]; then
  echo "Everything already derived ($(wc -l < "$tmp/shipped.tsv" | tr -d ' ') plugins)."
elif [ "$write" -eq 1 ]; then
  echo "$changed file(s) written. Run check-manifests.sh, then update the fork's prose counts if the plugin set changed."
else
  echo "$changed file(s) would change. Re-run with --write."
fi
