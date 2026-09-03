#!/usr/bin/env bash
# colcon build workspace'u repo, z hosta, bez wchodzenia do kontenera.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec distrobox enter ros2 -- bash -lc \
  "cd '$REPO/ws' && colcon build --symlink-install"
