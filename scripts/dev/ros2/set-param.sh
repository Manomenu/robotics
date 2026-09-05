#!/usr/bin/env bash
# USTAW PARAMETR — zmienia zachowanie DZIAŁAJĄCEGO węzła, bez restartu.
#
# Co realnie robi: `ros2 param set WĘZEŁ PARAMETR WARTOŚĆ` w kontenerze.
#
# Zmiana żyje tak długo jak proces węzła — po jego restarcie wraca wartość
# domyślna z declare_parameter(). Dlatego ten skrypt nie ma revertu:
# nie ma czego cofać, wystarczy zrestartować węzeł.
#
# Węzeł musi mieć ten parametr zadeklarowany (declare_parameter). Ustawienie
# nieznanej nazwy kończy się błędem, a nie cichym utworzeniem nowej.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)/container.sh"

usage() {
  cat <<'U'
użycie: set-param.sh WĘZEŁ PARAMETR WARTOŚĆ

  WĘZEŁ      pełna nazwa ze slashem, np. /vacuum_sensor
             listę masz z: list-running-nodes.sh
  PARAMETR   nazwa zadeklarowana w węźle, np. state
  WARTOŚĆ    typ jest wnioskowany: 5 -> int, 5.0 -> float,
             true/false -> bool, reszta -> tekst

przykłady:
  set-param.sh /vacuum_sensor state sealed
  set-param.sh /vacuum_sensor state leak
  set-param.sh /vacuum_sensor state empty
  set-param.sh /grasp_monitor window 50

nie wiesz, co węzeł ma do ustawienia:
  set-param.sh /vacuum_sensor         ← wypisze parametry tego węzła
U
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

[ $# -ge 1 ] || { echo "brakuje argumentów" >&2; echo >&2; usage >&2; exit 2; }

NODE="$1"; shift

# Sam węzeł = pytanie „co da się tu ustawić", nie próba ustawienia.
if [ $# -eq 0 ]; then
  echo "Parametry węzła '$NODE':" >&2
  echo >&2
  run-in-devcontainer "ros2 param list '$NODE'" || {
    echo >&2
    echo "Węzeł '$NODE' nie odpowiada. Czy działa?" >&2
    echo "Sprawdź:  scripts/dev/ros2/list-running-nodes.sh" >&2
    exit 1
  }
  exit 0
fi

[ $# -eq 2 ] || {
  echo "podaj PARAMETR i WARTOŚĆ (dostałem $# argument(ów) po nazwie węzła)" >&2
  echo >&2; usage >&2; exit 2
}

run-in-devcontainer "ros2 param set '$NODE' '$1' '$2'"
