# Orca/APE/autoqa harness-eval spike — findings log

Running log for the 7-step plan (constitution → tier 0–1 wiring → tier 2
skill → tier 2 harness → tier 3 adversarial → integration run → report).
Findings get appended here as each step happens, not saved for the report —
particularly anything that changes the view of Orca's suitability as a
harness, since that's what the whole spike is testing before AgentOS gets
built on top of it.

## Term resolution (2026-09-05)

The originating plan (pasted from a Claude.ai web session, recovered from
`~/.claude/paste-cache/`) referenced three things with no trace anywhere on
this machine at spike start. Resolved via user + web search:

- **APE** = [`nareshgcv/agentic-posture-engine`](https://github.com/nareshgcv/agentic-posture-engine) — offline static linter/auto-fixer for AI agent configs (MCP, CrewAI, AutoGen, LangChain/LangGraph, IDE rule files, Python/JS/TS source). `ape scan` / `ape fix`, policy via `.ape-policy.yml`, SARIF/JSON/Markdown output.
- **autoqa** = [`terryso/AutoQA-Agent`](https://github.com/terryso/AutoQA-Agent) — Claude Agent SDK + Playwright acceptance-testing CLI with exactly the two-phase pattern the plan names: `autoqa plan-explore` (discovery) then `autoqa plan-generate` (plan). Not yet installed/evaluated — that's step 3.
- **The Cratis repo** = `Powerworks/ExpenseTracker` (this repo). Confirmed identical checkout at `~/Code/DotNet/ExpenseTracker` and `~/Code/AgentOS/targets/ExpenseTracker` (same origin, same HEAD commit `fe76ecd`).
- **Orca** (`~/Code/Orca`) currently only contains the unrelated Minor-Working-Hour-Auditor project — no ExpenseTracker/Cratis wiring exists yet. Step 2 is a from-scratch integration, not "get the existing wiring passing."
- **Dilger** — still unidentified; not referenced anywhere on this machine. Assumed to be a person from the other conversation this plan came from; the report (step 7) will need the user to fill in who that is, since nothing here can resolve it.

## Step 1 — Constitution (2026-09-05)

Wrote `CONSTITUTION.md`. Key decision made along the way: Cratis's
one-`.cs`-file-per-slice convention (command + event + read model all
co-located, no `Commands/`/`Events/` folders) rules out path-based tier-4
gating — the rules had to be content-pattern (`git diff` line matches)
instead. This is a real constraint the original plan's phrasing ("event
schema changes, approval-gate logic, auth boundaries" as if they were
separable diff *categories*) didn't anticipate — worth flagging because it
also affects step 2's Orca hook design: the hook needs a diff-content grep
step, not a changed-files-list check.

**Tier 0 (APE) evaluation — this is the first real signal on tool
suitability, logged in full because it's substantial:**

Installed APE from GitHub source (not on PyPI: `pypi.org/pypi/agentic-posture-engine/json` returns 404, despite the README implying `pip install agentic-posture-engine`). At HEAD (`45ada78`, 2026-09-05), **the CLI does not run out of the box** — four separate breakages, all fixed locally to get a working scan, none upstreamed yet:

1. `cli.py` imports `analyze_path` and `discover_repo_files` from `discovery.py` — neither was ever defined there (`discovery.py` only ever exported `discover_files`, per its one-commit git history). The whole file-dispatch layer the CLI depends on was never written. Patched by adding both functions to the installed package, dispatching to the three scanner modules by extension.
2. `scanners/__init__.py` imports from `ape_linter.scanners.ast_scanner` (singular) — the actual module is `ast_scanners.py` (plural). Typo, one-line fix.
3. `reporters/sarif.py` only defines `export_sarif(violations)` (string-returning); `cli.py` calls `generate_sarif(violations, target_path)` expecting a dict back for `json.dump()`. Added a `generate_sarif` wrapper.
4. `scanners/config_scanner.py` has a corrupted 48-line block (lines 403–450) — a duplicated APE-006/APE-007 rule pair with a stray `return violations, capabilities` statement injected mid-block, causing a `SyntaxError` on import. Looks like a bad merge/rebase artifact, not a logic bug — deleted the corrupted first copy, kept the clean second copy.
5. (Separate, non-fatal until triggered) `SECRET_REGEX`'s Slack-token pattern is `xox[b-aprs]-` — an invalid regex character range (`b-a` has no valid ordering) that throws `re.PatternError` at import time on Python 3.14. Fixed to `xox[baprs]-` (the intended literal set).

**None of this is a fork** — these are local patches to the installed
package under `~/.local/lib/python3.14/site-packages/ape_linter/`, not
committed anywhere. If APE stays in the pipeline past this spike, either
upstream needs these fixes merged, or ExpenseTracker needs to vendor a
patched copy rather than depending on `pip install` from GitHub HEAD.

**Once running, real findings against this repo:**
- `.mcp.json:3` (`eventmodelers` MCP server) — HIGH, no `max_steps` bound. Real, legitimate finding.
- `package.json`, `clients/mobile/package.json`, `clients/mobile/package-lock.json` — HIGH, "agent lacks max_steps." **False positive**: APE's config scanner treats any JSON object with a `name` field as an agent definition. Fires on ordinary npm manifests.
- **Coverage gap**: `discovery.py`'s directory walk unconditionally prunes every directory starting with `.` — so `.claude/skills/**` and `.build-kit/**` (the actual agent-instruction surface for this project's build pipeline) are never scanned. `.mcp.json` was only caught because it sits at repo root, not because hidden-dir scanning works.
- **Language gap**: APE's AST scanner only covers Python/JS/TS. Cratis's C# `Handle()` bodies — where the actual approval-gate logic lives — are completely outside APE's static-analysis reach. This is the reason T4-01 through T4-07 in the constitution are hand-authored diff-pattern rules rather than "let APE catch it."

**Running view on Orca's suitability**: no signal yet — step 1 never touched Orca. First real signal on that comes in step 2.

## Step 2 — Tier 0–1 wiring (2026-09-05)

**This is the first real signal on Orca's suitability as a harness, and it's
a significant finding: as originally phrased, "wire xUnit +
warnings-as-errors into Orca's post-build step" doesn't map onto anything
Orca actually has.**

- Orca's lifecycle hooks are exactly two: `setup` (runs at worktree
  creation) and `archive` (runs at worktree removal) — confirmed via
  `orca repo add --json`, which returns `hookSettings: {scripts: {setup:
  "", archive: ""}}`. There is **no post-build, on-agent-done, or
  pre-merge hook**. This matches and sharpens what the vault's "about Orca"
  note already said (in-app human diff review is the `done` gate, not an
  automated test gate) — it's not just that Orca *defaults* to human
  review, it structurally has nowhere else to hang an automated gate.
