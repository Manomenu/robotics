#!/usr/bin/env bash
# BIBLIOTEKA — nie uruchamiasz jej, tylko `source`ujesz z innego skryptu.
#
# Jedno miejsce, w którym stoi nazwa kontenera i sposób wejścia do niego.
# Nazwa MUSI zgadzać się z --name w .devcontainer/devcontainer.json —
# to jest jedyne miejsce w repo, gdzie te dwa światy się spotykają.
#
# Funkcje:
#   inside-devcontainer                 czy JESTEŚMY w kontenerze (tylko pyta)
#   require-fedora-host                 przerywa, gdy jesteś W kontenerze
#   require-devcontainer-cli            przerywa, gdy nie ma `devcontainer`
#   require-devcontainer                przerywa, gdy kontener nie istnieje
#   run-in-devcontainer "POLECENIE"     wykonaj w kontenerze i wróć tutaj
#   enter-devcontainer                  oddaj powłokę w kontenerze (exec)

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
# jest poprawna także w środku. Dzięki temu nie tłumaczymy ścieżek —
# i dzięki temu ten sam skrypt działa po obu stronach granicy.
REPO_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Plik /run/.containerenv tworzy podman przy starcie kontenera; na Fedorze
# go nie ma. To jedyne pytanie „gdzie jestem", jakie zadaje to repo.
inside-devcontainer() { [ -f /run/.containerenv ]; }

# Dla skryptów, które w kontenerze nie mają czego zrobić: podmana ani
# devcontainer CLI tam nie ma, a stawianie kontenera z kontenera nie
# ma sensu. Skrypty pracujące z ROS-em tego NIE wołają — one działają
# po obu stronach (patrz run-in-devcontainer).
require-fedora-host() {
  inside-devcontainer || return 0
  echo "To polecenie działa tylko z Fedory — dotyczy kontenera z zewnątrz," >&2
  echo "a ty jesteś już w środku (podmana i devcontainer CLI tu nie ma)." >&2
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

# Działa po obu stronach granicy i to jest cały jej sens: skrypt wołający
# tę funkcję nie musi wiedzieć, gdzie go uruchomiono.
#
#   z Fedory     -> podman exec do kontenera
#   z kontenera  -> wprost, bo już jesteśmy na miejscu
#
# Obie drogi kończą się na `bash -lc`, więc polecenie widzi DOKŁADNIE to samo
# środowisko: powłoka logowania czyta /etc/profile.d/ros2.sh, czyli ROS-a
# i workspace. To ta sama komenda, nie dwie podobne.
#
# Bez exec, żeby skrypt mógł po powrocie wypisać następny krok;
# kod wyjścia i tak przechodzi (przy set -e kończy skrypt tym samym).
run-in-devcontainer() {
  if inside-devcontainer; then
    bash -lc "cd '$REPO_PATH' && $*"
    return
  fi

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
# Wejść do kontenera można tylko z zewnątrz — w środku nie ma dokąd.
enter-devcontainer() {
  require-fedora-host
  require-devcontainer
  podman start "$CONTAINER" >/dev/null 2>&1 || true
  exec podman exec -u "$CONTAINER_USER" -w "$REPO_PATH" -it "$CONTAINER" bash -l
}
