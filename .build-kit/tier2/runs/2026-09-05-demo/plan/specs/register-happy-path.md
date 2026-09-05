# Register — happy path

## Preconditions

- App booted, Chronicle reachable (`docker compose up`).
- No prior `Registered` event exists for the `EventSourceId` this case generates (fresh `Guid`).

## Steps

1. Issue `Register` with `Name = "Ada Lovelace"`.
2. Verify the command succeeds (non-error `CommandResult`) and returns a new `eventSourceId`.
3. Witness: query Chronicle's event log for the returned `eventSourceId` and verify a `Registered`
   event exists with `Name.Value == "Ada Lovelace"`. (Exact collection/query mechanism: see
   `.claude/skills/tier2-scenario-planner/references/witness-and-snapshot-patterns.md` — not yet
   confirmed against a live instance; step 4's first job is nailing this down.)
4. React snapshot: render `RegisterDialog` in its post-submit (closed/success) state and capture a
   snapshot. Informational only — do not fail this case on a snapshot mismatch alone if step 3 passed.
