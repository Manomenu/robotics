#!/usr/bin/env bash
# HOST. Cofa create-devcontainer.sh: kontener, obrazy i artefakty budowy.
#
# Obrazów jest kilka, nie jeden: devcontainer CLI buduje z Containerfile
# obraz pochodny (vsc-*), a potem jeszcze jeden wariant z mapowaniem UID.
# Kasujemy je po prefiksie, bo ich nazwy zawierają hash ścieżki repo.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/container.sh"
require-fedora-host

podman rm --force "$CONTAINER" >/dev/null 2>&1 && echo "-> kontener usunięty" || echo "-> kontenera nie było"

N=0
for img in $(podman images --format '{{.Repository}}:{{.Tag}}' | grep -E '^localhost/vsc-robotics' || true); do
  podman rmi --force "$img" >/dev/null 2>&1 && N=$((N+1)) || true
done
echo "-> obrazy pochodne (vsc-robotics-*) usunięte: $N"

podman rmi "$IMAGE" >/dev/null 2>&1 && echo "-> obraz bazowy $IMAGE usunięty" || echo "-> obraz bazowy zostaje (nie ma go, lub używa go coś innego)"
podman image prune -f >/dev/null 2>&1 || true

echo "-> gotowe (devcontainer CLI zostaje — fedora/install-devcontainer-cli-revert.sh)"
