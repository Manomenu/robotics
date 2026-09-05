#!/usr/bin/env bash
# JAKIE KANAŁY — lista topiców wraz z typem wiadomości.
#
# Co realnie robi: wypisuje nazwy kanałów istniejących w tej chwili w sieci.
# Typ pokazujemy domyślnie, bo kanał to kontrakt: obie strony muszą używać
# tej samej struktury wiadomości, inaczej po prostu się nie zobaczą.
#
# /rosout i /parameter_events dokłada ROS każdemu węzłowi sam — to
# odpowiednio zbiorcze logi i powiadomienia o zmianie parametrów.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)/container.sh"

usage() {
  cat <<'U'
użycie: list-topics.sh [--no-types]

  bez argumentu   nazwy kanałów + typ wiadomości  (ros2 topic list -t)
  --no-types      same nazwy

przykłady:
  list-topics.sh
  list-topics.sh --no-types
U
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

FLAG="-t"
[ "${1:-}" = "--no-types" ] && FLAG=""
run-in-ros2-container "ros2 topic list $FLAG"
