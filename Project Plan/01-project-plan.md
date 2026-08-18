# Project Plan — Expense Tracker

## 1. Document Purpose

This plan defines scope, phasing, tooling workflow, and risks for building a
small-company expense-tracking app: photograph a receipt, submit the expense,
route it through an approval workflow (manual or auto-approved under policy),
pay it out. Event-sourced on .NET/Cratis, modeled Event-Model-first the same
way [[Underwriting]] was — a fully elaborated board (commands/events/views,
Given/When/Then) before implementation — but scaled to a solo build, not a
multi-engineer engagement. Source: `Expense Tracker.md` (Obsidian
`Active_Projects`), tech stack and approval-workflow design locked
2026-08-14.

## 2. Assumptions

| # | Assumption |
|---|---|
| A1 | Solo build: one developer (William) pairing with an AI coding agent (Claude Code) driven by the eventmodelers build kit — no team-sizing section, unlike Underwriting |
| A2 | Backend: Cratis (event store: Chronicle), .NET — deliberately not MartenDB, so this project doubles as a hands-on comparison against the Marten-based Underwriting build |
| A2a | **Revised 2026-08-18, before board modeling**: Cratis is not the default for the whole app. Most slices will be plain CRUD via EF Core + Postgres in the same `CratisApp.csproj`; Cratis/Chronicle is reserved for slices with a genuine event-sourced lifecycle worth an audit trail (the `Expenses` approval workflow below is the model case — `PendingApproval → Approved/Rejected → PayoutRequested → Paid` with guarded transitions). Per-slice stack choice gets decided during board modeling, not defaulted to Cratis just because the scaffold has it installed |
| A3 | Frontend: React (web) + React Native (mobile), targeting Android for the first real-device test — not Blazor/MAUI, not Flutter |
| A4 | Modeling and build tooling: `@eventmodelers/cli`, using its `cratis-csharp` community stack as the base build kit, customized for this project's own conventions once the skeleton is proven — **not** GitHub's spec-kit (Underwriting used both `.specify`/spec-kit and eventmodelers; this project uses eventmodelers only) |
| A5 | Config (`ExpensePolicy`: `RequireApprovalGate`, `AutoApprovalThreshold`) stays static `appsettings.json`, not event-sourced — a deliberate scope cut, see Design note in the Obsidian doc |
| A6 | No bank-account linking in this scope — receipt photo + manual entry only, keeping the trust/security surface small |
| A7 | Single bounded context (`Expenses`) for v1 — unlike Underwriting's 11 contexts, this domain doesn't currently justify a multi-module split; revisit only if a second, genuinely separate context appears on the board |
| A8 | `dotnet` resolves to a user-local .NET 10.0.400 SDK + .NET/ASP.NET Core 9.0 runtimes under `~/.dotnet` (pinned via this repo's `global.json`), not the system `dotnet-sdk-10.0` package — Fedora's packaged 10.0.110 SDK is several feature bands behind and its bundled Roslyn can't load Cratis's source generators (`CS9057`); see §5.2 note |

## 3. Objectives

- Deliver a working v1: submit → approve (manual or auto) → pay out, with a
  mobile-first capture flow and an auditable event stream as the record of
  truth.
- Prove out the Cratis/Chronicle stack hands-on, and capture what's actually
  different from Marten in practice (not just the marketing pitch) once
  there's real code on both projects.
- Prove out the eventmodelers `cratis-csharp` build kit against a real board
  and a real build — it's an untested community kit for this stack, the same
  status `build-kit-dotnet-es` had before its first real run against
  Underwriting. Treat its skills as a first draft to validate, not something
  already exercised end-to-end.
- Keep the approval-gate guard logic in exactly one place (the `ApproveExpense`
  command handler) so manual and auto-approval paths can never diverge — see
  Design section of the Obsidian doc for the reactor-issues-a-command
  pattern.

## 4. Scope

### In scope — v1

- `Expenses` context: `SubmitExpense`, `ApproveExpense` (guarded,
  `ApprovedBy` = person or `"system"`), `RejectExpense`
- `AutoApprovalReactor` — pure domain logic, no I/O, issues `ApproveExpense`
  per policy config
- `PayoutReactor` — calls a mock payment gateway, `ExpensePayoutRequested` →
  `ExpensePaid`
- `ExpenseView` read model: `Status`, `ApprovalReason`
  (`Manual`/`AutoThreshold`/`AutoNoGate`)
- Receipt photo capture + blob storage, referenced from the event stream
  (not embedded in it)
- Web client: Cratis's own co-located frontend (`.frontend/` + per-slice
  `.tsx`, PrimeReact, auto-generated TS command/query proxies via
  `Cratis.Arc.ProxyGenerator.Build`) — adopted 2026-08-14 in place of a
  hand-scaffolded standalone SPA once the `cratis-csharp` install revealed
  this is what the kit's own `build-state-change` skill already assumes for
  UI-triggered slices. Still a genuine language boundary (TypeScript calling
  C# only over HTTP, never in-process) — the design note in the Obsidian doc
  was ruling out Blazor/MAUI, not repo/build co-location
- Mobile client: React Native (Expo, `clients/mobile`), targeting Android —
  Cratis's proxy generation is web/DOM-only, so mobile has no generated
  client and consumes the same REST/Swagger surface by hand. Worth asking
  the Cratis maintainers whether an RN-compatible proxy target exists or is
  planned; either way this isn't a blocker, just less generated-client
  convenience on the mobile side
- Repo/CI skeleton: solution scaffold, build kit wired to a board, base
  pipeline

### Out of scope — v1 (candidate v2/later)

- OCR / receipt-parsing (auto-extract amount/vendor/date) — natural fit for
  an LLM parser later, explicitly not a v1 requirement (avoid scope-creeping
  the first working version around it)
- Bank-feed linking — real threat-model surface, deliberate later decision
  not a default (see [[Cybersecurity/Welcome|Cybersecurity]] track)
- Event-sourcing the policy config itself (temporal "what threshold applied
  when this was submitted") — a legitimate real-world need, flagged in code
  as a deliberate cut, not an oversight
- Becoming [[Hadisfar Health]]'s actual expense system — undecided whether
  this app ever replaces [[Business Expenses]] or stays a personal
  convenience tool; not a v1 decision

## 5. Tooling & Workflow

Two-phase eventmodelers workflow, modeling fully separated from building —
no spec-kit involvement anywhere in this project.

### 5.1 Modeling phase (next step after this plan — board not created yet)

1. `npx @eventmodelers/cli init --modeling` — skills + agent loop only, no
   backend scaffold yet.
2. `npx @eventmodelers/cli run --modeling` — event storming, timelines,
   wireframes, live on the board. The Design section already drafted in the
   Obsidian doc (commands/events/reactors/read model) is the starting input,
   not something to re-derive from scratch.
3. Work the board through eventmodelers' own gated 9-step sequence — each
   step gates on confirmation before the orchestrator advances. Step 8
   (`/eventmodeling-checking-completeness`) builds a field traceability
   matrix confirming every event-produced field is consumed somewhere and
   every command-required field has an origin; Step 9 (validate) runs after,
   before handoff to the build kit.
4. **Extra QA gate on top of eventmodelers' own Steps 8–9** (this project's
   own practice, not an eventmodelers-documented feature): once our own
   completeness check and Step 9 validation pass, diff the finished board
   against a known-good reference board (e.g. Underwriting's, or an
   eventmodelers reference board) looking for structurally-obvious gaps —
   a missing rejection/cancellation path, a read model with no consuming
   screen, an event nothing subscribes to. A second, independent lens on
   top of the tool's own checks, not a replacement for them.

### 5.2 Build phase

1. `npx @eventmodelers/cli init --stack cratis-csharp` — scaffolds the Cratis
   backend and installs the community Cratis build kit into this repo.
   Requires this project's own `boardId`/`token`/`organizationId` (same
   eventmodelers org as Underwriting, new board) — run once the board from
   5.1 exists.
