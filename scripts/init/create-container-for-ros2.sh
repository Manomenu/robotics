#!/usr/bin/env bash
# HOST. Tworzy kontener ros2 (Ubuntu 24.04) i instaluje w nim ROS 2 Jazzy.
# Idempotentny. Cofa: create-container-for-ros2-revert.sh
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/container.sh"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

require-distrobox-installed

if podman container exists "$CONTAINER"; then
  echo "-> kontener $CONTAINER już istnieje"
else
  distrobox create --name "$CONTAINER" --image "$IMAGE" --yes
fi

echo "-> provisioning wewnątrz kontenera (może potrwać kwadrans)"
# Nie run-in-ros2-container: tamta funkcja używa exec, a tu po powrocie
# mamy jeszcze co wypisać. Wysyłamy plik, nie polecenie.
distrobox enter "$CONTAINER" -- bash "$HERE/../inside-distrobox/init/install-ros2-in-container.sh"

echo
echo "Gotowe. Wejście:  $HERE/../ros2/enter-ros2-container.sh"
