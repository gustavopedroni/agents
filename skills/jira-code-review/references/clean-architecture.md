# Clean architecture & clean code — review reference (aldo_mais repos)

Rules calibrated to the actual structure of these repos, not textbook Clean Architecture. Flag deviations **only in code the MR touches**. Write findings in the same comment format as everything else (Problema + Solução with corrected code).

## Severity

- Default: 🔵 `[sugestão]`.
- Escalate to 🟡 `[risco]` when the violation causes concrete harm, e.g.:
  - Business rule implemented in a controller/screen → will be duplicated or bypassed by the next caller (queue handler, another endpoint).
  - Layer skip that bypasses validation, auth, or mapping that the proper layer performs.
  - A god-function/duplication that is actively hiding a bug or making the diff's own fix incomplete.
- Never escalate for aesthetics alone (naming, function length) — those stay 🔵.

## Backend layers (app-backend, backoffice-backend — Express + TypeORM)

Structure: `src/adapters/` → `src/application/` → `src/infra/`.

| Layer | Responsibility | Flag when the MR adds… |
|---|---|---|
| `adapters/controllers`, `adapters/queue` | Parse/validate input (class-validator schema), call one usecase, shape response | business rules, direct repository/ORM/query access, direct AWS/HTTP integration calls |
| `application/usecases` | Business rules; orchestrate repositories and services | Express types (`req`/`res`), SQL/query-builder construction, HTTP status decisions that belong to the controller |
| `application/services` | External integrations (AWS, other APIs) | business rules that belong in a usecase |
| `infra/repositories` | Data access (TypeORM), one query concern per method | business decisions (status transitions, permission logic), calls to services/usecases |
| `infra/utils` | Pure helpers | anything stateful or layer-aware |

Concretely observed conventions to preserve:
- Controllers validate with a schema class and delegate: `validateSchema(...)` → `someUsecase(params)`. A controller that inlines logic beyond that is a finding.
- Usecases import repositories directly (that is accepted here — do **not** demand interfaces/DI the codebase doesn't use).
- Queue handlers (`adapters/queue/controllers/*.route.ts`) follow the same rule as HTTP controllers: parse message → usecase. Heavy logic inline in the handler is a finding.

## Frontend layers

**backoffice-frontend** (React + antd + react-query): `infra/services/backend/requests` (axios calls only) → `hooks/queries|mutations` (react-query wrappers) → `pages`/`components`.
- Components/pages calling `api`/axios directly instead of going through a hook → finding.
- Request functions containing UI logic (notifications, navigation) → finding; side effects belong in the mutation hook's `onSuccess`/`onError`.
- API types live in `infra/services/backend/interfaces` — inline duplicated response types in a component → finding.

**app-frontend** (React Native + zustand): `services/requests` (API) → `stores` (business state/flows) → `screens`/`components` (thin).
- Screens implementing multi-step business flows inline instead of in the store/hook → finding.
- Stores importing navigation/UI concerns beyond the existing helpers → finding.

## Clean code checklist (applies to every layer)

Flag only when the MR introduces or modifies the offending code:

- **Intent-revealing names** — `data2`, `aux`, `handleThing` for non-handlers. Suggest the precise name.
- **One responsibility per function** — a function that validates + transforms + persists + notifies: suggest the extraction, name the pieces.
- **Magic numbers/strings** — inline `300`, `'PENDING'`, URLs: suggest a named constant or existing enum (these repos already use enums — point to the right one).
- **Early return over nesting** — 3+ levels of `if` nesting: show the guard-clause version.
- **Swallowed errors** — empty `catch`, `catch` that only logs when the caller needs the failure: suggest rethrow or explicit handling.
- **Duplication introduced by the diff** — the MR copy-pastes a block that already exists (or creates two near-identical branches): suggest the shared helper.
- **Dead code** — commented-out code or unused exports added by the MR.

## What NOT to flag

- Pre-existing violations in lines the MR didn't touch (mention at most once, briefly, if the MR builds on top of them).
- The generated SQL inside `migrations/` — see "Reviewing migrations" in SKILL.md; only model↔migration consistency is in scope there.
- Patterns the codebase consistently uses, even if textbook-impure (direct repository imports in usecases, module-level singletons like `AWSServiceInstance`).
- Formatting the linter already governs.