2. Validate the scaffold with a real `dotnet build` before trusting any of
   the kit's skill instructions, the same discipline `build-kit-dotnet-es`'s
   `AGENT.md` used for Marten (its Program.cs/wiring guidance was derived
   from an actual successful build, not docs alone) — Cratis conventions
   get the same treatment here since the kit is community-status/unvalidated.
   **Confirmed 2026-08-14**: the `cratis-csharp` scaffold (`CratisApp.csproj`,
   single flat project — consistent with A7's single-context decision) builds
   green, but only once `dotnet` resolves to a genuinely current SDK — see
   A8. The failure mode is worth recording since it doesn't look like a
   Cratis problem at first: `CS9057` analyzer-version errors on
   `Cratis.Arc.Core.Generators.dll`/`Cratis.Fundamentals.TypeDiscovery.Generator.dll`
   (compiler too old for the packages' Roslyn-version-targeted analyzers),
   then — once the SDK itself is current — an `MSB3073`/`dotnet/app-launch-failed`
   from the post-build `Cratis.Arc.ProxyGenerator.Build.dll` step, which
   reflection-loads the built app DLL to discover `[Command]`/`[Query]`
   types for TS proxy generation and therefore needs the
   `Microsoft.AspNetCore.App` 9.0 shared runtime present (not just
   `Microsoft.NETCore.App`) even though the SDK itself is 10.x.
3. "Build our own kit": once the scaffold and a first real slice build
   cleanly, fork the installed `cratis-csharp` kit's skills
   (`build-state-change`, `build-state-view`, `build-automation`) into this
   project's own conventions, the same way `build-kit-dotnet-es` itself was
   forked from `build-kit-dotnet` after a real retrofit settled its
   storage-strategy question. Don't rewrite the kit blind against docs
   before that first real build exists to crib from.
4. `npx @eventmodelers/cli run` — the agent loop builds `Planned` slices off
   the board into the skeleton, one at a time (or via chapter orchestration
   once several slices are queued).

## 6. Phased Delivery Plan

Rough relative sizing, not committed dates — this is a solo build, not a
resourced engagement like Underwriting's.

| Phase | Name | Goal |
|---|---|---|
| 0 | Modeling | Event Model board for `Expenses` built and gated through eventmodelers' own Steps 1–9, plus the reference-board comparison pass (§5.1) |
| 1 | Skeleton & Build Kit | `cratis-csharp` scaffold installed and building green; kit forked into project-specific conventions; React web + React Native shells scaffolded; repo/CI baseline |
| 2 | Core Slices | `SubmitExpense`/`ApproveExpense`/`RejectExpense`, `AutoApprovalReactor`, `ExpenseView` — the approval workflow end-to-end, auto and manual |
| 3 | Payout & Receipts | `PayoutReactor` + mock gateway, receipt photo capture/blob storage wiring |
| 4 | Client Wiring | React web + React Native screens consuming the read model / issuing commands over the wire; Android device test |
| 5 | Hardening | Full GWT-scenario regression from the board, deferred-cut notes (config-as-event, OCR, bank linking) confirmed still deliberate, not drifted-into |

## 7. Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| `cratis-csharp` build kit is community/unvalidated for this project's shape | High | Phase 1 explicitly validates scaffold + first slice against a real build before trusting kit skill instructions (§5.2 step 2), before forking into "our own" kit |
| Cratis learning curve (first hands-on use, vs. Marten on Underwriting) | Medium | Treat Phase 1–2 as the comparison exercise itself; capture concrete differences as they're found, not from documentation alone |
| Auto-approval and manual-approval guard logic drift apart | High | Single architectural rule (§3): the reactor issues the same `ApproveExpense` command a human would, never writes `ExpenseApproved` directly — enforce in code review of the slice, not just in the model |
| Receipt/blob storage becomes a de facto security surface without a deliberate decision | Medium | Blob storage is referenced from the event stream, not embedded — keep access/retention as an explicit decision when that slice is built, not a default |
| Scope creep into OCR/receipt-parsing or bank linking during build | Medium | Both are explicitly out of scope for v1 (§4) — new scope goes through modeling first, not straight into a build slice |
| Solo build has no second reviewer for the modeling completeness check | Medium | The reference-board comparison pass (§5.1 step 4) is the substitute for a second human reviewer — don't skip it under time pressure |

## 8. Definition of Done (per slice)

- Slice implemented against a `Planned` board slice via the build kit, with
  unit + integration tests
- Every GWT scenario for the slice (from the board) passes as an automated
  acceptance test
- Chronicle event stream/read-model shape documented in the module's README
- Slice status updated back to the board (`Done`/`Blocked`) via
  `set-slice-status --remote`
- Deliberate scope cuts (config-as-event, OCR, bank linking) still intact —
  not silently absorbed by a slice that didn't need to touch them

## 9. Success Metrics (v1)

- Full submit → approve (manual + auto) → payout path working end-to-end on
  a real Android device
- 100% of the board's GWT scenarios passing as automated acceptance tests
- Zero direct `ExpenseApproved` writes outside the `ApproveExpense` command
  handler (grep-able architectural invariant, candidate for a fitness test
  once the pattern from Underwriting's `CommandStateFitnessTests` is ported)
- At least one concrete, written comparison note: Cratis vs. Marten, based on
  this build and Underwriting's

## 10. Related

[[about Event Modeling]], [[Underwriting]] (sibling project, same
Event-Model-first / .NET-event-sourcing pattern, Marten instead of Cratis),
`Expense Tracker.md` (source design doc), [[Business Expenses]] and
[[Hadisfar Health]] (the manual process this could eventually replace).
