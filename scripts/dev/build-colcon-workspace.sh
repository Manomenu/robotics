#!/usr/bin/env bash
# HOST. colcon build workspace'u repo, bez wchodzenia do kontenera.
# Pisze tylko w repo (ws/build, ws/install, ws/log). Cofa: build-colcon-workspace-revert.sh
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec distrobox enter ros2 -- bash -lc "cd '$REPO/ws' && colcon build --symlink-install"
