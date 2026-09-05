# ExpenseTracker Constitution — Tier 0–4 Gate Rules

Spike deliverable, step 1 of the Orca/APE/autoqa harness-eval plan (see
`spike-log.md` for the running log). This is the machine-checkable rule set
that decides which diffs may pass automatically and which require a human.

## Why content-pattern rules, not path-pattern rules

Cratis's non-negotiable convention (`.claude/skills/_shared/cratis-conventions.md`)
puts **one `.cs` file per vertical slice** — the `[Command]` record, its
`Handle()` body, the `[EventType]` record(s) it raises, and the read model it
feeds all live in the same file, e.g. a future
`Expenses/Approval/ApproveExpense/ApproveExpense.cs`. There is no
`Commands/`, `Handlers/`, or `Events/` folder to gate on. **A tier-4 rule
keyed on file path will either miss real approval-gate edits or block the
entire domain wholesale.** Every rule below matches on diff *content*
(added/changed lines, via `git diff -U0`), scoped to `**/*.cs` and
`**/*.tsx` under module/feature folders (i.e. excluding `**/*.g.cs`,
`// @generated` proxies, and anything under `.build-kit/`, `.claude/`,
`node_modules/`).

## Tiers

- **Tier 0** — static analysis (APE scan, see below). Runs on every diff, no gate.
- **Tier 1** — build + xUnit/Cratis.Specifications, warnings-as-errors. Runs on every diff, no gate.
- **Tier 2** — scenario matrix against a booted app + MongoDB (Chronicle's actual backing store here, not Postgres — see step-3 correction below) (event-store queries as witnesses, React snapshots for UI). Auto-passes if green.
- **Tier 3** — adversarial pass targeting the approval gate (threshold bypass, negative amounts, concurrent-approval race). Failure blocks merge; does not by itself require a human if the fix is mechanical.
- **Tier 4** — **human sign-off required**, regardless of whether tiers 0–3 pass. A diff matching any rule below is tier 4 even with a fully green pipeline.

## Tier-4 trigger rules

| ID | Pattern | Matches | Rationale |
|---|---|---|---|
| T4-01 | `` `[EventType]` `` added, removed, or its record's property list changed | New event, renamed/removed/retyped event property | Events are immutable facts once shipped (value 3 in Cratis conventions) — a schema change here is either additive-safe or a breaking replay change, and only a human can tell which. |
| T4-02 | A `[Command]` record's `Handle()` body changed where the record name matches `Approve*\|Reject*\|Submit*Expense` | Any edit inside `ApproveExpense`, `RejectExpense`, `SubmitExpense` `Handle()` | These three commands *are* the approval gate — see invariants below. |
| T4-03 | Any diff line matching `RequireApprovalGate\|AutoApprovalThreshold` (in `.cs` or `appsettings*.json`) | Config or code touching the gate switch/threshold | The threshold and the gate on/off switch are the two knobs that turn the approval workflow off for real money. |
| T4-04 | Any diff line matching `ApprovedBy\s*==?\s*"system"` or `ApprovedBy\s*=\s*"system"` | The auto-approval reactor's system-tag write path | This is the one place automation is allowed to approve its own spend — any change to *how* it tags itself needs a human, since it's the line between "audited automation" and "silent auto-approval." |
| T4-05 | A `CommandValidator<T>` subclass changed for `ApproveExpense`, `RejectExpense`, or `SubmitExpense` | Validator rule added/removed/loosened | Validators are the guard-clause layer in front of `Handle()`; loosening one is functionally identical to loosening the gate itself. |
| T4-06 | New or changed `[Authorize]`, `[AllowAnonymous]`, or any middleware/`Program.cs` diff touching auth registration | Auth boundary changes | Explicit per the original spike brief; not approval-gate-specific but same blast radius. |
| T4-07 | A reactor (`*Reactor.cs`) changed such that it now issues a raw event (`new ExpenseApproved(...)`) instead of a command (`ApproveExpense(...)`) | Reactor bypassing the command layer | Violates the locked design decision (Expense Tracker note, "the auto-approval reactor never writes `ExpenseApproved` directly") — this exact regression is the single most likely way a Gemini-authored change would silently reintroduce a double-approval bug. |
| T4-08 | Diff touches `.mcp.json`, any `.claude/skills/**`, or `.build-kit/**` | Agent tooling/instruction changes | Out of APE's discovery scope entirely (see Tier-0 gap below) but exactly the surface a prompt-injection or scope-escalation would land on — must not be nodded through by a green tier 0–3 run that never looked at it. |

Everything else — read-model projections, UI components, non-approval
commands, test files — stays tier 0–3 only.

## Approval-gate invariants (explicit, not inferred)

From the locked design in the vault (`Active_Projects/Expense Tracker/Expense Tracker.md`):

- **Threshold value**: `ExpensePolicy:AutoApprovalThreshold`, static `appsettings.json`, currently `100.00` (EUR). Not event-sourced (deliberate scope cut).
- **Gate-skip config**: `ExpensePolicy:RequireApprovalGate` (`bool`). `false` = every submission auto-approves regardless of amount (sole-trader mode). `true` = only submissions under threshold auto-approve.
- **Who can approve**:
  - A human, via the `ApproveExpense` command with `ApprovedBy` set to a person identifier.
  - The system, via `AutoApprovalReactor` issuing the *same* `ApproveExpense` command with `ApprovedBy = "system"` — never by writing `ExpenseApproved` directly (T4-07).
  - Both paths share one guard: expense must be `PendingApproval`; an already-approved or rejected expense cannot be re-approved. This guard lives once, in `ApproveExpense.Handle()` — see T4-02.
- **Reason semantics** (server-set, not caller-set): `ExpenseApproved.Reason ∈ {Manual, AutoThreshold, AutoNoGate}` — a diff that lets the caller set `Reason` directly is a T4-02/T4-05 violation even if syntactically it looks like a minor refactor.

## Tier 0 — APE scan: real findings and known gaps (run 2026-09-05)

Ran `agentic-posture-engine` (APE) against this repo as the concrete tier-0
step. Full findings and the fixes required to make APE runnable at all are
logged in `spike-log.md` — summary relevant to this constitution:

1. **APE cannot see this repo's actual domain code.** Its AST scanner
   (`ast_scanners.py`) only parses Python/JS/TS — Cratis's C# `Handle()`
   bodies are invisible to it. APE's tier-0 role here is necessarily
   confined to *agent/tool config* risk (MCP servers, IDE rule files,
   secrets), not the approval-gate logic itself. Tiers on approval-gate
   content (T4-01 through T4-08 above) cannot be delegated to APE and must
   run as a separate, hand-authored pattern check (e.g. a small `git diff`
   grep step) alongside it in Orca's post-build hook (step 2).
2. **APE's file discovery unconditionally prunes every dot-directory**
   (`discovery.py`'s `DEFAULT_IGNORE_DIRS` filter drops any dir starting
   with `.`), so `.claude/skills/**`, `.build-kit/**`, and `.mcp.json`'s
   sibling agent configs under hidden dirs are silently skipped unless they
   sit at repo root. `.mcp.json` itself was caught only because it's a
   root-level file, not because the scan reached into a hidden directory.
   T4-08 exists specifically to not rely on APE catching this.
3. **False-positive noise on plain `package.json`/`package-lock.json`.**
   APE's config scanner treats *any* JSON object with a `name` field as an
   "agent" definition and flags it for missing `max_steps` — this fired on
   `cratisapp`'s and the mobile client's ordinary npm manifests, not
   anything agent-related. Needs a `.ape-policy.yml` suppression or an
   upstream fix before wiring this into a gate that fails the build (step
   2) — otherwise every commit touching `package.json` trips a fake HIGH.

## Tier 0–1 wiring (step 2, 2026-09-05)

`.build-kit/hooks/tier01-gate.sh` runs both gates: APE scan (tier 0, informational — not a hard fail yet, see false-positive note above) then `dotnet build` (warnings-as-errors, already `true` in `CratisApp.csproj`) then `dotnet test` against `CratisApp.Specs` (xUnit + `Cratis.Specifications`/`Cratis.Specifications.XUnit`, new this step). Verified working end-to-end on this machine.

**Where it plugs into Orca**: Orca's only lifecycle hook points are `setup` (runs at worktree creation) and `archive` (runs at worktree removal) — there is no "post-agent-turn" or "pre-merge" hook. `tier01-gate.sh` is written to be pasted into the repo's `setup` hook in Orca's GUI (Settings → repo → Hooks; **no CLI command sets hook script content**, only whether a configured one runs, via `--setup run|skip|inherit`). This gates the *baseline* — a broken worktree fails fast before an agent burns turns on it — but does **not** gate the agent's own diff before tier 2, which is what "Gemini gets fast feedback before anything reaches tier 2" implies. Getting that requires external orchestration (`orca terminal wait --for exit` after the agent's terminal, then `orca terminal create` running this same script, then reading its exit code) — not yet built; see spike-log.md.

## Tier 2 scenario planning (step 3, 2026-09-05)

`.claude/skills/tier2-scenario-planner/SKILL.md` adapts autoqa-agent's discovery→plan pattern from
Playwright DOM crawling to Cratis's domain model: Phase 1 statically parses `[Command]`/`[EventType]`/
`[ReadModel]`/`IReactor` shapes out of the slice `.cs` files (instead of crawling rendered pages) into
`domain-graph.json`; Phase 2 turns that into a scenario matrix, each case ending in a **witness**
(event-store query — the actual ground truth, since a Cratis command can succeed at the UI while the
underlying event never gets appended) and, only where a slice has a UI component, an informational
**React snapshot** step. Demo-run against this repo's one real slice (`Registration`) at
`.build-kit/tier2/runs/2026-09-05-demo/`. **Correction while building this**: `docker-compose.yml`
runs MongoDB (`Cratis.Arc.MongoDB`, port `27017`), not Postgres — the constitution's Tier 2 line above
originally echoed the plan's "booted app + Postgres" phrasing uncritically; it's Mongo. Witness queries
are written against Mongo (exact collection schema not yet confirmed — step 4 is the first point
Chronicle actually boots in this spike).

## Tier 2 execution harness (step 4, 2026-09-05)

`.build-kit/tier2/start-stack.sh` (boot Chronicle + the app) and `.build-kit/tier2/run-tier2.sh`
(execute a plan's mechanically-runnable cases, write `report.json` + `evidence/*.json`) — both run
against a real live boot, not simulated. Confirmed the exact witness schema empirically (real database/
collection names, real document shape — see the skill's `references/witness-and-snapshot-patterns.md`,
updated from "unverified hypothesis" to "confirmed live" this step) and found a real gotcha: **the
command HTTP response's id is not the resulting event's `eventSourceId`** — witness queries must match
on event content, never on the command response id. Real run: 2 pass, 1 skipped (the reactor case,
honestly marked not-automatable rather than faked), 0 fail.

**Where "Orca hook" fits, given step 2's finding that no post-build hook exists**: this harness is
exactly the script step 2 said would need external orchestration — invoked via
`orca terminal create --command ".build-kit/tier2/start-stack.sh && .build-kit/tier2/run-tier2.sh <run-dir>"`
inside an Orca-managed worktree, with `orca terminal wait --for exit` and `report.json`'s exit code
(0 = all pass, 1 = any fail) as the gate signal. Not re-demonstrated against a live Orca instance this
step (that belongs to step 6's integration run) — the terminal primitives were already verified working
in step 2.

## Tier 3 adversarial pass (step 5, 2026-09-05)

`.claude/skills/tier3-adversary/` — a Claude-driven adversary role targeting the three attack classes
the spike brief named (threshold bypass, negative amounts, concurrent-approval race), each explicitly
tied to one of this document's approval-gate invariants or T4 rules rather than generic security-scan
checks. **The approval-gate-specific cases are written and ready
(`references/pending-cases.md`) but not executable — `SubmitExpense`/`ApproveExpense` don't exist
yet.** Demo-ran the adversarial stance against the one real command that does exist (`Register`) for
real findings now: no content validation at all (confirms `hasValidator: false` from step 3's static
analysis, live), a script-injection payload stored verbatim and permanently in the immutable event log,
and a genuine platform-level gap — a JSON type mismatch on a `ConceptAs<string>` field throws an
**unhandled exception** (`500`) inside Cratis's own `ConceptAsJsonConverter`, rather than the clean
`400` a missing field gets. Full findings: `.build-kit/tier3/runs/2026-09-05-demo/report.md`.

## Integration run (step 6, 2026-09-05) — blocked at tier 2, real bug found

Had Antigravity (`agy`, the working replacement for Gemini CLI — see spike-log.md) build the real
`SubmitExpense`/`ApproveExpense`/`RejectExpense` slice under `Expenses/Approval/`. Two `agy`-specific
findings first: it silently wrote the entire slice into a wrong, unrelated repo on the first attempt
(headless mode doesn't scope to the invoking shell's `cwd` — always pass `--new-project --add-dir
<path>`), and its free-tier quota is now exhausted for ~7 days after that misdirected run. Recovered by
copying the (correct, reviewable) generated files into this repo rather than re-running.

The code itself reads as a correct implementation of the design (validator, `PendingApproval` guard,
reactor correctly calling `commands.Execute(new ApproveExpense(...))` per T4-07, never a raw event) and
`tier01-gate.sh` passes clean. **But it fails tier 2**: booted the real stack and ran the tier-2/tier-3
approval-gate cases for the first time — `ExpenseApproved` is never appended, by any path, while the
command itself reports `isSuccess: true` with no exception.

**Root cause found** (full trace: spike-log.md step 6 addendum) — this is a Cratis platform/project-
setup gap, not an Antigravity code defect. Definitive isolation: a minimal throwaway command injecting
`IEnumerable<ICanResolveReadModelForCommand>` showed **zero resolvers registered in DI**
(`resolvers=[]`), reproduced identically against `Listing`, the pre-existing, independently-verified
read model — nothing to do with `ExpenseStatus` or anything Antigravity wrote. Ruled out along the way:
timing/replication lag (18s wait, no change), the `[Key]` attribute choice (Chronicle's own analyzer,
`ARCCHR0008`, confirms Antigravity's original choice was correct), missing query-method registration,
and Chronicle server/client version skew (pinned the server to the client's exact `16.39.1`, identical
failure). `Cratis.Arc.Chronicle`'s `ReadModelServiceCollectionExtensions.AddReadModels` is the method
that's supposed to populate this and doesn't appear to be invoked by this project's `AddCratis`/
`WithMongoDB` call chain — the concrete next step is tracing that method's real call sites in Cratis's
source, not further trial-and-error against the public API.

A genuinely valuable, independent side-finding surfaced along the way: **Arc's `isSuccess` response
flag reflects only whether the command pipeline ran without an unhandled exception — not whether a
`Result<TSuccess, TError>` command actually succeeded.** A call that hits the error branch still returns
`isSuccess: true`; the real outcome must be read from `response`'s shape. Any caller (UI or automation)
branching on `isSuccess` alone will be silently wrong — worth a standing convention, independent of the
DI bug above.

**This diff should not proceed to tier 4 as-is** — it doesn't clear tier 2's happy path, so the tier-3
adversarial cases (threshold/negative-amount/race) can't be meaningfully evaluated until the DI
registration gap is fixed upstream of the application code.

## Related

`spike-log.md` (running findings log across all 7 steps), `Active_Projects/Expense Tracker/Expense Tracker.md` in the vault (source of the locked design this constitution encodes), `.claude/skills/_shared/cratis-conventions.md` (source of the one-file-per-slice convention that drove the content-pattern-not-path-pattern decision above).
