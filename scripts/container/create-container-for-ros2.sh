#!/usr/bin/env bash
# HOST. Tworzy pusty kontener ros2 (Ubuntu 24.04). NIC w nim nie instaluje
# i NIE wchodzi do środka — to osobny krok, patrz komunikat na końcu.
# Idempotentny. Cofa: create-container-for-ros2-revert.sh
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/container.sh"

require-distrobox-installed

if podman container exists "$CONTAINER"; then
  echo "-> kontener $CONTAINER już istnieje"
else
  distrobox create --name "$CONTAINER" --image "$IMAGE" --yes
  echo "-> kontener $CONTAINER utworzony (pusty, bez ROS-a)"
fi

cat <<'NEXT'

Dalej:

  scripts/container/install-ros2-in-container.sh   ROS 2 Jazzy + colcon
                                                  (~5 GB, kwadrans — raz)

  scripts/ros2/enter-ros2-container.sh            wejście do środowiska
                                                  (codziennie, po instalacji)
NEXT
