#!/usr/bin/env bash
# Instala skills, plugins (MCPs) e settings deste repo para o usuário atual. Idempotente.
# uso: curl -fsSL https://raw.githubusercontent.com/gstvpedroni/agents/main/install.sh | bash
#   ou: ./install.sh (a partir do clone)
set -euo pipefail

main() { # wrapper: com curl|bash, o bash lê o script inteiro antes de executar
  REPO_URL="${AGENTS_REPO_URL:-https://github.com/gstvpedroni/agents.git}"
  for c in git npx jq; do command -v "$c" >/dev/null || { echo "falta: $c" >&2; exit 1; }; done

  DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
  if [ ! -f "$DIR/claude/settings.json" ]; then # via curl: clona/atualiza
    DIR="${AGENTS_DIR:-$HOME/.local/share/agents}"
    if [ -d "$DIR/.git" ]; then git -C "$DIR" pull --ff-only; else git clone "$REPO_URL" "$DIR"; fi
  fi

  # Lock do npx skills vira symlink para o repo: add/remove/update -g já gravam aqui
  mkdir -p ~/.agents
  [ -e ~/.agents/.skill-lock.json ] && [ ! -L ~/.agents/.skill-lock.json ] && mv ~/.agents/.skill-lock.json ~/.agents/.skill-lock.json.bak
  ln -sfn "$DIR/skills-lock.json" ~/.agents/.skill-lock.json

  # Skills → ~/.agents/skills (canônico) + symlink em ~/.claude/skills
  # 2+ agentes = modo symlink (com 1 só, o npx skills copia e ignora ~/.agents); universal = ~/.agents/skills
  # Reinstala tudo sempre: após um `git pull` o lock já tem os hashes novos e o `npx skills update` acharia que está em dia
  skill() { npx -y skills add "$@" -g -a universal -a claude-code -y </dev/null; } # </dev/null: não consumir o stdin do while
  jq -r '.skills | to_entries | map(select(.value.sourceType != "local")) | group_by(.value.source)[]
    | "\(.[0].value.source) \(map(.key) | join(" "))"' "$DIR/skills-lock.json" |
    while read -r src names; do skill "$src" --skill $names; done # 1 clone por origem; $names sem aspas de propósito
  skill "$DIR" --skill '*' # skills próprias

  # Claude Code: marketplaces + plugins (trazem os MCPs) + settings
  command -v claude >/dev/null || return 0
  S="$DIR/claude/settings.json"
  jq -r '.extraKnownMarketplaces[].source | .repo // .url' "$S" | while read -r m; do claude plugin marketplace add "$m" </dev/null || true; done
  jq -r '.enabledPlugins | to_entries[] | select(.value) | .key' "$S" | while read -r p; do claude plugin install "$p" </dev/null || true; done
  jq -r '.enabledPlugins | to_entries[] | select(.value | not) | .key' "$S" | while read -r p; do claude plugin disable "$p" </dev/null || true; done
  [ -e ~/.claude/settings.json ] && [ ! -L ~/.claude/settings.json ] && mv ~/.claude/settings.json ~/.claude/settings.json.bak
  ln -sfn "$S" ~/.claude/settings.json # por último: `claude plugin` escreve no settings
}

main "$@"
