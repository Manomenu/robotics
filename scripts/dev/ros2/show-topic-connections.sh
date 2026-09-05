#!/usr/bin/env bash
# KTO NADAJE, KTO SŁUCHA — pełny opis jednego kanału.
#
# Co realnie robi: pokazuje typ wiadomości, liczbę nadawców i odbiorców
# oraz ustawienia QoS obu stron.
#
# Trzy rzeczy, na które patrzeć:
#   Publisher count: 0     nikt nie nadaje — węzeł padł albo nazwa się nie zgadza
#   Subscription count: 0  nikt nie słucha — to NIE jest błąd, nadawca nadaje dalej
#   QoS                    gdy oba węzły żyją, a mimo to się nie widzą,
#                          zwykle winne jest niedopasowane QoS (typowo przy kamerach)
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)/container.sh"

usage() {
  cat <<'U'
użycie: show-topic-connections.sh TOPIC

  TOPIC   pełna nazwa kanału ze slashem, np. /chatter
          listę masz z: scripts/dev/ros2/list-topics.sh

przykład:
  show-topic-connections.sh /chatter
U
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ $# -eq 1 ] || { usage >&2; exit 2; }

run-in-ros2-container "ros2 topic info '$1' -v"
