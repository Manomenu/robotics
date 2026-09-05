#!/usr/bin/env bash
# BIBLIOTEKA — nie uruchamiasz jej, tylko `source`ujesz z innego skryptu.
#
# Po co istnieje: nazwa kontenera i obraz stały wcześniej zaszyte na sztywno
# w ośmiu plikach, a „wejdź do kontenera i wykonaj" powtarzało się w dziewięciu.
# Tutaj jest jedno miejsce, w którym to się zmienia.
#
# Wszystko poniżej wykonuje się NA HOŚCIE — to host wchodzi do kontenera,
# nie odwrotnie. Kod, który sam musi działać w środku, leży w
# scripts/inside-distrobox/ i tej biblioteki nie używa.
#
# Funkcje:
#   require-distrobox-installed        przerywa, gdy nie ma distroboxa
#   require-ros2-container             przerywa, gdy nie ma kontenera
#   run-in-ros2-container "POLECENIE"  wykonaj w kontenerze (exec — na końcu skryptu)
#   enter-ros2-container               zostań w kontenerze  (exec — na końcu skryptu)

[ "${BASH_SOURCE[0]}" != "$0" ] || {
  echo "To biblioteka, nie polecenie — inne skrypty robią na niej 'source'." >&2
  exit 1
}

CONTAINER=ros2
IMAGE=docker.io/library/ubuntu:24.04

# Dla skryptów, które kontener dopiero tworzą — jego jeszcze nie ma,
# więc sprawdzamy tylko narzędzie.
require-distrobox-installed() {
  command -v distrobox >/dev/null 2>&1 || {
    echo "brak distroboxa — scripts/fedora/install-distrobox.sh" >&2
    exit 1
  }
}

require-ros2-container() {
  podman container exists "$CONTAINER" 2>/dev/null || {
    echo "brak kontenera $CONTAINER — scripts/container/create-container-for-ros2.sh" >&2
    exit 1
  }
}

# bash -l, żeby złapać /etc/profile.d/ros2.sh — czyli source ROS-a i workspace'u.
# Używa exec, więc MUSI być ostatnią instrukcją skryptu; kod wyjścia polecenia
# staje się kodem wyjścia skryptu.
run-in-ros2-container() {
  require-ros2-container
  exec distrobox enter "$CONTAINER" -- bash -lc "$*"
}

enter-ros2-container() {
  require-ros2-container
  exec distrobox enter "$CONTAINER" -- bash -l
}
