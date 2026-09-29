---
name: jira-code-review
description: >
  Automated code-review pipeline: Jira task or board link → GitLab MR diff → caveman-review
  findings → inline MR comments in Brazilian Portuguese → Jira comment notifying the assignee.
  Use whenever the user invokes /jira-code-review, pastes a Jira
  board/task link asking for review, or says things like "revisar MRs do board", "code review
  automático", "revisa a task ALD-21", "roda o review nas tasks em code review". Accepts a
  board/project link (reviews every task in the "Em Code Review" column) or a single task link.
---

Automated review pipeline. Think and work in English; every text posted to GitLab or Jira must be written in Brazilian Portuguese.

## Constants (ezlogicbr instance)

- Atlassian cloudId: `b14f239c-a983-4fae-890a-b31edf804e80` (site `ezlogicbr.atlassian.net`)
- MR link custom field: `customfield_10078` (named "Merge Request", holds the GitLab MR URL)
- Review column status: `"Em Code Review"`
- GitLab access: `glab` CLI, already authenticated on gitlab.com

If any of these fail (field missing, status not found), re-discover them via the Atlassian MCP (`getJiraIssue` with `fields: ["*all"], expand: "names"`) instead of giving up — the instance config may have changed.

## Mode detection

Look at the link the user passed:

- **Board / project link** (contains `/boards/`, `/jira/software/`, or is just a project reference): **full mode** — extract the project key and search `project = <KEY> AND status = "Em Code Review"` via `searchJiraIssuesUsingJql`. Review every result.
- **Task link** (`/browse/<KEY-N>`) or bare issue key like `ALD-21`: **single mode** — review just that issue.

If the user says "dry-run", run the whole pipeline but print the would-be comments instead of posting anything.

## Pipeline (per task)

