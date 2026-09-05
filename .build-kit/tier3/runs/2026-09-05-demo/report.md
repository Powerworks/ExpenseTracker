# Tier 3 adversarial pass — demo run, 2026-09-05

Target: the only real `[Command]` in this repo, `Register` (`SomeModule/SomeFeature/Registration`).
The approval-gate-specific attack classes this tier exists for (threshold bypass, negative amounts,
concurrent-approval race) are **not executable yet** — see
`.claude/skills/tier3-adversary/references/pending-cases.md`. This run instead applies the same
adversarial stance to the one command that exists, both to produce real findings now and to prove the
skill's mechanism (real HTTP call → real witness query) works before the approval gate lands.

## Findings

1. **No content validation on `Name` at all — confirmed, not just predicted.** Empty string,
   whitespace-only, and a 10,000-character string were all accepted (`isSuccess: true`) and durably
   recorded. `domain-graph.json` (step 3) already flagged `Register.hasValidator: false` from static
   analysis; this run proves the consequence live rather than inferring it.
2. **Unsanitized input stored verbatim, permanently, in an immutable log.** Sent
   `<script>alert(1)</script>` as the name; it landed in `event-log` byte-for-byte
   (`content.1.name: "<script>alert(1)</script>"`). Not necessarily exploitable today — depends
   entirely on whether `ListingDataTable.tsx` (or any future consumer) renders `name` through
   something that skips React's default JSX escaping (`dangerouslySetInnerHTML`, or a non-React
   consumer entirely) — but because Chronicle's event log is append-only, **a bad value here can never
   be edited, only compensated with a new event**. Worth deciding deliberately (validator, or an
   explicit "we render this as text everywhere, always" invariant) before any UI actually consumes
   free-text event content, not discovering it after a real user hits it.
3. **Missing-field vs. wrong-type produce very different failure quality.** Omitting `name` entirely
   produced a clean `400` with a proper validation message (`"The value is required."`, `members:
   ["Name"]`) — Arc's model binding enforces *presence* even with `hasValidator: false`. Sending a
   *number* where a string was expected (`{"name": 12345}`) instead threw an **unhandled exception**
   → `500`, with a real stack trace in the server log:
   `'System.String' is not a supported underlying concept value type for a JSON number token.` at
   `Cratis.Json.ConceptAsJsonConverter<T>.Read`. This is Cratis/Arc's own `ConceptAs<T>` JSON
   deserialization path, not application code — a malformed request type mismatch on *any*
   `ConceptAs<string>` field in *any* future slice will hit the same unhandled-exception path unless
   Cratis's converter is patched or every command adds its own type-coercion guard. Worth raising
   upstream or at minimum documenting as a known platform gap in `CONSTITUTION.md`'s tier-1 scope
   (this is exactly the kind of thing warnings-as-errors/xUnit won't catch, since it's a runtime JSON
   deserialization failure, not a compile-time or unit-test-level concern).
4. **SQL-injection-shaped input** (`'; DROP TABLE listings; --`) was accepted and stored — expected and
   harmless here (Mongo, not SQL, and Cratis doesn't build queries from event content), included only
   to confirm no accidental "string contains suspicious characters" filter exists that could produce
   false-positive rejections later.

## What could not be tested this run

The concurrent-approval race is the one attack class in the original spike brief that most needs a
DCB-guarded command to exist — `Register` mints a fresh `eventSourceId` per call, so there's no shared
identity to race two commands against. Confirmed general concurrent-write safety (many `Register` calls
in flight don't corrupt each other's distinct event sources) but that's a materially weaker claim than
"two commands racing the same `eventSourceId` can't both win" — see `pending-cases.md`'s
`concurrent-approval-race` case for the real test, blocked until `ApproveExpense` exists.

## Severity read (informal — this skill reports findings, not a pass/fail gate)

Findings 1 and 3 are the two worth acting on before real domain slices are built on the same patterns:
(1) because it confirms every future command needs an explicit validator-existence check as part of
code review, not an assumption Cratis provides one by default; (3) because it's a platform-level gap
that will recur on every slice with a `ConceptAs<string>` field unless addressed once, centrally.
