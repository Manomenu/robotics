#!/usr/bin/env bash
# CO DZIAŁA — nazwy wszystkich żywych węzłów.
#
# Co realnie robi: pyta sieć ROS-a, kto się w niej ogłosił. Nigdzie nie ma
# pliku z tą listą — węzły rozgłaszają swoje istnienie same, a to polecenie
# ich słucha. Pusto = nic nie chodzi (albo chodzi w innym ROS_DOMAIN_ID).
#
# Szczegóły pojedynczego węzła: show-node-connections.sh
set -euo pipefail

usage() {
  cat <<'U'
użycie: list-running-nodes.sh

  Bez argumentów. Wypisuje nazwy węzłów działających w tej chwili.
  Nazwy zaczynają się od slasha, np. /talker.

  Co dalej z taką nazwą:
    show-node-connections.sh /talker   co ten węzeł nadaje i czego słucha
U
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ $# -eq 0 ] || { echo "ten skrypt nie bierze argumentów — szczegóły węzła: show-node-connections.sh" >&2; echo >&2; usage >&2; exit 2; }
podman container exists ros2 || { echo "brak kontenera ros2 — scripts/init/create-container-for-ros2.sh" >&2; exit 1; }

exec distrobox enter ros2 -- bash -lc 'ros2 node list'
