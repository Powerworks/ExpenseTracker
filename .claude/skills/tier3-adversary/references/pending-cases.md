# Pending tier-3 cases — approval gate

Written against the locked design in the vault (`Active_Projects/Expense Tracker/Expense Tracker.md`)
and `CONSTITUTION.md`'s approval-gate invariants. **Not executable as of 2026-09-05** — `SubmitExpense`,
`ApproveExpense`, and `RejectExpense` don't exist in this repo yet (`SomeModule/SomeFeature` is still
template placeholder, confirmed in the vault's Expense Tracker status note and every prior spike step).
Run these the moment that slice lands, before it reaches tier 4 human sign-off.

## Case: threshold-boundary-comparator

**Targets**: T4-03 (`AutoApprovalThreshold` invariant) — is the comparator `<` or `<=`?

1. Set `ExpensePolicy:RequireApprovalGate = true`, `AutoApprovalThreshold = 100.00`.
2. Submit an expense with `Amount = 100.00` exactly.
3. Witness: query the event log — did `AutoApprovalReactor` fire (a second `ApproveExpense` →
   `ExpenseApproved{ApprovedBy: "system", Reason: AutoThreshold}` event, per the design's server-set
   `Reason` semantics), or did the expense stay `PendingApproval`?
4. Repeat at `Amount = 99.99` and `Amount = 100.01`.
5. **Finding, not pass/fail**: report exactly where the boundary falls and whether it matches what a
   reasonable reading of "AutoApprovalThreshold" implies (most likely intent: amounts *strictly under*
   the threshold auto-approve, `100.00` itself requires a human — but the design doc doesn't say `<` vs
   `<=` explicitly, so this case's real job is forcing that ambiguity to become an explicit decision).

## Case: gate-skip-ignores-amount

**Targets**: T4-03, the "sole trader = false" auto-approval-for-everything semantics.

1. Set `RequireApprovalGate = false`.
2. Submit an expense with `Amount = 1000000.00` (far above any reasonable threshold).
3. Witness: verify it auto-approves via the `AutoNoGate` reason (per the design's `Reason ∈ {Manual,
   AutoThreshold, AutoNoGate}` enum) — if it instead stays `PendingApproval` or auto-approves under the
   wrong `Reason` value, that's a T4-03 finding (the amount is being checked even though the gate is
   supposedly fully off).

## Case: negative-amount-accepted

**Targets**: T4-05 (validator existence/strength on `SubmitExpense`).

1. Submit `Amount = -50.00`.
2. Expected: a `CommandValidator<SubmitExpense>` rejects this before `Handle()` runs — witness should
   show **no** `ExpenseSubmitted` event.
3. If it succeeds: this is a **critical** finding, not a minor one — a negative amount is below every
   positive threshold, so with `RequireApprovalGate = true` it would still auto-approve (T4-03's
   comparator doesn't protect against negative values, only against values *above* the threshold), and
   with a `PayoutReactor` wired to a real payment gateway later, a negative "expense" payout is a
   concrete fraud/refund-abuse shape, not a data-quality nitpick.
4. Also try `Amount = 0.00` — same question, lower severity (a validator might reasonably allow it;
   report what actually happens, don't assume zero should be rejected without checking the design's
   intent first).

## Case: concurrent-approval-race

**Targets**: the guard's atomicity in `ApproveExpense.Handle()` — "must be `PendingApproval`; can't
double-approve."

1. Submit one expense, `RequireApprovalGate = true`, `Amount` above threshold (stays `PendingApproval`,
   no reactor interference).
2. Fire two concurrent `ApproveExpense` calls at the same `eventSourceId` — one with a human
   `ApprovedBy`, one racing from a second client (simulating the reactor and a human approving at the
   same instant, or two humans both clicking approve).
3. Witness: the event log for that `eventSourceId` should contain **exactly one** `ExpenseApproved`.
   Two would mean the guard's read-then-write isn't atomic under Chronicle's actual concurrency model —
   this is the single most important thing this case can discover, since it's a property of the
   Cratis/Chronicle platform generally, not just this one command, and would affect every DCB-guarded
   command in any future slice, not only this one.
4. **What this session could establish about the general mechanism, short of the real command**: fired
   many concurrent `Register` calls (the only command that exists) against the live stack — see
   `spike-log.md` step 5. `Register` always mints a fresh `eventSourceId` per call, so it can't
   reproduce the *same-eventSourceId* race this case needs; it only establishes that concurrent writes
   to *different* event sources don't corrupt each other, which is a much weaker guarantee. This case
   remains genuinely blocked until a DCB-guarded command exists.
