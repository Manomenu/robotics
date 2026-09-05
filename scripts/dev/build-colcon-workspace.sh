#!/usr/bin/env bash
# HOST. colcon build workspace'u repo, bez wchodzenia do kontenera.
# Pisze tylko w repo (ws/build, ws/install, ws/log). Cofa: build-colcon-workspace-revert.sh
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/container.sh"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# run-in-ros2-container używa exec, więc po nim nic się już nie wykona —
# podpowiedź musi pójść przed budowaniem.
cat <<'NEXT'
Po udanym budowaniu, w powłoce z scripts/ros2/enter-ros2-container.sh:
  ros2 run <pakiet> <węzeł>
Podgląd z Fedory: scripts/ros2/list-running-nodes.sh

NEXT

run-in-ros2-container "cd '$REPO/ws' && colcon build --symlink-install"
