# `domain-graph.json` schema

Adapted field-for-field from autoqa-agent's `ExplorationGraph` / `PageNode` / `ElementSummary` /
`FormInfo` / `NavigationEdge` (`src/plan/types.ts` in terryso/AutoQA-Agent). Left column is the real
autoqa type this maps from; right is what to write here.

```jsonc
{
  "runId": "2026-09-05-demo",
  "generatedAt": "2026-09-05T00:00:00Z",
  "slices": [                        // was: ExplorationGraph.pages: PageNode[]
    {
      "id": "SomeModule.SomeFeature.Registration",   // was: PageNode.id (there: a page URL-derived id)
      "sourceFile": "SomeModule/SomeFeature/Registration/Registration.cs",
      "module": "SomeModule",
      "feature": "SomeFeature",
      "slice": "Registration",
      "commands": ["Register"],       // ids into the top-level `commands` array below
      "events": ["Registered"],
      "readModels": [],
      "reactors": ["RegistrationReactor"],
      "uiComponent": null             // path to a co-located .tsx, or null if automation-only
    }
  ],
  "commands": [                      // was: FormInfo (fields = ElementSummary[], submitButton = Handle())
    {
      "id": "Register",
      "sliceId": "SomeModule.SomeFeature.Registration",
      "fields": [                     // was: FormInfo.fields: ElementSummary[]
        { "name": "Name", "type": "SomeName", "conceptOf": "string" }
      ],
      "handleReturns": ["Registered"], // event id(s) this Handle() can produce
      "handleReturnShape": "tuple",    // "single" | "tuple" | "enumerable" | "result" | "void" — see cratis-conventions.md
      "hasValidator": false,           // true if a CommandValidator<T> exists in the same file
      "dcbReadModelParams": []         // read-model ids taken as Handle() parameters, if any (DCB rules)
    }
  ],
  "events": [                        // no direct autoqa equivalent — autoqa has no backend truth signal
    {
      "id": "Registered",
      "sliceId": "SomeModule.SomeFeature.Registration",
      "fields": [
        { "name": "Name", "type": "SomeName" }
      ]
    }
  ],
  "readModels": [                    // was: PageNode.links (things you can navigate to see state)
    {
      "id": "AuthorListItem",
      "sliceId": "...",
      "queryMethods": ["AllAuthors", "ObserveAllAuthors"]
    }
  ],
  "edges": [                          // was: ExplorationGraph.edges: NavigationEdge[]
    {
      "from": "Registered",           // event id
      "to": null,                     // command id the reactor calls, or null if it's a pure side-effect (e.g. logging)
      "action": "react",              // was: NavigationEdge.action ('navigate'|'click'|'form_submit') -> here always 'react'
      "trigger": "RegistrationReactor.Handle"
    }
  ],
  "warnings": [                       // slice files that didn't parse cleanly against cratis-conventions.md
    // { "file": "...", "reason": "..." }
  ]
}
```

## Extraction rules (mechanical, do these with Read + Grep, not guesswork)

- **Slice discovery**: find every `.cs` file under a module/feature/slice folder (3 levels deep from
  the project root's actual slice root — confirm the root name from an existing slice, don't assume
  `SomeModule`). Skip anything under `bin/`, `obj/`, `CratisApp.Specs/`, or matching `*.g.cs` / files
  containing `// @generated`.
- **Commands**: grep for `\[Command\]` immediately preceding a `public record`. The record's positional
  parameter list is `fields`. Find the `Handle()` method (on the record or a `partial` extension) and
  read its return type to determine `handleReturnShape` and `handleReturns` (an `IEnumerable<object>`
  body — inspect the `new X(...)` expressions inside it; a `Result<TSuccess,TError>` — `TSuccess` is
  the event).
- **Events**: grep for `\[EventType\]` preceding a `public record`; positional params are `fields`.
- **Read models**: grep for `\[ReadModel\]`; `public static` methods on the record are `queryMethods`.
- **Reactors**: grep for `: IReactor`; every public method with signature `Task <Name>(TEvent @event, EventContext context)` is one edge, `from` = `TEvent`'s id. If the body calls `commands.Execute(new SomeCommand(...))`, set `to` = `SomeCommand`'s id; otherwise `to: null` (pure side-effect, e.g. logging — see the shipped `RegistrationReactor` example).
- **UI**: a `.tsx` file in the same folder as the slice's `.cs` file → `uiComponent`. Cratis's
  `CratisProxiesUseSourceFileAsOutputFile` setting means the generated proxy sits right next to the
  `.cs` file too (`// @generated` marker) — don't treat the generated proxy itself as `uiComponent`,
  only a real hand-authored component that imports it.
