#!/usr/bin/env bash
# HOST. Cofa install-distrobox.sh.
set -euo pipefail

if podman container exists ros2 2>/dev/null; then
  echo "Kontener ros2 wciąż istnieje — najpierw create-container-for-ros2-revert.sh" >&2
  exit 1
fi

sudo dnf remove -y distrobox
echo "-> distrobox usunięty"
