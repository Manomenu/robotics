#!/usr/bin/env bash
# HOST. Instaluje distroboxa na Fedorze.
# Cofa: install-distrobox-revert.sh
set -euo pipefail

if command -v distrobox >/dev/null 2>&1; then
  echo "-> distrobox już jest ($(command -v distrobox))"
else
  sudo dnf install -y distrobox
  echo "-> distrobox zainstalowany"
fi

cat <<'NEXT'

Dalej:

  scripts/container/create-container-for-ros2.sh   pusty kontener ros2 (sekundy)
NEXT