1. **Fetch the issue** via `getJiraIssue` with fields `["summary", "description", "assignee", "status", "customfield_10078"]`. The description usually contains acceptance criteria and technical notes — read them; they are the review context (the reviewer should flag code that contradicts the stated acceptance criteria, not just generic bugs).
2. **No MR link?** Skip the task and record it for the final report. Do not comment on Jira for skipped tasks.
3. **Parse the MR URL** into project path and IID. Example: `https://gitlab.com/aldo_mais/aldomais/app-frontend/-/merge_requests/162` → project `aldo_mais/aldomais/app-frontend`, IID `162`.
4. **Duplicate guard**: run `scripts/check-reviewed.sh <project> <iid>`. It prints the current `head_sha` and whether a marker note for that sha already exists. If already reviewed at this sha, skip the MR (report it as "já revisado"). New commits since the marker → review again (new findings only; read existing bot notes first so you don't repeat yourself).
5. **Get the diff**: `glab mr diff <iid> -R <project>`. For large MRs also fetch changed-file list via `glab api "projects/<url-encoded>/merge_requests/<iid>/diffs" --paginate` to make sure nothing is truncated.
6. **Review**: apply the `caveman-review` skill to the diff (invoke it if not already loaded). Findings internally follow its severity scheme (🔴 bug / 🟡 risk / 🔵 nit / ❓ q). Use the Jira description as context. Skip pure-style nits unless there is nothing else — the goal is catching real problems, not flooding the author.
   - **Architecture & clean code pass**: besides bugs, check the changed code against `references/clean-architecture.md` (layer rules calibrated to these repos + clean-code checklist). Only flag code the MR actually touches — a pre-existing violation in an untouched block is out of scope, but if the MR adds or modifies code that breaks the patterns, point it out. Default severity 🔵 `[sugestão]`; escalate to 🟡 `[risco]` when the violation causes concrete harm (see the reference for the escalation criteria).
   - **Migrations**: see "Reviewing migrations" below — the rules there are different from the rest of the diff.
7. **Post inline comments** — one per finding, in pt-BR, using `scripts/post-inline-comment.sh <project> <iid> <file> <line> <body-file>`. Write each body to a temp file first (scratchpad). The script posts an inline discussion on the diff line and automatically falls back to a general MR note (prefixed with the file:line) when GitLab rejects the position.
8. **Post the marker note** on the MR: a short summary in pt-BR listing the findings count, ending with the machine-readable marker line (see below).
9. **Comment on Jira** via `addCommentToJiraIssue`, mentioning the assignee.

## Reviewing migrations

Files under `migrations/` in these repos are produced by `typeorm migration:generate`. The SQL inside them is the generator's output, not a decision the author made — so reviewing *how* the migration works produces findings nobody can act on without hand-editing generated code and diverging from the tool.

**Do not flag** the generated DDL: `DROP COLUMN` + `ADD COLUMN` instead of `ALTER COLUMN ... TYPE`, missing `USING` clauses, the `down()` strategy, resulting data loss, locking/downtime characteristics, column ordering, or the generated class name and timestamp. All of these are TypeORM's shape.

**Do check** that the migration and the models agree, because *that* is the human step and it breaks deploys when it's wrong. Walk the model changes in the diff (`src/infra/models/**`) against the migration statements:

- Every `@Column` the MR changes has a matching statement in the migration, with the same value — model `length: 255` ↔ migration `character varying(255)`, a new field ↔ an `ADD` for its column, a removed field ↔ a `DROP`.
- A model change with **no migration at all** is a 🔴 `[bug]`: the entity and the database disagree the moment it deploys, which is usually the exact failure the task is trying to fix.
- A value mismatch between model and migration is a 🔴 `[bug]` for the same reason.
- A migration statement that **no model change accounts for** is a 🟡 `[risco]` — it normally means the migration was generated against a stale schema and is carrying someone else's pending change.

If a migration contains hand-written logic beyond the generated DDL — a data backfill, an `UPDATE`, a conditional — that part *was* authored, so review it normally.

## Comment format (MR, pt-BR)

Each inline comment:

````
**[severidade] Problema:** <o que quebra e por quê — 1-2 frases diretas>

**Solução:**

```<lang>
<trecho de código corrigido>
```
````

Severity translation for the pt-BR text: 🔴 → `**[bug]**`, 🟡 → `**[risco]**`, 🔵 → `**[sugestão]**`, ❓ → `**[dúvida]**`. Keep code identifiers, error strings, and API names verbatim (never translate them).

Marker/summary note (last comment on the MR):

```
🤖 **Code review automático concluído** — <N> apontamento(s): <n_bug> bug(s), <n_risco> risco(s), <n_sugestao> sugestão(ões).

<!-- code-review-auto head_sha=<head_sha> -->
```

The HTML comment line is what `check-reviewed.sh` greps for — always include it exactly in that format.

## Jira comment (pt-BR)

Post via `addCommentToJiraIssue` with `contentFormat: "adf"` — the markdown format escapes `[~accountId:...]` into literal text, so build the mention as an ADF node: `{"type":"mention","attrs":{"id":"<assignee accountId>"}}` in the first paragraph, followed by text nodes (link to the MR as a text node with a `link` mark). Fall back to the display name in plain text if the mention fails. Content template (rendered):

```
[~accountId:XXXX] Code review automático concluído na MR <link da MR>.

Foram feitos <N> apontamentos (<resumo curto: ex. "2 bugs, 1 risco">). Os comentários estão na própria MR, cada um com o problema e a sugestão de correção.
```

If the review found nothing, still post both the marker note and the Jira comment saying no issues were found ("Nenhum problema encontrado").

## Final report (to the user)

After all tasks, print a short table: task key, MR, findings count, status (revisado / já revisado / sem MR / erro). Full mode processes tasks sequentially — partial failure on one task must not abort the rest.

## Boundaries

- Never approve, merge, close, or transition anything — comments only.
- Never push code or edit the MR branch.
- Jira: only `addCommentToJiraIssue`; do not edit fields or transition issues.
- Destructive/irreversible actions are out of scope; if something requires one, stop and tell the user.
