#!/usr/bin/env bash
# Usuwa środowisko robotyczne z maszyny. Kod i notatki zostają.
#   --hard  dodatkowo kasuje obrazy podmana i śmieci ROS-a we współdzielonym $HOME
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

distrobox rm --force ros2 2>/dev/null || true
rm -rf "$REPO/ws/build" "$REPO/ws/install" "$REPO/ws/log"

if [ "${1:-}" = "--hard" ]; then
  podman image prune -af
  # katalog domowy jest współdzielony, więc ROS zostawia tu swoje ślady:
  rm -rf ~/.ros ~/.colcon
fi

echo "Usunięte. Zostało jeszcze:"
echo "  - pakiet 'distrobox' w ~/.dotfiles/fedora/nix/home.nix"
echo "  - repo $REPO"
