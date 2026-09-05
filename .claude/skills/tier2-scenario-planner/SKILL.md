---
name: tier2-scenario-planner
description: >
  Generate the tier-2 scenario matrix for this Cratis project (CONSTITUTION.md's tier 2: "scenario
  matrix against a booted app + Postgres [sic — actually MongoDB, see below], event-store queries as
  witnesses, React snapshots for UI checks"). Adapts autoqa-agent's (terryso/AutoQA-Agent) two-phase
  discovery → plan pattern from Playwright DOM crawling to Cratis's own domain model. Use when: (1)
  building or refreshing the tier-2 scenario matrix for a Cratis Arc app, (2) the user asks to
  "discover slices" / "plan tier 2" / "generate scenario matrix", (3) new slices have been added since
  the last domain-graph.json and the matrix is stale.
---

# Tier 2 Scenario Planner — Cratis Domain Discovery + Plan

Two phases, run in order, output-compatible with each other exactly the way autoqa-agent's
`plan-explore` → `plan-generate` are (`generateTestPlan()` reads `explore-graph.json` written by the
explore phase — see `src/plan/orchestrator.ts` in that project). Same shape here: Phase 2 reads Phase
1's `domain-graph.json`.

**Why this isn't just "run autoqa on the frontend":** autoqa's discovery is a Playwright agent
clicking through rendered pages — it can only see what the DOM exposes, and its evidence that
something worked is a UI snapshot proving something *rendered*. In a Cratis app the ground truth of
"did this actually happen" lives one layer down, in Chronicle's event log — a command can succeed at
the UI (form submits, page navigates) while the underlying event never got appended, or got appended
with the wrong values, and a DOM-only test would still pass. So discovery here reads the domain model
directly (the `.cs` slice files) rather than crawling a browser, and every generated case's real
assertion is an **event-store query** ("witness"), with a React snapshot only for the parts of the
matrix that are actually UI-observable behavior (layout, disabled states, error messages) rather than
correctness of the underlying state change.

> **Read first:** [../_shared/cratis-conventions.md](../_shared/cratis-conventions.md) for the
> `[Command]`/`[EventType]`/`[ReadModel]`/`IReactor` shapes this skill parses, and
> [`CONSTITUTION.md`](../../../CONSTITUTION.md) for why tier-4 diffs (approval-gate `Handle()` bodies,
> event schema changes) need human sign-off regardless of what this matrix says.

## Correction this skill depends on (verify before trusting old notes)

The project's `docker-compose.yml` runs `cratis/chronicle:latest-development` exposing port `27017`
(MongoDB's default port), and `CratisApp.csproj` references `Cratis.Arc.MongoDB`. **This project's
event store is MongoDB, not Postgres** — Chronicle is storage-agnostic in general (Mongo/Postgres/SQL
Server/SQLite), but this project picked Mongo. Witness queries below are written against Mongo. If a
later change swaps the backing store, update `references/witness-and-snapshot-patterns.md` before
trusting any witness query it documents.

## Phase 1 — Discovery (replaces autoqa's Playwright crawl)

Walk every `<Module>/<Feature>/<Slice>/*.cs` file (module → feature → slice hierarchy — discover the
actual root folder from an existing slice, don't hard-code `SomeModule`). For each slice file, extract
the same four things autoqa's `ElementSummary`/`FormInfo`/`PageNode` extract from a DOM, translated to
domain terms:

| autoqa (DOM) | this skill (domain model) | Extracted from |
|---|---|---|
| `PageNode` | `SliceNode` | The slice folder + its one `.cs` file |
| `FormInfo` (fields + submit button) | `CommandNode` | `[Command] record X(...) { Handle() }` — record's positional params are the fields, `Handle()`'s return type(s) are what it "submits" to |
| (implicit — a successful submit) | `EventNode` | `[EventType] record X(...)` — every event a command's `Handle()` can return, including each arm of an `IEnumerable<object>`/`Result<,>` return |
| `links` | `ReadModelNode` | `[ReadModel] record X(...)` + its `public static` query methods |
| `NavigationEdge` (click → new page) | `ReactorEdge` | Any `IReactor` implementation: `Handle(TEvent, EventContext)` methods become an edge `{from: <TEvent id>, to: <command it calls via ICommandPipeline>, trigger: <method name>}` |
| (n/a) | `UiNode` | A `.tsx` file co-located in the same slice folder (Cratis convention: proxy + component sit beside the `.cs` file) |

Write `domain-graph.json` (mirrors autoqa's `ExplorationGraph{pages,edges}` — see
[references/domain-graph-schema.md](references/domain-graph-schema.md) for the exact shape) to
`.build-kit/tier2/runs/<runId>/discovery/domain-graph.json`.

**Guardrails** (same purpose as autoqa's `GuardrailConfig` — this is a static/mechanical pass, not an
agent loop, so the equivalent risk is scope creep, not runaway API spend): scope to slice folders only
(skip `.build-kit/`, `.claude/`, `bin/`, `obj/`, generated `// @generated` proxy files, and
`CratisApp.Specs/`). If a `.cs` file doesn't parse cleanly against the conventions doc's shapes (e.g. a
`[Command]` with a handler method instead of `Handle()` on the record), record it under `graph.warnings`
rather than guessing its structure.

## Phase 2 — Plan generation (replaces autoqa's plan-agent)

Read `domain-graph.json`. For each `CommandNode`, generate one or more `TestCasePlan`-shaped cases
(field names match autoqa's `TestCasePlan` in `src/plan/types.ts` exactly, so tooling that already
understands autoqa's plan shape needs no translation layer):

| `type` | When to generate it | Verification |
|---|---|---|
| `functional` | Always, one per command — the happy path | Witness only |
| `form` | The command has a `CommandValidator<T>` in the same file | Witness (assert the invalid submission produced **no** new event for that `EventSourceId`) |
| `boundary` | A field is numeric/amount-typed, or the constitution's approval-gate invariants apply (`AutoApprovalThreshold`, etc.) | Witness at threshold, threshold−1, threshold+1 |
| `functional` (reactor) | For each `ReactorEdge` | Witness: the *reacted* command's event was appended, not just the triggering one |
| — | A `UiNode` exists for the slice | Add a React-snapshot step to whichever case above is the happy path for that slice |

Each case becomes a Markdown spec in the same **Preconditions / Steps** shape autoqa writes (see a real
example this pattern is copied from: `specs/saucedemo-01-login.md` in terryso/AutoQA-Agent — steps are
plain numbered English sentences, not code). The last 1–2 steps are always the verification steps,
written explicitly as "Witness:" / "React snapshot:" so step 4's execution harness (not yet built) has
an unambiguous instruction to turn into a real Mongo query / snapshot assertion. See
[references/witness-and-snapshot-patterns.md](references/witness-and-snapshot-patterns.md) for the
exact query/assertion shapes to write into those steps.

Write:
- `.build-kit/tier2/runs/<runId>/plan/plan.json` — `{runId, generatedAt, cases: TestCasePlan[]}`.
- `.build-kit/tier2/runs/<runId>/plan/specs/<case-id>.md` — one file per case.

## What this skill does not do

Execute anything — that's step 4 (the execution harness: boot the app + MongoDB, run the matrix,
produce report + evidence). This skill only produces the plan the harness will later run against. Do
not boot Docker, run `dotnet run`, or start Chronicle from inside this skill.

## References
- [references/domain-graph-schema.md](references/domain-graph-schema.md) — full JSON shape for
  `domain-graph.json`, with the real autoqa `ExplorationGraph` type it's adapted from alongside each
  field for traceability.
- [references/witness-and-snapshot-patterns.md](references/witness-and-snapshot-patterns.md) — how to
  write a witness query against this project's Mongo-backed Chronicle, and what a React snapshot step
  should specify.
- [../_shared/cratis-conventions.md](../_shared/cratis-conventions.md) — the Cratis shapes this skill
  parses.
- `spike-log.md` (repo root) — this skill is step 3 of the Orca/APE/autoqa harness-eval spike; log any
  finding here that changes the view of whether this discovery approach actually scales past a handful
  of slices.
