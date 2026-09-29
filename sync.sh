#!/usr/bin/env bash
# Traz para o repo o que foi instalado à mão nesta máquina. Depois: git diff && commit.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
LOCK="$REPO/skills-lock.json" # terceiros já caem aqui direto (symlink de ~/.agents/.skill-lock.json)

# Próprias: skill instalada (com SKILL.md) sem origem remota no lock → copia para skills/
# ponytail: skills removidas da máquina não somem de skills/, `git rm` manual
for d in ~/.agents/skills/*/ ~/.claude/skills/*/; do
  n=$(basename "$d")
  [ -f "$d/SKILL.md" ] || continue
  jq -e --arg n "$n" '.skills[$n] | select(. != null and .sourceType != "local")' "$LOCK" >/dev/null && continue
  rm -rf "${REPO:?}/skills/$n" && cp -a "$(realpath "$d")" "$REPO/skills/$n"
done

# Marketplaces adicionados com `claude plugin marketplace add`
S="$REPO/claude/settings.json"
jq --slurpfile k ~/.claude/plugins/known_marketplaces.json '.extraKnownMarketplaces = ($k[0] | map_values({source}))' "$S" >"$S.tmp" && mv "$S.tmp" "$S"

git -C "$REPO" status --short
