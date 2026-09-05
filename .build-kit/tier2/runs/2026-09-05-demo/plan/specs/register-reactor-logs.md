# RegistrationReactor observes Registered

## Preconditions

- App booted, Chronicle reachable.
- Reactor is registered (Cratis auto-discovers `IReactor` implementations — no explicit setup step
  needed beyond the app starting).

## Steps

1. Issue `Register` with `Name = "Grace Hopper"`.
2. Witness: query Chronicle's event log and verify `Registered` was appended for the returned
   `eventSourceId` (same witness as the happy-path case — this case exists to isolate the reactor's
   own behavior from the command's, not to re-prove the append).
3. Witness (reactor side-effect): `RegistrationReactor.Handle` only logs (`LogRegistered`) — it does
   not call `ICommandPipeline.Execute`, so `domain-graph.json`'s edge for this trigger has `to: null`.
   There is no second event to witness for this reactor. If step 4's harness has access to the app's
   structured log output, verify a `Registered: Grace Hopper` log line instead; otherwise mark this
   case's reactor-specific step **not automatable** and rely on the reactor's own Cratis.Specifications
   unit spec (if one exists) for that assertion.

## Note for whoever runs this

This case is a template for the *general* reactor-edge case type
(`domain-graph.json`'s `edges[].to !== null`) once a real translation reactor exists — e.g. the
Expense Tracker design's `AutoApprovalReactor`, which *does* call `ICommandPipeline.Execute(new
ApproveExpense(...))`. For that shape, step 3 above becomes a real second witness: query the event log
for the *second* command's event, not a log line. This repo currently has no translation reactor to
demonstrate that path against — flagged here rather than faked.
