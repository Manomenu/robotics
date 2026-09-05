#!/usr/bin/env bash
# HOST. Stawia kontener opisany w .devcontainer/devcontainer.json.
#
# Sam nic nie konfiguruje — cała wiedza o środowisku (obraz, montowania,
# użytkownik, rozszerzenia) siedzi w tamtym pliku. Ten skrypt tylko każe
# ją wykonać, żeby dało się to zrobić z terminala, nie tylko z VS Code.
# Idempotentny. Cofa: create-devcontainer-revert.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/container.sh"
refuse-inside-container
require-devcontainer-cli

REPO="$(cd "$HERE/../.." && pwd)"

if podman container exists "$CONTAINER"; then
  echo "-> kontener $CONTAINER już istnieje"
else
  echo "-> stawianie kontenera z .devcontainer/devcontainer.json"
  devcontainer up --workspace-folder "$REPO"
fi

cat <<'NEXT'

Dalej:

  code ~/repos/robotics                       potem: Reopen in Container
  scripts/dev/enter-devcontainer.sh    albo terminal z Fedory
NEXT
