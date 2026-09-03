#!/usr/bin/env bash
# CO DZIAŁA — lista żywych węzłów, albo szczegóły jednego.
#
# Co realnie robi: pyta sieć ROS-a, kto się w niej ogłosił. Nigdzie nie ma
# pliku z tą listą — węzły rozgłaszają swoje istnienie same, a to polecenie
# ich słucha. Pusto = nic nie chodzi (albo chodzi w innym ROS_DOMAIN_ID).
set -euo pipefail

usage() {
  cat <<'U'
użycie: nodes.sh [WĘZEŁ]

  bez argumentu   wypisz nazwy wszystkich działających węzłów
  WĘZEŁ           pełna nazwa ze slashem, np. /talker
                  — pokaże jego topici (nadawane i słuchane) oraz serwisy

przykłady:
  nodes.sh
  nodes.sh /talker
U
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
podman container exists ros2 || { echo "brak kontenera ros2 — scripts/init/create.sh" >&2; exit 1; }

if [ $# -eq 0 ]; then
  exec distrobox enter ros2 -- bash -lc 'ros2 node list'
else
  exec distrobox enter ros2 -- bash -lc "ros2 node info '$1'"
fi