- **Hook script *content* is GUI-only.** `orca repo add`/`show`/`set-base-ref`/`search-refs`
  are the entire CLI surface for repos — none of them set `hookSettings`.
  `worktree create --setup run|skip|inherit` only controls whether an
  already-configured hook runs, not what it runs. So even the `setup`
  hook (the one lifecycle point that does exist) can't be wired up
  end-to-end from a script — it needs one manual step in Orca's Settings
  UI, same category as the `--yolo`-removal step the vault already flags
  for first-session setup. **This is a real ceiling on "headless,
  no-human-in-the-loop" wiring**, worth weighing directly against
  AgentOS's stated goal (`pilot/README.md`: "headless coding pipeline, no
  tmux, no permission nagging").
- **Orca *can* run headless**, which is a genuine positive finding worth
  weighing against the above: `orca serve --project-root <path>` starts a
  full runtime with no Electron GUI/display required (confirmed — killed
  the display-bound app process first, ran `orca serve` in the
  background, and the full CLI — `repo add`, `status`, etc. — worked
  against it identically). `~/.config/orca/orca-runtime.json` being stale
  (a dead pid) initially suggested Orca might be tied to a live GUI
  session; it isn't. This matters a lot for AgentOS: an unattended VM
  doesn't need a virtual display, just `orca serve` running as a daemon.
- Also confirmed: the CLI shim script lives at
  `~/.config/orca/linux-orca-cli-shim/orca`, **not on PATH by default**,
  and is a *different program* from `/usr/bin/orca` (the GNOME
  accessibility screen reader — real naming collision on Linux). Any
  script driving Orca needs the full shim path or `orca serve`'s own
  install step (`serve` auto-installed `orca`/`orca-ide` into
  `~/.local/bin` on this run, which would resolve the collision if that
  dir precedes `/usr/bin` on PATH — worth checking, not assumed).
- The CLI's `--agent <id>` list of "known ids" (`claude`, `codex`, `omp`,
  `pi`, `grok`) doesn't include `gemini` by name — the vault's original
  Orca setup note used Gemini CLI successfully, so presumably any
  installed TUI agent works via the same mechanism even if not in the
  "known ids" convenience list. Not verified this session (no worktree
  was actually created against a live agent) — worth confirming in step
  4/6 before assuming it "just works."

**Separately, getting the repo to build at all on this machine was its own
multi-step blocker**, unrelated to Orca but directly relevant to "Gemini
gets fast feedback" — a broken baseline gives fast feedback about nothing:

1. `global.json` pins SDK `10.0.400`; only Fedora's `dotnet-sdk-10.0`
   (`10.0.111`) and `8.0.130`/`9.0.120` were installed. `dotnet build`
   failed immediately with "SDK not found."
2. Retargeting to the installed `10.0.111` did resolve the SDK, but then
   failed with `CS9057` — Fedora's `dotnet-sdk-10.0` package is a
   source-rebuilt `10.0.111`, not Microsoft's official `10.0.400`, and its
   Roslyn (`5.0.0.0`) is too old for Cratis's analyzer packages (need
   `5.9.0.0`). **Fedora's dotnet package lags upstream enough to be
   incompatible with a current Cratis project** — not a one-off, this will
   hit again on any Fedora dev/CI box using the distro package.
