#!/usr/bin/env bash
# CO TEN WĘZEŁ NADAJE I CZEGO SŁUCHA — opis jednego węzła.
#
# Co realnie robi: wypisuje kanały, na które dany węzeł nadaje (Publishers),
# których słucha (Subscribers), oraz jego serwisy i akcje.
#
# To jest widok od strony WĘZŁA. Ten sam graf od strony KANAŁU pokazuje
# show-topic-connections.sh — przydaje się, gdy nie wiesz, kto zasila temat.
set -euo pipefail

usage() {
  cat <<'U'
użycie: show-node-connections.sh WĘZEŁ

  WĘZEŁ   pełna nazwa ze slashem, np. /talker
          listę masz z: list-running-nodes.sh

przykład:
  show-node-connections.sh /talker
U
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ $# -eq 1 ] || { usage >&2; exit 2; }
podman container exists ros2 || { echo "brak kontenera ros2 — scripts/init/create-container-for-ros2.sh" >&2; exit 1; }

exec distrobox enter ros2 -- bash -lc "ros2 node info '$1'"
