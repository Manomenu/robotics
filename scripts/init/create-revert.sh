#!/usr/bin/env bash
# HOST. Cofa ros2-create.sh: kontener, jego obraz i ślady, które ROS
# zostawia we WSPÓŁDZIELONYM katalogu domowym.
set -euo pipefail

CONTAINER=ros2
IMAGE=docker.io/library/ubuntu:24.04

distrobox rm --force "$CONTAINER" 2>/dev/null && echo "-> kontener usunięty" || echo "-> kontenera nie było"
podman rmi "$IMAGE" 2>/dev/null && echo "-> obraz usunięty" || echo "-> obraz zostaje (nie ma go, lub używa go coś innego)"

for d in ~/.ros ~/.colcon; do
  [ -e "$d" ] && { rm -rf "$d"; echo "-> usunięte $d"; }
done
echo "-> gotowe (distrobox zostaje — install-distrobox-revert.sh)"
