# Listing read model reflects a new registration

## Preconditions

- App booted, Chronicle reachable.
- `Listing` is `[FromEvent<Registered>]` — AutoMap projects it directly, no explicit projection class
  to verify beyond the attribute being present (confirmed in `domain-graph.json`'s `readModels[0]`).

## Steps

1. Issue `Register` with `Name = "Katherine Johnson"`.
2. Witness: query Chronicle's event log and verify `Registered` was appended (same as the happy-path
   case's witness — included here too since this case can run independently of that one).
3. Witness (projection): query the `Listing.AllListings` read model (or `ObserveAllListings` if this
   skill's discovery re-run finds one added later — see extraction rule note in
   `domain-graph-schema.md`) and verify an entry exists with `Name.Value == "Katherine Johnson"`. Since
   `AllListings` returns `ISubject<IEnumerable<Listing>>` (observable/real-time), prefer subscribing
   and waiting for the emission over polling a plain query — this is exactly the "prefer Observe over
   polling" guidance in `witness-and-snapshot-patterns.md`.
4. React snapshot: render `ListingDataTable` and capture a snapshot showing the new row. Informational
   only per the same rule as the other cases.
