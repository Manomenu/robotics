#!/usr/bin/env bash
# HOST. Cofa install-devcontainer-cli.sh.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/container.sh"
refuse-inside-container

if podman container exists "$CONTAINER" 2>/dev/null; then
  echo "Kontener $CONTAINER wciąż istnieje — najpierw create-devcontainer-revert.sh" >&2
  exit 1
fi

npm uninstall -g @devcontainers/cli 2>/dev/null && echo "-> devcontainer CLI usunięty" || echo "-> nie było go"
