#!/usr/bin/env bash
# HOST. colcon build workspace'u repo, bez wchodzenia do kontenera.
# Pisze tylko w repo (ws/build, ws/install, ws/log). Cofa: build-colcon-workspace-revert.sh
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/container.sh"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
run-in-ros2-container "cd '$REPO/ws' && colcon build --symlink-install"

cat <<'NEXT'

Dalej:

  scripts/dev/ros2/enter-ros2-container.sh   a w środku:  ros2 run <pakiet> <węzeł>
  scripts/dev/ros2/list-running-nodes.sh     podgląd z Fedory, gdy już chodzi
NEXT