3. Fixed by installing Microsoft's actual SDK 10.0.400 via
   `dot.net/v1/dotnet-install.sh` into a dedicated `~/.dotnet-official`
   (no sudo, doesn't touch the distro package). Reverted `global.json` to
   its original correct `10.0.400` pin (the pin was right all along; the
   environment was wrong).
4. Build then failed differently: Cratis's proxy-generator build task is
   itself a separate `net9.0` tool invoked *during* `dotnet build`,
   independent of the project's own TFM — needed the `Microsoft.NETCore.App`
   and `Microsoft.AspNetCore.App` 9.0 shared runtimes installed alongside
   the SDK. Added both via the same install script.
5. Build succeeded. Then, scaffolding the xUnit project (`CratisApp.Specs/`)
   as a subfolder of the repo root — where `CratisApp.csproj` also lives —
   caused `CratisApp.csproj`'s default SDK-style glob to **double-compile**
   the test files into the main app assembly (missing `xunit`/`Cratis.Specifications`
   references there, since those are the test project's packages). Fixed
   with an explicit `<Compile Remove="CratisApp.Specs/**/*.cs" />` in
   `CratisApp.csproj`. This is a general gotcha for any `.build-kit`-style
   automation scaffolding a test project alongside a Cratis app's
   single-project-at-repo-root layout — worth flagging in the constitution
   for whoever builds the tier-2 harness next, since the same trap applies
   to any generated folder living under the app root.
6. The vault's `cratis-conventions.md` skill doc names `Specification` as
   the xUnit spec base class from `Cratis.Specifications` — that package
   alone doesn't expose it; a separate `Cratis.Specifications.XUnit`
   package does. Added both.

**Files changed this step**: `global.json` (SDK pin, confirmed correct as
originally written — no net change), `CratisApp.csproj` (added `Compile
Remove` for the new test folder), new `CratisApp.Specs/` project (one real
spec against the existing placeholder `Register` command — not a fictional
expense-approval test, since that domain code doesn't exist yet), new
`.build-kit/hooks/tier01-gate.sh`.

**Running view on Orca's suitability, updated**: mixed, not negative. The
positive (headless `orca serve` works, no GUI/display dependency) is a
real point in favor of using it under AgentOS. The negative (no
post-build/completion hook exists at all, and even the one hook that does
exist needs a manual GUI step to configure) means the original plan's
framing of Orca as a place to "wire in" an automated gate needs revising —
the gate has to live in external orchestration around Orca's terminal
primitives (`terminal create`/`wait`/`read`), with Orca providing the
worktree/agent-session mechanics but not the gate itself. That's a
materially different integration shape than "post-build step," and it's
exactly the kind of thing this spike exists to surface before AgentOS
commits to Orca as the harness.

## Step 3 — Tier 2 skill build (2026-09-05)

Cloned `terryso/AutoQA-Agent` (the real `autoqa`, confirmed step 1) to read its actual discovery/plan
source rather than working from the README summary — `src/plan/explore.ts` +
`src/plan/orchestrator.ts` + `src/plan/types.ts`. Concretely: Phase 1 (`explore`) is a Claude Agent
SDK–driven Playwright session that crawls the running app, producing an `ExplorationGraph{pages,
edges}` (`PageNode` = one page, with `ElementSummary[]`/`FormInfo[]`/`links[]`; `NavigationEdge` = a
click/nav/submit between pages) written to `.autoqa/runs/<runId>/plan-explore/explore-graph.json`.
Phase 2 (`generateTestPlan`) reads that graph and produces `TestPlan{flows, cases: TestCasePlan[]}`,
each case written as a Markdown spec in a plain Preconditions/Steps shape (real example pulled from
the repo: `specs/saucedemo-01-login.md`).

**The core adaptation decision**: autoqa's whole discovery mechanism assumes there's a rendered UI to
crawl, and its implicit "did it work" signal is a DOM snapshot (something rendered). Neither premise
holds cleanly for a Cratis app — the real domain model lives in `.cs` slice files whether or not a
given slice has UI at all (see the shipped `Registration` slice's reactor, which is automation-only),
and a DOM snapshot proving something *rendered* is a materially weaker claim than proving the
underlying event was actually appended to Chronicle. So Phase 1 here reads the domain model directly
(parsing `[Command]`/`[EventType]`/`[ReadModel]`/`IReactor` shapes per `cratis-conventions.md`) instead
of crawling a browser, and Phase 2's cases always end in an event-store **witness** as the real
assertion, with a React snapshot demoted to informational-only (see rationale in
`witness-and-snapshot-patterns.md` — visual diffs have a much higher false-positive rate than a witness
query, so a snapshot mismatch alone shouldn't fail tier 2 if the witness passed).

**Correction found while writing the witness-query reference**: `docker-compose.yml` runs
`cratis/chronicle:latest-development` exposing port `27017` (Mongo's default), and
`CratisApp.csproj` references `Cratis.Arc.MongoDB` specifically. **This project's event store is
MongoDB, not Postgres** — Chronicle itself is storage-agnostic (Mongo/Postgres/SQL Server/SQLite per
the vault's Chronicle note), but this project picked Mongo, and the original spike plan's step 4
phrasing ("boot the Cratis app + Postgres") was wrong for this repo specifically. Fixed in
`CONSTITUTION.md`'s tier definitions. The exact witness query (which Mongo collection, what document
shape) is still unconfirmed — no live Chronicle instance has been booted yet in this spike (that's
step 4) — `witness-and-snapshot-patterns.md` documents this honestly as unverified rather than
fabricating a schema, with a fallback (Arc's generated read-model queries, which are documented/public)
usable in the meantime and a concrete action item for step 4 to nail down the raw event-log query.

**Demo run against the real repo** (`.build-kit/tier2/runs/2026-09-05-demo/`): ran both phases by
hand against the one real slice that exists (`Registration` + its sibling `Listing` read-model slice —
the domain code elsewhere is still template placeholder, so this is genuinely the only slice available
to discover). Worth noting because the demo run itself caught a real thing: `domain-graph.json`'s
`warnings[]` array flagged that `RegistrationReactor.Handle(Registered evt)` is missing the
`EventContext context` parameter `cratis-conventions.md` documents as the reactor method signature —
either a benign deviation (Cratis may resolve it via an optional/DI parameter) or a real drift between
the shipped starter code and the documented convention. Not fixed here (out of scope for a planning
skill to silently correct app code) — flagged for whoever next touches `Registration.cs`. This is
exactly the kind of value a discovery pass should produce even before step 4 runs anything.

Also surfaced while writing the reactor-edge test case: this repo has **no translation reactor yet**
(one that calls `ICommandPipeline.Execute(...)` in response to an event, per the "reactors issue
commands, not raw events" rule) — `RegistrationReactor` only logs. The Expense Tracker's own design
(`AutoApprovalReactor`) *is* exactly this shape once built, and T4-07 in the constitution exists
specifically to gate changes to it. `register-reactor-logs.md` documents this gap explicitly rather
than faking a translation-reactor example against code that doesn't exist.

**Files added**: `.claude/skills/tier2-scenario-planner/` (`SKILL.md` +
`references/domain-graph-schema.md` + `references/witness-and-snapshot-patterns.md`),
`.build-kit/tier2/runs/2026-09-05-demo/` (real discovery + plan output, 3 generated cases).

**Running view on Orca's suitability**: unchanged this step — step 3 never touched Orca, it's pure
Claude-skill/domain-parsing work. Next real signal comes in step 4, when the harness actually has to
boot the app + Mongo and run these cases for real, which is also where the unconfirmed witness-query
schema gets settled.

## Step 4 — Tier 2 execution harness (2026-09-05)

**First step to actually boot the real stack.** `docker compose up -d chronicle` pulled and started
`cratis/chronicle:latest-development` cleanly (single container, exposes gRPC-ish event-store port
`35000`, Mongo-compatible port `27017`, a REST/health port `8080`). `dotnet run` (using the
`~/.dotnet-official` SDK from step 2 — a bare `dotnet` would have failed the same way build did)
started the app and connected to Chronicle with no issues. No blockers this time — steps 1-2's
groundwork paid off.

**Nailed down the witness schema empirically, since step 3 correctly declined to guess it**:

- `pip install pymongo`, connected to `mongodb://localhost:27017` before starting the app: databases
  were `System+es`, `System+es+Default`, plus Mongo's own `admin`/`config`/`local`. **No `CratisApp`
  database existed yet** — it's created lazily on first use.
- After one real `POST /api/some-module/some-feature/registration {"name":"Ada Lovelace"}`: three new
  databases appeared — `CratisApp` (read models — `listings` collection, matching the `[ReadModel]
  Listing` type), `CratisApp+es` (event-type schema registry), `CratisApp+es+Default`
  (`event-log` collection — the actual raw event log; naming pattern `<EventStore>+es+<Namespace>`).
- Real `event-log` document shape confirmed (see full example now written into
  `witness-and-snapshot-patterns.md`): `type` = exact `[EventType]` name, `eventSourceId`,
  `content.<generation>.<field>` (camelCase field names, generation `"1"` for a never-evolved type —
  first read of a `System` event-log doc without content misread this as a per-field index; the real
  `Registered` doc corrected that).
- **The one real gotcha, worth its own line because it'll bite anyone who assumes otherwise**: the
  command's HTTP response (`{"response": "99046013-...", "isSuccess": true, ...}`) returned a
  **different Guid** than the event that actually landed in `event-log`
  (`eventSourceId: "a9426e5e-..."`) — not a formatting difference, a genuinely different value, on the
  exact same request. `cratis-conventions.md` documents `(Guid, EventName) Handle()` as returning the
  new id via `CommandResult<T>.response` — either that documentation doesn't hold for this return
  shape, or something else is going on that wasn't diagnosed further (out of scope to trace through
  Arc's source this session). **Practical consequence**: `run-tier2.sh`'s `witness_event()` matches on
  `type` + `content.1.<field>`, never on the command response id — confirmed this works reliably
  (`content.1.name` match found exactly 1 doc). Anyone writing a witness query who *does* join on the
  response id will get false negatives silently.
- **Read-model / event-log cross-check**: the `listings` read-model document's `_id` is a BSON Binary
  Guid — decoded, it equals the *event's* real `eventSourceId` (not the command response id either).
  This is a good sanity check for future witness-writing: the read model and the event log agree with
  each other on the true id; only the HTTP response disagrees with both.

**Built and ran the harness for real**: `.build-kit/tier2/start-stack.sh` (boot + wait-for-ready) and
`.build-kit/tier2/run-tier2.sh <run-dir>` (execute cases, write `report.json` + `evidence/*.json`).
Ran it against `.build-kit/tier2/runs/2026-09-05-demo/`:
```
{"pass": 2, "fail": 0, "skipped": 1}
```
`register-happy-path` and `listing-reflects-registration` both passed for real (real HTTP call, real
Mongo witness, real read-model cross-check — evidence files hold the actual matched documents).
`register-reactor-logs` skipped, honestly, per its spec's own "not automatable without log access"
note from step 3 — not faked as a pass.

**Orca angle**: step 2 already established there's no native post-build hook to "wire into." This
step's harness is exactly the artifact that gap requires — a self-contained script with a clean exit
code, meant to be invoked via `orca terminal create --command "..."` + `orca terminal wait --for exit`
inside a worktree. Didn't re-verify that specific invocation against a live Orca instance this step
(orca serve wasn't running during this step's work — steps 2 and 4 didn't overlap); that round-trip
belongs to step 6's integration run, where it matters more because a real agent-authored diff will be
the thing under test, not a hand-run demo.

**Running view on Orca's suitability**: unchanged again — step 4, like step 3, is Cratis/Chronicle
harness work, not Orca work. The Orca-specific open item (does `orca terminal wait --for exit` +
reading this script's exit code actually work as a gate, invoked from a real Orca worktree) is now
squarely step 6's job, not deferred further than that.

**Cleanup**: stopped the app process and `docker compose stop chronicle` after this step — the stack
isn't left running between spike sessions.

## Step 5 — Tier 3 adversarial pass (2026-09-05)

Built `.claude/skills/tier3-adversary/` — three attack classes from the original spike brief
(threshold bypass, negative amounts, concurrent-approval race), each grounded explicitly in one of
`CONSTITUTION.md`'s approval-gate invariants or T4 rules rather than a generic security checklist
(the skill's own instructions say so — "don't invent generic security-scanner checks, ground each
attack in an actual documented rule").

**Confirmed blocker, stated plainly rather than worked around**: all three real attack cases target
`SubmitExpense`/`ApproveExpense`/`RejectExpense`, none of which exist in this repo yet. Wrote them in
full in `references/pending-cases.md` — ready to run the moment that slice lands — rather than either
skipping step 5 entirely or faking results against code that isn't there. This is the same honesty
pattern as `register-reactor-logs.md` from step 3.

**What this step could do for real**: ran the adversarial stance against the one command that exists,
`Register`, against a live boot (Chronicle + app, same as steps 2/4). Real findings, not hypothetical:

- Empty string, whitespace-only, and a 10,000-character name were all accepted and durably recorded —
  confirms live what step 3's static `domain-graph.json` already predicted (`Register.hasValidator:
  false`).
- **A `<script>alert(1)</script>` payload landed verbatim in `event-log`'s `content.1.name`.** Not
  necessarily an active vulnerability (depends on how/whether any consumer renders it unescaped) but
  worth flagging structurally: Chronicle's event log is append-only, so a bad value here is permanent —
  it can be compensated with a later event but never edited or deleted. This matters more than a normal
  DB's "just fix the row" story would suggest.
- **A genuine platform-level gap, not an app bug**: sending `{"name": 12345}` (wrong JSON type) didn't
  produce a clean validation `400` the way a *missing* field did — it threw an unhandled exception
  inside Cratis's own `Cratis.Json.ConceptAsJsonConverter<T>.Read`: `'System.String' is not a supported
  underlying concept value type for a JSON number token.`, surfaced to the caller as a bare `500`. This
  will recur on *any* future `ConceptAs<string>` field across any slice, since it's in Cratis's
  deserialization path, not this project's code. Worth deciding whether to patch/wrap it centrally
  (a global exception filter mapping this specific exception to a `400`) before more slices exist,
  rather than rediscovering it per-slice.
- Fired many concurrent `Register` calls to at least partially probe the concurrency question the real
  `concurrent-approval-race` case needs — no corruption across *distinct* event sources, but this is a
  much weaker guarantee than "two commands racing the *same* `eventSourceId` can't both win," which
  genuinely cannot be tested without a DCB-guarded command. Documented as blocked, not worked around.

**Files added**: `.claude/skills/tier3-adversary/` (`SKILL.md` + `references/pending-cases.md`),
`.build-kit/tier3/runs/2026-09-05-demo/` (real adversarial evidence + `report.md`).

**Running view on Orca's suitability**: unchanged — step 5, like 3 and 4, is Cratis/Chronicle domain
work, not Orca work. No new signal on the harness question here.

## Step 6 — Integration run (2026-09-05, blocked)

User confirmed step 6's scope: have Gemini build the real approval-gate slice
(`SubmitExpense`/`ApproveExpense`/`RejectExpense`), then run the full tier 0–4 pipeline against that
diff — finally exercising the approval-gate-specific cases steps 3 and 5 could only write, not run.

**Hard blocker found before any code got written — this affects the spike's core premise, not just
this step.** `gemini -p "say ok"` hung indefinitely with the sandbox's network proxy (no output even
to stderr); outside the sandbox, it failed immediately with a real error:

```
IneligibleTierError: This client is no longer supported for Gemini Code Assist for individuals.
To continue using Gemini, please migrate to the Antigravity suite of products: https://antigravity.google
```

**Google has discontinued the free-tier personal-account OAuth path this Gemini CLI install
authenticates with** (`~/.gemini/oauth_creds.json` holds a real, valid-looking token — this is not an
auth-expired-token problem, it's the tier itself being retired). The vault's Orca setup note (`about
Orca (Worktree Agent GUI).md`) documents this exact OAuth flow as the intended way to drive Gemini
through Orca — that path no longer works, full stop, not just on this machine.

**What this means for the spike, not just step 6**: every step so far that named "Gemini" as the
execution agent (the whole tier 0–1 "Gemini gets fast feedback" framing, step 6's "real Gemini-built
change") assumed a Gemini CLI that can actually run. It can't, as currently configured. Two real paths
forward, neither exercised this session (both need the user's input — cost/product decisions, not
technical ones this session should make unilaterally):
1. **`GEMINI_API_KEY`** — a paid Gemini API key would bypass the retired free-tier OAuth path
   entirely (different auth mechanism, per Gemini CLI's own docs). Not set on this machine. Requires
   the user to get a key and accept the real per-token cost this spike's "Gemini is the cheap
   execution agent" framing assumed.
2. **Antigravity** — Google's suggested replacement, and Orca already has hook support for it
   (`~/.orca/agent-hooks/antigravity-hook.sh` exists, and `~/.gemini/antigravity-cli/settings.json`
   shows it's been used before, on the Minor-Working-Hour-Auditor project specifically — a real prior
   session, not a stub). No `antigravity` CLI binary found on `PATH` this session, so its current
   install state on this machine is unconfirmed — didn't chase further without the user's direction,
   since standing up a whole different product mid-spike is a scope decision, not a technical unblock.

**Also worth surfacing**: while checking `~/.gemini/oauth_creds.json` for a stale/expired token
(reasonable diagnostic step), its raw contents including a live OAuth access token were printed to this
session's output before realizing the actual failure was tier-eligibility, not staleness. Local to this
machine/session, low real risk, but flagged in the write-up to the user directly rather than left
implicit — reading a credential file's raw content should have been avoided in favor of a narrower
existence/expiry check.

**Resolved within the same session** — user confirmed they use Antigravity (`agy`), which turns out to
already be installed and authenticated on this machine (`~/.local/bin/agy`, v1.1.19; `agy -p "say ok"`
returns cleanly). The vault already had this fully documented
(`Agentic AI/Frameworks/about Antigravity CLI.md`): Gemini CLI's free/individual-account OAuth was
killed by Google on **2026-06-18**, `agy` is the intended replacement, and it's Orca's already-known
`agentDefaultArgs` entry for the `antigravity` agent — not a bolt-on. The vault note even names this
exact prior use case: "used as the coding-agent substitute for Gemini CLI in Minor Working Hour Auditor
once Gemini CLI's individual-account OAuth was killed mid-setup." This spike hit the identical wall
independently rather than checking the vault first — worth remembering to check
`Agentic AI/Frameworks/` for a tool's current status before assuming an older setup note (the Orca
setup brief's Gemini CLI instructions) is still accurate.

**Proceeding with step 6 using `agy` in place of `gemini`** — same role (cheap execution agent builds
the slice), different binary. Everything built in steps 1–5 (constitution, tier01-gate.sh,
tier2-scenario-planner, tier3-adversary) is agent-agnostic — none of it assumed a specific CLI, only
that *some* agent would produce a diff to run the pipeline against.

### `agy`'s first run wrote to the wrong repo entirely — a real harness-suitability finding

`agy -p "<build the slice>" --mode accept-edits` first failed outright: it tried to run `dotnet build`
and headless mode auto-denied the command-permission request (`--mode accept-edits` only covers file
edits, not shell commands). Retried with `--dangerously-skip-permissions` — Claude Code's own auto-mode
classifier blocked that (correctly: "run a nested agent with all permission checks off" is exactly the
class of action it should catch) — stopped and asked the user, who explicitly authorized it for this
one scoped run.

**On the authorized retry, `agy` silently built the entire slice inside a different, unrelated repo**:
`~/Code/DotNet/Projects/ExpenseTracking`, not `~/Code/DotNet/ExpenseTracker` (the directory it was
invoked from, `cd`'d into, with the prompt itself referencing this repo's own files). Root cause
diagnosed: `agy`'s headless/print mode doesn't scope to the invoking shell's `cwd` — it reattaches to
its own remembered **default project**, evidently set by an unrelated, much earlier session, unless
`--new-project` and/or `--add-dir <path>` are passed explicitly. Confirmed with a non-mutating sanity
check (`agy -p "pwd and ls" --add-dir "$(pwd)" --new-project` → correctly reported the intended
directory) before retrying the real build.

**Compounding discovery while investigating**: `~/Code/DotNet/Projects/ExpenseTracking` turned out to
be a *stale, orphaned clone of the same GitHub repo* (`Powerworks/ExpenseTracker`, same `origin`) sitting
one real, unpushed local commit (`cf86270`, 2026-08-18, "docs: default to CRUD/EF+Postgres, reserve
Cratis for event-sourced slices") ahead of what's on GitHub — a piece of the user's own prior work that
never made it to the remote, discovered only because `agy` happened to write into it. Confirmed
`origin/main` is still at the same commit (`fe76ecd`) the *correct* `ExpenseTracker` checkout is at, so
nothing here was actually lost — just sitting uncommitted-to-remote in a second, forgotten local
checkout. Left `ExpenseTracking` untouched (no commit/push/discard) — that repo and its orphaned commit
are the user's to deal with, out of scope for this spike to resolve unilaterally.

**Real, load-bearing harness-suitability finding, not a one-off mistake**: this is the second time in
this spike an agent orchestration surface silently operated somewhere other than where it was told to
(the first being APE's own installer/discovery bugs, though those were upstream code bugs, not a
session/state-scoping gap). For AgentOS, "an agent CLI reattaches to a remembered project instead of
the directory it was invoked in, with no visible warning" is a genuinely dangerous default for any
unattended pipeline — a scheduled worker that assumes `cwd` scoping could silently modify the wrong
repo on every run. **Any AgentOS wiring around `agy` must always pass `--new-project --add-dir <path>`
explicitly, never rely on `cwd` alone.**

**Recovered rather than re-running** (the misdirected run had already consumed real quota — see below):
copied only the new files (`Expenses/` folder, the `appsettings.json` diff) into the correct
`ExpenseTracker` checkout — purely additive, nothing overwritten or discarded in either repo — deleted
the copied `.g.cs`/`.ts` generated-proxy artifacts and let `dotnet build` regenerate them fresh in the
correct location. Independently verified: `dotnet build` clean (0 errors, the pre-existing
`StringTools` TFM warning only), 4 commands + 1 query discovered.

**`agy`'s free-tier quota is now exhausted** — the retry (correctly scoped this time) failed
immediately: `Error: Individual quota reached. ... Resets in 167h31m23s.` (~7 days). The first,
misdirected run burned the quota for nothing. **This closes off re-running `agy` for the rest of this
spike** — any further step needing a fresh agent-authored diff is blocked until the quota resets or a
paid key is configured. Worth flagging directly: free-tier quotas on both Gemini CLI's shutdown path
and now Antigravity's individual tier are real, practical constraints on this spike's "cheap execution
agent" premise, not edge cases.

### Reviewed the code `agy` actually produced — good on design, but functionally broken

Read all three slice files before trusting them. `SubmitExpense.cs`'s validator, `ApproveExpense.cs`'s
`PendingApproval` guard, and the `AutoApprovalReactor`'s `commands.Execute(new ApproveExpense(...))`
(never a raw `new ExpenseApproved(...)` — correctly follows the non-negotiable T4-07 rule) all read as
correct implementations of the locked design. Threshold comparator is strict `<` (an explicit answer to
the ambiguity `pending-cases.md`'s `threshold-boundary-comparator` case flagged in step 5).

**Confirmed the constitution's tier-4 rules actually fire on a real diff** — first real validation of
the whole rule set since step 1: `git diff` against this change hits T4-01 (`[EventType]` × 3),
T4-03 (`RequireApprovalGate`/`AutoApprovalThreshold`), and T4-05 (`CommandValidator` added). T4-07's
guard held (no raw event write in the reactor, confirmed by direct code read, not just pattern-match).

Ran `tier01-gate.sh` (step 2) against the real diff: clean pass, build + xUnit both green.

**Then ran the real approval-gate tier-2/tier-3 cases from `pending-cases.md` (step 5) for the first
time ever** — booted Chronicle + the app, submitted expenses at the threshold boundary
(`99.99`/`100.00`/`100.01`), fired the negative-amount and zero-amount cases, and ran both the
sequential-double-approve and concurrent-approval-race cases. Result, and this is the headline finding
of the whole spike so far:

**`ExpenseApproved` was never appended to the event log — not once, by any path.** Confirmed by
querying the full event log after all cases ran: `event-log`'s distinct `type` values were only
`['ExpenseSubmitted', 'Registered']` — zero `ExpenseApproved`, zero `ExpenseRejected`, across:
- The `AutoApprovalReactor`, which should have auto-approved every submission under the `100.00`
  threshold (the `99.99` case, and the very first ad-hoc `50.00` submission) — the read model for both
  stayed `"PendingApproval"` (`expenseStatuses` collection, `CratisApp` database — checked directly).
- Two explicit human `ApproveExpense` calls (the sequential-double-approve case's first call, and both
  legs of the concurrent-race case) — **all of which reported `isSuccess: true`, no exceptions,** yet
  produced no event and no read-model state change. The command claims success while doing nothing.

This makes the adversarial cases' own pass/fail readouts uninterpretable as designed — `PASS_second_
rejected: false` isn't evidence of a race-condition bug, because there's no evidence the *first* call
did anything either. **The real finding underneath all of them is more fundamental: `ApproveExpense`
doesn't work at all, and reports success while not working**, which is a worse failure mode than a
clean rejection would be — a caller (human or the reactor) has no way to know the approval silently
no-op'd.

**Root cause not diagnosed** — checked app logs (no exceptions logged around the approve calls, no
reactor-related log lines at all, though the reactor has no explicit logging to check against),
confirmed the read model itself does update correctly for `ExpenseSubmitted` (its `PendingApproval`
initial state is real, current, and queryable), so the read-model plumbing works one direction but not
the other. Plausible causes, none confirmed: something about combining `[Key] Guid ExpenseId` with a
`Result<TSuccess, TError>` return shape doesn't wire the emitted event's target `eventSourceId` the way
`(Guid, Event)` tuple-shaped `Handle()` methods (like `Register`'s) do; or a DCB read-model parameter
staleness issue where `Handle()` evaluates against a not-yet-caught-up projection every time,
independent of any real concurrency race. Deliberately stopped debugging Cratis/Arc internals further
here rather than open-endedly chasing it — this is squarely the "expect this step to reveal rework
needed in 3–4" outcome the original plan predicted, just discovered at the platform/wiring layer rather
than in the constitution's rules themselves.

**This diff does not pass tier 2 (the happy-path witness for `ApproveExpense` fails) and cannot be
meaningfully adversarial-tested at tier 3 until that's fixed — recommend it not proceed toward tier 4
sign-off as-is.**

**Running view on Orca's suitability**: still no new signal — this step never touched Orca (used `agy`
directly, not through an Orca-managed worktree). The `agy` project-scoping bug is a finding about
Antigravity specifically, not Orca; worth carrying into the AgentOS decision regardless of which
orchestrator sits on top, since Orca would be invoking the same `agy` binary the same way.

## Step 6 addendum — root-causing the silent-approval bug (2026-09-05)

User asked to troubleshoot properly rather than accept "diff doesn't pass tier 2, cause undiagnosed."
Full root-cause investigation, documented in order since each ruled-out hypothesis is itself useful
evidence for whoever debugs a similar Cratis issue later.

**Method**: added temporary `Console.Error.WriteLine` diagnostics directly inside `ApproveExpense
.Handle()`, rebuilt, and issued real HTTP calls against a live boot — watching exactly what `current`
(the DCB read-model parameter) received, not just the HTTP response.

1. **First real signal**: `ApproveExpense`'s response for a call that hit the guard branch was
   `{"response": "Expense is not pending approval", "isSuccess": true, ...}` — **`isSuccess: true` even
   though `Handle()` returned the `Result<,>` error branch.** This is itself a significant, independent
   finding: Arc's `isSuccess` flag reflects only whether the command pipeline executed without an
   unhandled exception, **not** whether a `Result<TSuccess, TError>` command actually succeeded — the
   real outcome has to be read out of `response`'s shape (a Guid/object vs. a bare string). Any caller
   (a future UI, an automation) that branches on `isSuccess` alone to decide whether an approval went
   through will be silently wrong. Worth its own line in the constitution or a shared client
   convention, independent of the bug below.
2. **The DCB parameter (`current`) was `NULL` on every call** — both the reactor's auto-approval
   attempt and explicit human calls, every time, with no exception anywhere in the app log.
3. **Ruled out timing/replication lag**: confirmed via direct Mongo query that the `expenseStatuses`
   projection document existed, correctly keyed (`__subject` == the real `eventSourceId`, confirmed by
   decoding the BSON Binary `_id`), with `status: "PendingApproval"`, *before* issuing the approve call.
   Retested with an 18-second gap between submit and approve — still `NULL`. Not a staleness problem.
4. **Ruled out the `[Key]` attribute ambiguity** (a real, separate gotcha worth recording on its own):
   there are two different `[Key]` attributes in this codebase's dependency graph —
   `System.ComponentModel.DataAnnotations.KeyAttribute` (what Arc's own core XML docs describe reading
   for command key resolution) and `Cratis.Chronicle.Keys.KeyAttribute` (what Antigravity actually
   imported and used, to satisfy Chronicle's own analyzer). Swapping `ApproveExpense`'s `[Key]` to the
   DataAnnotations one **failed the build outright** — analyzer rule `ARCCHR0008` fired with an explicit,
   named explanation: *"Chronicle resolves keys from Cratis.Chronicle.Keys.KeyAttribute, so it will
   resolve a new event source id for every 'ApproveExpense' and every read model keyed by it will
   resolve to nothing. Use Cratis.Chronicle.Keys.KeyAttribute instead."* — confirming Antigravity's
   original choice was correct all along, and ruling out this entire line of hypothesis.
5. **Ruled out query-method registration**: added a static `GetById` query method to `ExpenseStatus`
   (none existed — unlike every read model in the conventions doc's examples) — build's own discovery
   count went from "1 query" to "2 queries," confirming the addition registered, but `current` was
   still `NULL` afterward.
6. **Isolated the read model entirely**: built a minimal, throwaway diagnostic command
   (`DiagDcbTest([Key] Guid Id) { Handle(Listing? current) }`) against `Listing` — the pre-existing,
   independently-verified-populated read model from the original starter slice, nothing to do with
   Antigravity's code at all. **Still `NULL`.** This is the decisive step: proves the bug is not in
   `ExpenseStatus`, not in anything Antigravity wrote, but in DCB read-model resolution generally, for
   this project, full stop. (Placing the diagnostic command inside `Registration/`'s own folder first
   silently broke that slice's routing — Arc's route generation collapses commands sharing a folder to
   the same path, downgrading `Register`'s endpoint to `405 Method Not Allowed`. Moved the diagnostic to
   its own folder and the collision went away — a real, if narrower, gotcha about the folder-per-slice
   convention worth remembering for anyone scaffolding throwaway diagnostics the same way.)
7. **Checked for a version-skew explanation** — a real, live possibility given
   `docker-compose.yml` runs `cratis/chronicle:latest-development` (floating to whatever's newest) and
   the NuGet client resolves to a fixed `Cratis.Chronicle` **16.39.1**, while the running server printed
   **"Version 16.44.2.0"** at startup — a real 9-release gap. Found `github.com/Cratis/Arc` issue #2587
   ("Commands can inject a read model Chronicle refuses to resolve, and it only fails in production")
   describing an adjacent but not identical failure mode (that one throws `UnknownReadModel`; ours
   throws nothing), and an open PR (#2644) bumping the client to 16.44.2 across a changelog that
   includes at least one confirmed "silent failure, nothing thrown, nothing logged" bug class elsewhere
   (a reactor dispatch bug, Chronicle 16.40.0). Pulled `cratis/chronicle:16.39.1-development` (a
   version-pinned tag exists on Docker Hub) to match the client exactly and re-ran the identical
   `DiagDcbTest` against `Listing` — **still `NULL`, byte-for-byte identical failure.** Version skew
   ruled out definitively.
8. **Checked the vault's own prior guidance**: `Arc ASP.NET Core Configuration.md` states explicitly —
   written before this spike even started — *"This is the point where the Expense Tracker design's
   Cratis backend would call `WithChronicle()` — everything else in that project's Design section
   (commands, reactors, read models) assumes Chronicle is wired in here."* `Program.cs` never calls it
   (only `.WithMongoDB()`). Added `arcBuilder.WithChronicle()` — hit an overload ambiguity between
   `Cratis.Arc.ArcBuilderExtensions.WithChronicle` (`Cratis.Arc.Chronicle` package) and
   `Microsoft.AspNetCore.Builder.ArcBuilderExtensions.WithChronicle` (`Cratis.Chronicle.AspNetCore`
   package) — picked the AspNetCore one to disambiguate, rebuilt cleanly, retested. **Still `NULL`.**
   Then read the *other* overload's own XML doc more carefully: *"Call this... when you want event
   sourcing but are wiring authentication yourself. `AddCratis` composes it for you as part of the
   all-in-one setup."* — meaning `Program.cs`'s existing `builder.AddCratis(...)` call should already
   include Chronicle wiring, and the general Chronicle features clearly do work (commands append events
   correctly, `AllListings`'s observable query works) — so this wasn't actually the missing piece,
   and the overload picked was likely the wrong, redundant one for this setup shape. Reverted.
9. **Definitive isolation**: extended the diagnostic command to inject
   `IEnumerable<Cratis.Arc.Queries.ICanResolveReadModelForCommand>` directly and log what's registered.
   **Result: `resolvers=[]` — completely empty.** No Chronicle resolver, no MongoDB fallback resolver,
   nothing. This is the real, provable root cause: the DI container has zero implementations of the
   interface that's supposed to answer "given a command's key, find its read model," which is why
   *every* DCB read-model parameter in this application resolves to `null` unconditionally, independent
   of read model shape, `[Key]` attribute choice, or Chronicle/client version.
10. Traced one level further: `Cratis.Arc.Chronicle`'s `ReadModelServiceCollectionExtensions
    .AddReadModels(IServiceCollection, IClientArtifactsProvider)` is the method that's supposed to
    populate this — its own XML doc confirms it's exactly "read model auto-discovery and registration"
    for command-scoped resolution — but nothing in this project's `Program.cs`/`AddCratis`/`WithMongoDB`
    call chain appears to invoke it. Whether that's a genuine bug in how `AddCratis` composes for a
    Mongo-backed setup, or an undocumented extra call the application is expected to make explicitly,
    wasn't resolved within this session's remaining scope — this is the concrete, actionable next step
    for whoever picks this up (start from `AddReadModels`'s call sites in `Cratis.Arc.Chronicle`'s
    source, not from more trial and error against the public fluent API surface).

**Conclusion**: this is a genuine platform/project-setup gap, not an Antigravity code-quality problem.
Every line of code Antigravity wrote (validator, guard, reactor discipline, threshold comparator) reads
as correct — the diff simply exercises a Cratis wiring capability (DCB read-model injection into
commands) that nothing before this spike had ever turned on, because the shipped starter's only
existing slice (`Registration`) never used it. Tier 2 was right to catch this and right to block tier 4
— the finding is real, reproducible with a 15-line minimal case, and would have shipped completely
silently (`isSuccess: true`, HTTP 200, no logs) had this session accepted the first read of "isSuccess
true" as "it worked."

**All diagnostic scaffolding removed** after concluding (`DiagDcbTest` deleted, `Console.Error
.WriteLine` calls removed from `ApproveExpense.cs`, `Program.cs` and `ApproveExpense.cs` reverted to
their pre-diagnostic state) — the `Expenses/` diff in this repo is exactly what Antigravity produced,
unmodified, so the finding above is reproducible against it as-is.

**Filed upstream**: [Cratis/Arc#2645](https://github.com/Cratis/Arc/issues/2645) — full repro, the
ruled-out-hypothesis list above, and the expected-behavior ask. Hit a real tooling snag getting there:
`gh auth status` reported an invalid token inside this session's sandboxed Bash tool even right after
the user completed an interactive `gh auth login -h github.com -w` — turned out the sandbox was
blocking access to the OS keyring where `gh` actually stores the token (login uses keyring storage, not
a plain credentials file); the same `gh auth status` call succeeded immediately once run with the
sandbox disabled. Worth remembering for any future `gh`-dependent step in this or other spikes.

## Step 8 — Orca worktree gating follow-up (2026-09-06)

The report's own recommendation: the one thing this whole spike never actually tested was gating an
agent's diff **through a live Orca-managed worktree**, end to end. Every prior step drove `agy`
directly. This step does the real thing.

**Setup**: the leftover `orca serve` process from step 2 (never actually killed — `pkill -f "orca
serve"` missed it because the running process is titled `orca-ide --serve` under the AppImage mount,
not `orca serve`) turned out to still be alive and healthy days later, with `ExpenseTracker` already
registered as a repo from that same step. No restart needed.

**Created a real worktree with a real agent**: `orca worktree create --repo id:... --name
orca-gate-test --agent claude --prompt "<small, safe task>"` — asked it to fix the recurring
`Microsoft.NET.StringTools`/net9.0 build warning this whole spike has seen in every `dotnet build`
output, by adding `<SuppressTfmSupportBuildWarnings>true</SuppressTfmSupportBuildWarnings>` to
`CratisApp.csproj`. Chose a trivial, safe, verifiable task deliberately — the point was testing the
gating *mechanism*, not building a feature.

**Real finding, immediately**: the agent's terminal came up and sat at Claude Code's own first-run
trust prompt (`❯ No, exit` selected by default), then a second prompt approving the repo's `.mcp.json`
MCP server — both genuinely interactive, both would silently stall an unattended pipeline. Sending
navigation keystrokes to a terminal driving another agent got auto-blocked by Claude Code's own
auto-mode classifier as too opaque an action to wave through unilaterally (a correct call) — stopped
and asked the user, who authorized it for this one worktree terminal. Sent arrow-up + enter to accept
the trust prompt, then enter to accept the MCP prompt's own safe default ("continue without using this
MCP server"). This alone is a real, on-topic result: **an Orca-driven Claude Code agent is not
unattended by default** — first-run trust and per-project MCP approval both need a human (or a
pre-seeded config) in the loop, at least once per fresh workspace.

Once past both prompts, the agent did the task correctly and quickly (~30s): read the file, made the
one-line edit, ran the build itself, confirmed 0 warnings/0 errors, stopped. Exactly right.

**The actual test — gating the resulting diff**:
1. `orca terminal create --worktree <the new worktree> --command "... bash .build-kit/hooks/tier01-gate.sh; echo GATE_EXIT_CODE=$?"`, then `orca terminal wait --for exit` — **timed out**. Real finding:
   `--for exit` waits for the **terminal's shell process** to exit, not for a command run inside a
   persistent interactive shell to finish — the gate script completed successfully (visible via
   `terminal read`, `GATE_EXIT_CODE=0` printed) but the shell itself stayed open at its prompt
   afterward, so nothing ever "exited."
2. Fixed by appending `; exit $?` to the command instead of just letting it print the code — re-ran,
   `terminal wait --for exit` returned cleanly: `{"status": "exited", "exitCode": 0}`.
3. Verified the failure path isn't just assumed symmetric: a throwaway `exit 1` terminal in the same
   worktree returned `{"status": "exited", "exitCode": 1}` through the identical wait call.

**This is the proof the spike was missing.** The exact pattern `CONSTITUTION.md` (step 2) and
`spike-log.md` (steps 4, 6) proposed as the answer to "Orca has no native post-build hook" —
external orchestration via `terminal create` + `terminal wait --for exit`, reading the exit code as
the gate signal — genuinely works, real repo, real agent, real diff, real pass and real fail both
confirmed. The one correction to carry forward: **always end the gated command with `exit $?`**, never
rely on the command's own exit code propagating through an interactive shell on its own.

**Left in place, not cleaned up**: the worktree at
`~/orca/workspaces/ExpenseTracker/orca-gate-test` (branch `Powerworks/orca-gate-test`) still holds the
real, uncommitted `CratisApp.csproj` fix — a genuinely useful small change, left for deliberate
review/merge/discard rather than committed or discarded unilaterally as a side effect of this test.

**Running view on Orca's suitability, final update**: upgraded from "promising, not yet provable" to
**provable, with two concrete caveats now on record** — (1) first-run trust/MCP prompts need handling
before any of this can run truly unattended (a one-time per-workspace setup cost, not a per-run one),
and (2) the exit-code-gating pattern needs the `exit $?` discipline called out above. Neither is a
blocker; both are exactly the kind of finding a spike like this exists to produce before AgentOS
commits real infrastructure to the pattern.

## Step 7 — Report findings (2026-09-05)

Published a synthesized report, not just this raw log: **https://claude.ai/code/artifact/8d06eccd-8a59-4167-b71c-eeb84a297429**
("Harness Spike Report") — TL;DR verdict, a 7-step status strip, what worked / what broke, the
10-step root-cause elimination for the Cratis DI bug, the Orca-specific finding table, open questions,
and a recommendation for the AgentOS foundation decision. Written for the Dilger conversation and the
AgentOS decision per the original brief — this log and `CONSTITUTION.md` remain the full detail behind
it.

**One-paragraph summary of the whole spike**: every piece of tooling built this week (constitution,
tier01-gate.sh, tier2-scenario-planner, tier3-adversary) works as designed against a real live stack —
the thing that didn't work was the approval-gate slice itself, and not because of the build agent's
code quality, but because of a genuine Cratis platform bug (DCB read-model resolver never registered in
DI for a Mongo-backed setup) now filed and reproducible as Cratis/Arc#2645. Orca's verdict is
"promising, not yet provable" — its headless mode is a real, unexpected point in its favor, but the one
thing that would actually prove it (an agent's diff gated end-to-end through a live Orca worktree) was
never exercised, since every command this spike ran went through `agy` directly rather than through an
Orca-managed session. That's the concrete next spike, not a restart of this one.

