#!/usr/bin/env bash
# HOST. Cofa install-distrobox.sh.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/container.sh"

if podman container exists "$CONTAINER" 2>/dev/null; then
  echo "Kontener $CONTAINER wciąż istnieje — najpierw create-container-for-ros2-revert.sh" >&2
  exit 1
fi

sudo dnf remove -y distrobox
echo "-> distrobox usunięty"
