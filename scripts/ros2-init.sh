#!/usr/bin/env bash
# Tworzy kontener ros2 (Ubuntu 24.04) i instaluje w nim ROS 2 Jazzy.
# Idempotentny — można puścić ponownie, np. po ros2-clean.sh.
set -euo pipefail

CONTAINER=ros2
IMAGE=docker.io/library/ubuntu:24.04
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if podman container exists "$CONTAINER"; then
  echo "-> kontener $CONTAINER już istnieje"
else
  echo "-> tworzę kontener $CONTAINER"
  distrobox create --name "$CONTAINER" --image "$IMAGE" --yes
fi

echo "-> provisioning wewnątrz kontenera (może potrwać kwadrans)"
distrobox enter "$CONTAINER" -- bash "$HERE/ros2-provision.sh"

echo
echo "Gotowe. Wejście:  $HERE/ros2-enter.sh"
