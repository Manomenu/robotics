#!/usr/bin/env bash
# BIBLIOTEKA — nie uruchamiasz jej, tylko `source`ujesz z innego skryptu.
#
# Jedno miejsce, w którym stoi nazwa kontenera i sposób wejścia do niego.
# Nazwa MUSI zgadzać się z --name w .devcontainer/devcontainer.json —
# to jest jedyne miejsce w repo, gdzie te dwa światy się spotykają.
#
# Funkcje:
#   require-devcontainer-cli            przerywa, gdy nie ma `devcontainer`
#   require-devcontainer              przerywa, gdy kontener nie istnieje
#   refuse-inside-container             przerywa, gdy jesteś W kontenerze
#   run-in-devcontainer "POLECENIE"   wykonaj w kontenerze i wróć tutaj
#   enter-devcontainer                oddaj powłokę w kontenerze (exec)

[ "${BASH_SOURCE[0]}" != "$0" ] || {
  echo "To biblioteka, nie polecenie — inne skrypty robią na niej 'source'." >&2
  exit 1
}

CONTAINER=robotics-ros2
IMAGE=docker.io/osrf/ros:jazzy-desktop

# Musi zgadzać się z "remoteUser" w devcontainer.json. `podman exec` bez -u
# wchodzi jako root, a wtedy pliki tworzone w repo (ws/build) miałyby przy
# --userns=keep-id błędnego właściciela na Fedorze.
CONTAINER_USER=ubuntu

# Repo jest zamontowane pod TĄ SAMĄ ścieżką co na Fedorze (patrz
# workspaceMount w devcontainer.json), więc ścieżka policzona na hoście
# jest poprawna także w środku. Dzięki temu nie tłumaczymy ścieżek.
REPO_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Skrypty tego repo odpala się WYŁĄCZNIE z Fedory. W kontenerze masz
# gołe komendy ROS-a i nie potrzebujesz opakowań — a opakowanie użyte
# w środku próbowałoby wejść do kontenera z kontenera.
refuse-inside-container() {
  [ -f /run/.containerenv ] || return 0
  echo "Jesteś wewnątrz kontenera — te skrypty odpala się z Fedory." >&2
  echo "Tutaj używaj wprost: ros2 topic list, colcon build, ..." >&2
  exit 1
}

require-devcontainer-cli() {
  command -v devcontainer >/dev/null 2>&1 || {
    echo "brak devcontainer CLI — scripts/fedora/install-devcontainer-cli.sh" >&2
    exit 1
  }
}

require-devcontainer() {
  podman container exists "$CONTAINER" 2>/dev/null || {
    echo "brak kontenera $CONTAINER — scripts/container/create-devcontainer.sh" >&2
    exit 1
  }
}

# bash -l, żeby złapać ~/.bashrc z sourcem ROS-a i workspace'u.
# Bez exec, żeby skrypt mógł po powrocie wypisać następny krok;
# kod wyjścia i tak przechodzi (przy set -e kończy skrypt tym samym).
run-in-devcontainer() {
  refuse-inside-container
  require-devcontainer
  podman start "$CONTAINER" >/dev/null 2>&1 || true

  # Terminal podpinamy tylko wtedy, gdy sami go mamy. Bez tego Ctrl+C nie
  # dochodzi do procesu w kontenerze, a węzły i podsłuch działają do Ctrl+C.
  # Gdy wyjście idzie do potoku albo pliku, -t psułoby formatowanie.
  local tty=()
  [ -t 0 ] && [ -t 1 ] && tty=(-i -t)

  podman exec -u "$CONTAINER_USER" -w "$REPO_PATH" ${tty[@]+"${tty[@]}"} "$CONTAINER" bash -lc "$*"
}

# Tu exec jest na miejscu: to przekazanie powłoki, nie wywołanie polecenia.
enter-devcontainer() {
  refuse-inside-container
  require-devcontainer
  podman start "$CONTAINER" >/dev/null 2>&1 || true
  exec podman exec -u "$CONTAINER_USER" -w "$REPO_PATH" -it "$CONTAINER" bash -l
}
