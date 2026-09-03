#!/usr/bin/env bash
# HOST. Instaluje distroboxa na Fedorze.
# Cofa: install-distrobox-revert.sh
set -euo pipefail

if command -v distrobox >/dev/null 2>&1; then
  echo "-> distrobox już jest ($(command -v distrobox))"
  exit 0
fi

sudo dnf install -y distrobox
echo "-> distrobox zainstalowany"
