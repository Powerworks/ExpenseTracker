# Witness and React-snapshot patterns

## Witness (event-store query) — confirmed live 2026-09-05 (step 4)

Both mechanisms below are now verified against a real boot (`docker compose up chronicle` + `dotnet
run`, real `POST /api/some-module/some-feature/registration`, real Mongo query) — see
`.build-kit/tier2/run-tier2.sh` for the working implementation and
`.build-kit/tier2/runs/2026-09-05-demo/report.json` + `evidence/*.json` for real output.

**Critical gotcha found on the live run — read this before writing any witness query**: the command's
HTTP response (`CommandResult<T>.response`, the id `cratis-conventions.md` documents as coming back
from a `(Guid, EventName) Handle()` return shape) is **not** the resulting event's `eventSourceId`. On
a real `Register` call, the response returned one Guid; the event that landed in `event-log` had a
completely different `eventSourceId` — not a formatting/byte-order difference, a different value
outright. Root cause not fully diagnosed (plausibly the response is a command/correlation id rather
than the domain `eventSourceId` for this particular return shape) — don't assume it's fixed until
someone traces it through Arc's source. **Practical fix**: witness queries match on `type` +
`content.<generation>.<field>` (the event's own content, not any id returned by the command), never on
the command response id as a join key. `run-tier2.sh`'s `witness_event()` does this.

### Preferred: Arc's generated read-model query, not the raw event log

Arc auto-generates a query endpoint for every `[ReadModel]` (see
`Event-Driven Systems/Tools and Libraries/Cratis/Arc Model-Bound Queries.md` in the vault). A read
model is a *projection* of the event log, not the log itself, so it's eventually consistent — but it's
the documented, supported way to observe state from outside the process, versus reaching into
Chronicle's internal storage. Use this as the witness whenever the slice already has a `[ReadModel]`
that reflects the event in question:

```
GET /api/<readmodel-query-route>
```

Poll (with a short timeout — Arc's queries can also be `ObserveX` subjects for real-time push, prefer
that over polling where the read model supports it) until the expected value appears, then assert on
the response body. Write the case's step as:

> Witness: query `<ReadModelName>.<QueryMethod>` and verify `<field>` equals `<expected>` within
> `<timeout>`.

### Fallback / stronger guarantee: direct Mongo query against Chronicle's event log — confirmed schema

Chronicle's raw event log genuinely is a plain Mongo collection — no gRPC client or special tooling
needed to read it externally. Confirmed database/collection naming and document shape, from a real
`Register` call against this repo:

- **Database**: `<EventStore>+es+<Namespace>` — this project's `appsettings.json` sets
  `Chronicle.EventStore = "CratisApp"`, default namespace is `Default`, so: `CratisApp+es+Default`.
  (Chronicle's own internal event store is separately `System+es+Default` — don't query that by
  mistake.)
- **Collection**: `event-log`.
- **Document shape** (real example, from a live `Register` call):
  ```json
  {
    "_id": "0",
    "type": "Registered",
    "occurred": "2026-09-05 15:26:04.950000",
    "eventSourceId": "a9426e5e-c8eb-49ef-9d6f-b3623f211b7b",
    "eventSourceType": "Default",
    "eventStreamId": "Default",
    "content": { "1": { "name": "Ada Lovelace" } },
    "causation": [ { "type": "Command", "properties": { "commandType": "Register", "name": "Ada Lovelace" } } ]
  }
  ```
  `type` is the exact `[EventType]` record name. `content` is keyed by **schema generation** (a string
  integer, `"1"` for a never-evolved event type — not a per-field index as an early read of this
  collection's shape wrongly suggested before the real content was inspected), and *within* that
  generation the fields are the event's own properties, camelCase (`Name` → `name`), matching the
  React proxy's field naming, not the C# PascalCase.
- **Read-model collections live in a separate, plainly-named database** — `<EventStore>` itself (here:
  `CratisApp`), one collection per read model, named lowercase-plural-ish after the record (`Listing` →
  `listings`, confirmed). Each read-model document's `_id` is a **BSON Binary-encoded Guid** equal to
  the event's real `eventSourceId` (confirmed: decoding the `listings` document's `_id` bytes as a UUID
  produces the exact same value as the source event's `eventSourceId` — this is the reliable way these
  two witness mechanisms cross-check each other).

Write the case's step as:

> Witness: query Chronicle's event log (`<EventStore>+es+<Namespace>`.`event-log`) for
> `type = "<EventTypeName>"` and `content.1.<field> = <expected>`, **not** by matching the command's
> HTTP response id (see the gotcha above).

Use this over the read-model fallback specifically for cases whose whole point is proving the event
was recorded correctly (T4-01-adjacent concerns — event schema/shape), and for the `form` case type
above where the assertion is "no event was appended" (a read-model query can't easily prove a
*negative* — the read model just won't have changed, which is indistinguishable from "hasn't caught up
yet"; the event log can be queried for absence with more confidence after the projection's known lag).

## React snapshot (UI)

Only for slices with a `uiComponent` in `domain-graph.json`. This is the one piece that *is* a direct
carry-over from autoqa's own approach (its `snapshot()` Playwright tool — see `explore.ts`), scoped
down from "crawl the whole rendered page" to "snapshot the one component this slice owns."

Write the case's step as:

> React snapshot: render `<Component>` with props reflecting the post-command state (from the witness
> above), capture a snapshot (Playwright `page.screenshot()` scoped to the component's locator, or a
> React Testing Library / Vitest snapshot if the project has component-level test infra — neither is
> wired up yet in this repo as of 2026-09-05, that's part of step 4), and compare against the committed
> baseline. Flag for human review on first mismatch rather than auto-failing — visual diffs have a
> higher false-positive rate than a witness query, so treat this as informational for tier 2, not a
> hard gate (the constitution's tier 2 auto-passes on green; a snapshot diff alone shouldn't block if
> the witness passed).
