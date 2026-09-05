#!/usr/bin/env bash
# HOST. Cofa create-container-for-ros2.sh: kontener, jego obraz i ślady, które ROS
# zostawia we WSPÓŁDZIELONYM katalogu domowym.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/container.sh"

distrobox rm --force "$CONTAINER" 2>/dev/null && echo "-> kontener usunięty" || echo "-> kontenera nie było"
podman rmi "$IMAGE" 2>/dev/null && echo "-> obraz usunięty" || echo "-> obraz zostaje (nie ma go, lub używa go coś innego)"

for d in ~/.ros ~/.colcon; do
  [ -e "$d" ] && { rm -rf "$d"; echo "-> usunięte $d"; }
done
echo "-> gotowe (distrobox zostaje — install-distrobox-revert.sh)"
