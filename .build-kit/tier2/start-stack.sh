#!/usr/bin/env bash
# Boots Chronicle + the CratisApp, waits for readiness, then hands off to
# run-tier2.sh. Wraps dotnet with the ~/.dotnet-official SDK install from
# step 2 (tier01-gate.sh) rather than assuming a bare `dotnet` on PATH
# resolves to something that can actually build this project — see
# spike-log.md step 2 for why that assumption failed here.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOTNET_INSTALL_DIR="${DOTNET_INSTALL_DIR:-$HOME/.dotnet-official}"
export PATH="$DOTNET_INSTALL_DIR:$PATH"
export DOTNET_ROOT="$DOTNET_INSTALL_DIR"
APP_URL="${APP_URL:-http://localhost:5266}"

cd "$REPO_ROOT"

echo "Starting Chronicle..." >&2
docker compose up -d chronicle

echo "Waiting for Chronicle (localhost:35000)..." >&2
for _ in $(seq 1 30); do
  if (echo > "/dev/tcp/localhost/35000") 2>/dev/null; then break; fi
  sleep 1
done

echo "Starting CratisApp..." >&2
dotnet run --no-launch-profile --urls "$APP_URL" > "$REPO_ROOT/.build-kit/tier2/app.log" 2>&1 &
APP_PID=$!
echo "$APP_PID" > "$REPO_ROOT/.build-kit/tier2/app.pid"

echo "Waiting for CratisApp ($APP_URL)..." >&2
for _ in $(seq 1 30); do
  if curl -s -o /dev/null "$APP_URL/.cratis/queries/health"; then break; fi
  sleep 1
done

echo "Stack ready. App pid $APP_PID (see app.pid). Run:" >&2
echo "  .build-kit/tier2/run-tier2.sh <run-dir>" >&2
echo "Tear down with:" >&2
echo "  kill \$(cat .build-kit/tier2/app.pid); docker compose stop chronicle" >&2
