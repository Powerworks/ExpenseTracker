---
name: tier3-adversary
description: >
  Run the tier-3 adversarial pass (CONSTITUTION.md tier 3: "Claude-driven adversary role targeting
  the approval gate specifically: threshold bypass, negative amounts, concurrent-approval race").
  Given a command's Handle() body, its CommandValidator, and any DCB read-model parameters, actively
  try to break its invariants rather than confirm its happy path (tier 2's job). Use when: (1) a
  command with money/threshold/guard logic has landed and needs adversarial coverage before tier 4
  human sign-off, (2) the user asks to "run tier 3" / "adversarial pass" / "try to break the approval
  gate", (3) CONSTITUTION.md's T4-02/T4-03/T4-04/T4-05 rules just fired on a diff and the reviewer
  wants an adversary's read before approving.
---

# Tier 3 — Adversary Role

Tier 2 (`tier2-scenario-planner`) proves a command works when used as intended. This skill is the
opposite stance: **assume the command will be misused, and go find the input or timing that breaks
its stated invariant.** Every case here targets a specific invariant from `CONSTITUTION.md`'s
"Approval-gate invariants" section — don't invent generic security-scanner checks, ground each attack
in an actual documented rule.

> **Read first:** [`CONSTITUTION.md`](../../../CONSTITUTION.md)'s approval-gate invariants section —
> every attack case below is written to break one specific line in it. If a case doesn't cite which
> invariant it targets, it doesn't belong in this skill's output.

## The three attack classes (from the spike brief this step implements)

### 1. Threshold bypass

Targets: `RequireApprovalGate` / `AutoApprovalThreshold` (T4-03), and the guard "expense must be
`PendingApproval`; can't double-approve" inside `ApproveExpense.Handle()` (T4-02).

Attack shapes to try, once `SubmitExpense`/`ApproveExpense` exist:
- Submit an amount **exactly equal to** the threshold — is `<` or `<=` the actual comparator? (An off-
  by-one here silently changes which expenses need a human.)
- Submit at threshold `− 0.01` and `+ 0.01` — confirm the boundary is where the constitution says it
  is, not where the code happens to put it.
- Submit with `RequireApprovalGate = false` and a huge amount — confirm gate-skip really does skip
  regardless of amount (per the design: "sole trader = false" should auto-approve *everything*, not
  just small amounts).
- Call `ApproveExpense` twice in sequence on the same expense (human approves, then automation's
  reactor tries again, or vice versa) — the guard should reject the second call. If it silently
  succeeds, that's a T4-02 finding.

### 2. Negative / malformed amounts

Targets: whatever `CommandValidator<SubmitExpense>` exists (T4-05) — and the *absence* of one is
itself a finding.

Attack shapes:
- Negative amount — does a validator reject it, or does `Handle()` happily construct an event with
  `Amount < 0`? A negative-amount `ExpenseSubmitted` that later gets auto-approved (negative amounts
  are always under any positive threshold) is a real payout-fraud shape, not a theoretical one.
- Zero amount, `NaN`/`Infinity`-adjacent values if the field type allows them, absurdly large amounts
  (overflow / precision-loss boundary for whatever numeric type `Amount` uses).
- Empty/whitespace-only strings on any required text field, if the command has one.

### 3. Concurrent-approval race

Targets: the guard's atomicity — "must be `PendingApproval`" is read-then-write, and DCB read-model
parameters in Cratis are supplied fresh per `Handle()` call, so the question is whether Arc/Chronicle
serializes commands against the same `eventSourceId` or whether two concurrent calls can both observe
`PendingApproval` before either write commits.

Attack shape: fire two `ApproveExpense` (or one `ApproveExpense` + one `RejectExpense`) calls
concurrently at the same expense's `eventSourceId`, and check the event log afterward — exactly one
`ExpenseApproved`/`ExpenseRejected` should exist, never both, never two `ExpenseApproved`s.

**This attack class could not be executed this session — see the demo run's log entry for why (no
command in this repo targets an existing `eventSourceId`, so there was nothing to race against). The
case is written and ready in `references/pending-cases.md`; it needs the real `SubmitExpense`/
`ApproveExpense` slice to exist before it can run.**

## What this skill can do today, against whatever commands actually exist

Even before the approval-gate slice is built, run the same adversarial stance against any existing
`[Command]`:
1. Read the command's fields, its `Handle()` body, and its `CommandValidator<T>` (if any).
2. For each field, ask: what's the most hostile value a caller could send, and what actually happens?
   Empty string, max-length-plus-one, injection-shaped strings (`<script>`, `'; DROP`, null bytes) even
   though Cratis's C#/Mongo path isn't SQL-injectable — the point is confirming *nothing* silently
   accepts and stores unvalidated hostile input, not assuming a specific vulnerability class applies.
3. Issue the real HTTP call, then use `tier2-scenario-planner`'s witness mechanism (event-log content
   query) to check what actually got recorded — an adversarial case's "pass" condition is usually the
   *rejection* being recorded (or nothing being recorded), not a success.
4. Write findings to `.build-kit/tier3/runs/<runId>/report.md` — plain findings, not pass/fail against
   a matrix, since there's no pre-defined expected outcome the way tier 2 has one.

## References
- [references/pending-cases.md](references/pending-cases.md) — the three approval-gate-specific
  attack cases (threshold bypass, negative amount, concurrent race), written and ready to run once
  `SubmitExpense`/`ApproveExpense` exist. Not executable yet — see `spike-log.md` step 5.
- [../tier2-scenario-planner/references/witness-and-snapshot-patterns.md](../tier2-scenario-planner/references/witness-and-snapshot-patterns.md) —
  the confirmed event-log query mechanism this skill reuses for verifying what an attack actually did.
- [`CONSTITUTION.md`](../../../CONSTITUTION.md) — the invariants every case here targets.
