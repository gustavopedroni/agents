# agents

Backup das minhas configs de agentes de IA (hoje: Claude Code).

## Instalar tudo

```sh
curl -fsSL https://raw.githubusercontent.com/gstvpedroni/agents/main/install.sh | bash
```

Clona o repo em `~/.local/share/agents` (mude com `AGENTS_DIR=...`) e instala:

- **Skills** via [`npx skills`](https://skills.sh): cópia em `~/.agents/skills`, symlink em `~/.claude/skills`.
  - Terceiros, registrados em [`skills-lock.json`](skills-lock.json) (o lock do `npx skills`; `~/.agents/.skill-lock.json` vira symlink para ele).
  - Próprias, em [`skills/`](skills).
- **Plugins do Claude Code** (MCPs e o que só funciona no Claude: agents, comandos, hooks), com marketplaces, de [`claude/settings.json`](claude/settings.json).
  - Plugins com `false` em `enabledPlugins` são desabilitados.
- **`~/.claude/settings.json`**: vira symlink para o repo. O arquivo anterior vai para `settings.json.bak`.

Requer `git`, `npx` (Node) e `jq`. O `claude` é opcional; sem ele, só as skills são instaladas.

Só as skills próprias:

```sh
npx skills add gstvpedroni/agents -g -a universal -a claude-code
```

## Adicionar uma skill nova

```sh
npx skills add <owner/repo> --skill <nome> -g -a universal -a claude-code   # ou crie em ~/.claude/skills/<nome>
./sync.sh                                                        # copia skills próprias para skills/ e atualiza marketplaces
git add -A && git commit -m "skill: <nome>"
```

Skills de terceiros entram sozinhas no `skills-lock.json`, e mudanças de plugins/settings feitas no Claude caem em `claude/settings.json` (ambos são symlinks); é só commitar.

## Atualizar skills

A action [`update-skills`](.github/workflows/update-skills.yml) roda todo dia e abre um PR quando alguma skill de terceiros muda na origem (o `skillFolderHash` no lock). Depois do merge:

```sh
git pull && ./install.sh
```

Use o `install.sh` e não o `npx skills update`: depois do pull o lock já tem os hashes novos, e o `update` acharia que está tudo em dia.

> A action precisa de *Settings → Actions → General → Allow GitHub Actions to create and approve pull requests*.
