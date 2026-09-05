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

usage() {
  cat <<'U'
użycie: topics.sh [--no-types]

  bez argumentu   nazwy kanałów + typ wiadomości  (ros2 topic list -t)
  --no-types      same nazwy

przykłady:
  topics.sh
  topics.sh --no-types
U
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
podman container exists ros2 || { echo "brak kontenera ros2 — scripts/init/create-container-for-ros2.sh" >&2; exit 1; }

FLAG="-t"
[ "${1:-}" = "--no-types" ] && FLAG=""
exec distrobox enter ros2 -- bash -lc "ros2 topic list $FLAG"
