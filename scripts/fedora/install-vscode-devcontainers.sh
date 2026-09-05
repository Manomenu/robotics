#!/usr/bin/env bash
# HOST. Instaluje rozszerzenie Dev Containers w VS Code.
#
# To ono czyta .devcontainer/devcontainer.json, stawia kontener i wysyła
# do środka serwer VS Code — dzięki czemu Pylance, terminal i debugger
# działają obok ROS-a, a nie obok twojej Fedory.
#
# Rozmawia z podmanem przez /usr/bin/docker (pakiet podman-docker), więc
# nie trzeba niczego przestawiać. Cofa: install-vscode-devcontainers-revert.sh
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/container.sh"
refuse-inside-container

EXT=ms-vscode-remote.remote-containers

command -v code >/dev/null 2>&1 || { echo "brak VS Code (polecenie 'code')" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "brak /usr/bin/docker — doinstaluj: sudo dnf install podman-docker" >&2; exit 1; }

if code --list-extensions | grep -qx "$EXT"; then
  echo "-> $EXT już jest"
else
  code --install-extension "$EXT"
  echo "-> $EXT zainstalowane"
fi

cat <<'NEXT'

Dalej:

  code ~/repos/robotics
  potem: F1 → "Dev Containers: Reopen in Container"
NEXT
