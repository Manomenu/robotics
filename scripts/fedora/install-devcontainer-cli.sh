#!/usr/bin/env bash
# HOST. Instaluje `devcontainer` CLI (globalnie w npm).
#
# Po co, skoro VS Code potrafi postawić kontener klikiem: bo klik nie jest
# skryptem. Z CLI środowisko stawia się z Ghostty, da się je odtworzyć na
# innej maszynie i da się je zrewertować — czego kliknięcie nie oferuje.
# Cofa: install-devcontainer-cli-revert.sh
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/container.sh"
refuse-inside-container

command -v npm >/dev/null 2>&1 || { echo "brak npm (nvm) — zainstaluj node zanim pójdziesz dalej" >&2; exit 1; }

if command -v devcontainer >/dev/null 2>&1; then
  echo "-> devcontainer już jest ($(command -v devcontainer))"
else
  npm install -g @devcontainers/cli
  echo "-> devcontainer CLI zainstalowany"
fi

cat <<'NEXT'

Dalej:

  scripts/container/create-devcontainer.sh   kontener z ROS 2 Jazzy
NEXT
