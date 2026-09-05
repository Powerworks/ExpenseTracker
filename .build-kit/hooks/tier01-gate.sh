#!/usr/bin/env bash
# Tier 0-1 gate for the Orca/APE/autoqa harness-eval spike (spike-log.md).
#
# Paste this in as the Orca repo's "setup" hook (Settings > repo > Hooks in
# the Orca app — no CLI command sets hook script content, only whether a
# configured one runs via `worktree create --setup run|skip|inherit`).
#
# Two real, load-bearing gotchas found wiring this up 2026-09-05, both from
# this exact machine/repo combination, not generic advice:
#
# 1. Fedora's `dnf install dotnet-sdk-10.0` is a source-rebuilt 10.0.111,
#    NOT Microsoft's official 10.0.400 this repo's global.json pins — its
#    Roslyn (5.0.0.0) is too old for Cratis's analyzer packages (need
#    5.9.0.0), so the build fails with CS9057 before a single line of this
#    project's own code is even checked. Must use Microsoft's own SDK.
# 2. The SDK-only install doesn't include the .NET 9 runtime Cratis's
#    proxy-generator build task needs (it's a separate net9.0 tool that
#    runs during `dotnet build`, independent of this project's own TFM) —
#    needs the netcore + aspnetcore 9.0 shared runtimes installed alongside.
#
# Both are handled by installing into a dedicated, non-distro directory
# once and pointing PATH/DOTNET_ROOT at it, rather than depending on
# whatever `dotnet` a fresh worktree's environment happens to resolve to.

set -euo pipefail

DOTNET_INSTALL_DIR="${DOTNET_INSTALL_DIR:-$HOME/.dotnet-official}"

if [ ! -x "$DOTNET_INSTALL_DIR/dotnet" ]; then
  echo "Installing .NET SDK 10.0.400 + 9.0 shared runtimes to $DOTNET_INSTALL_DIR..." >&2
  curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
  bash /tmp/dotnet-install.sh --version 10.0.400 --install-dir "$DOTNET_INSTALL_DIR"
  bash /tmp/dotnet-install.sh --channel 9.0 --runtime dotnet --install-dir "$DOTNET_INSTALL_DIR"
  bash /tmp/dotnet-install.sh --channel 9.0 --runtime aspnetcore --install-dir "$DOTNET_INSTALL_DIR"
fi

export PATH="$DOTNET_INSTALL_DIR:$PATH"
export DOTNET_ROOT="$DOTNET_INSTALL_DIR"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

echo "== Tier 0: APE scan (agent-config risk only — see CONSTITUTION.md for why) ==" >&2
if command -v ape >/dev/null 2>&1; then
  ape scan . --output-json "$REPO_ROOT/.build-kit/hooks/.last-ape-scan.json" || {
    echo "APE flagged HIGH/CRITICAL findings — see .last-ape-scan.json. Not currently a hard gate (see spike-log.md false-positive notes on package.json); review, don't auto-fail on this alone yet." >&2
  }
else
  echo "ape not installed — skipping tier 0 (see spike-log.md for install-from-source steps; not on PyPI)." >&2
fi

echo "== Tier 1: build (warnings-as-errors) ==" >&2
dotnet build CratisApp.csproj

echo "== Tier 1: xUnit / Cratis.Specifications ==" >&2
dotnet test CratisApp.Specs/CratisApp.Specs.csproj

echo "Tier 0-1 gate passed." >&2
