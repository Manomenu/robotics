#!/usr/bin/env bash
# HOST. Tworzy kontener ros2 (Ubuntu 24.04) i instaluje w nim ROS 2 Jazzy.
# Idempotentny. Cofa: create-container-revert.sh
set -euo pipefail

CONTAINER=ros2
IMAGE=docker.io/library/ubuntu:24.04
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v distrobox >/dev/null 2>&1 || { echo "Brak distroboxa — najpierw install-distrobox.sh" >&2; exit 1; }

if podman container exists "$CONTAINER"; then
  echo "-> kontener $CONTAINER już istnieje"
else
  distrobox create --name "$CONTAINER" --image "$IMAGE" --yes
fi

echo "-> provisioning wewnątrz kontenera (może potrwać kwadrans)"
distrobox enter "$CONTAINER" -- bash "$HERE/install-ros2.sh"

echo
echo "Gotowe. Wejście:  $HERE/../ros2/enter.sh"
