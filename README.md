# Expense Tracker

A small-company expense-tracking app: photograph a receipt, submit the
expense, route it through an approval workflow (manual or auto-approved
under policy), pay it out.

Event-sourced on [Cratis](https://www.cratis.io) (event store: Chronicle),
modeled [Event-Model-first](https://eventmodeling.org) — a fully elaborated
board (commands/events/views, Given/When/Then) before implementation — using
[eventmodelers.ai](https://app.eventmodelers.ai) for both modeling and the
agentic build loop. See [`Project Plan/01-project-plan.md`](Project%20Plan/01-project-plan.md)
for scope, phasing, and the full modeling/build workflow.

**Status:** skeleton stage — backend scaffold builds green, board modeling
not started yet. Nothing domain-specific built.

## Stack

- **Backend:** .NET / [Cratis Arc](https://www.cratis.io/docs/Arc/) (CQRS)
  + [Chronicle](https://www.cratis.io/docs/Chronicle/) (event sourcing),
  single project (`CratisApp.csproj`) — one bounded context (`Expenses`) for
  v1, vertical-slice-per-feature rather than layered
- **Web client:** React, co-located per-slice under each module/feature
  folder (`.frontend/` shell), PrimeReact, TypeScript command/query proxies
  auto-generated from the backend on `dotnet build`
- **Mobile client:** React Native ([Expo](https://expo.dev), TypeScript) —
  `clients/mobile` — targeting Android; consumes the same REST/Swagger API
  by hand, since Cratis's proxy generation is web-only
- **Build tooling:** [`@eventmodelers/cli`](https://app.eventmodelers.ai/documentation),
  `cratis-csharp` stack — not GitHub's spec-kit

## Getting started

Prerequisites: .NET 10 SDK (a genuinely current one — see note below),
Docker + Docker Compose, Node.js 20+, npm.

```bash
# 1. Infrastructure — Chronicle (event store) + Aspire Dashboard
docker-compose up -d

# 2. Backend
dotnet build
dotnet run

# 3. Web frontend (separate terminal, repo root)
npm install
npm run dev

# 4. Mobile
cd clients/mobile
npm install
npx expo start
```

- Backend API: http://localhost:5000 (Swagger: `/swagger`)
- Web frontend (Vite dev server): http://localhost:5173
- Aspire Dashboard: http://localhost:18888

### A packaged-SDK gotcha, if `dotnet build` fails with `CS9057`

Some Linux distro packages of the .NET 10 SDK lag Microsoft's actual latest
release badly enough that their bundled Roslyn can't load Cratis's source
generators. If you hit `CS9057` analyzer-version errors, install the current
SDK directly rather than via your distro's package manager:

```bash
curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
chmod +x /tmp/dotnet-install.sh
/tmp/dotnet-install.sh --channel 10.0 --install-dir ~/.dotnet
/tmp/dotnet-install.sh --channel 9.0 --runtime dotnet --install-dir ~/.dotnet
/tmp/dotnet-install.sh --channel 9.0 --runtime aspnetcore --install-dir ~/.dotnet
export PATH="$HOME/.dotnet:$PATH"
```

This repo's `global.json` pins the SDK version so `dotnet` resolves to a
matching install once one is on `PATH`. The extra .NET/ASP.NET Core 9.0
runtimes are for the post-build TypeScript proxy generator, which
reflection-loads the compiled app and therefore needs its shared frameworks
present even though the SDK itself is 10.x.

## Project structure

```
CratisApp.csproj, Program.cs, ...   - .NET backend entry point + project file
.frontend/                          - Web frontend shell (Vite + React root)
<Module>/<Feature>/                 - A vertical slice: backend + frontend
                                       code side by side
  <Feature>.tsx                     - React composition page
  <Slice>/<Slice>.cs                - Command/event/query backend code
  <Slice>/<Slice>.ts                - Generated TS proxy (do not hand-edit)
SomeModule/SomeFeature/             - The kit's own reference example slice —
                                       not real domain code, left in place as
                                       a convention reference for future
                                       slices (see .claude/skills/)
clients/mobile/                     - React Native (Expo) app
Project Plan/                       - Planning docs
.build-kit/, .claude/skills/        - eventmodelers build kit + Claude Code
                                       skills (build-state-change,
                                       build-state-view, build-automation)
```

## License

MIT — see [LICENSE](LICENSE).
