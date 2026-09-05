#!/usr/bin/env bash
# URUCHOM WĘZEŁ — startuje jeden węzeł z twojego pakietu.
#
# Co realnie robi: `ros2 run PAKIET WĘZEŁ` w kontenerze. Nazwa WĘZŁA to nie
# nazwa pliku, tylko komenda zarejestrowana w `entry_points` w setup.py —
# dlatego po dopisaniu nowego węzła trzeba przebudować, zanim się tu pojawi.
#
# Węzeł działa aż do Ctrl+C i zwykle nic nie wypisuje. To normalne: żeby
# zobaczyć, co robi, użyj z drugiego terminala list-running-nodes.sh
# albo print-topic-messages.sh.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)/container.sh"

usage() {
  cat <<'U'
użycie: run-node.sh PAKIET WĘZEŁ [DODATKOWE ARGUMENTY...]

  PAKIET      nazwa pakietu z ws/src, np. grip_monitor
  WĘZEŁ       nazwa komendy z entry_points w setup.py, np. vacuum_sensor
              (NIE nazwa pliku — te dwie rzeczy mogą się różnić)
  ARGUMENTY   przekazywane wprost do `ros2 run`, m.in.:
    --ros-args -p NAZWA:=WARTOŚĆ     parametr startowy
    --ros-args -r STARA:=NOWA        podmiana nazwy tematu

przykłady:
  run-node.sh grip_monitor vacuum_sensor
  run-node.sh grip_monitor grasp_monitor
  run-node.sh grip_monitor vacuum_sensor --ros-args -p state:=sealed
  run-node.sh grip_monitor vacuum_sensor --ros-args -r vacuum_pressure:=cisnienie_2

nie wiesz, co masz do uruchomienia:
  run-node.sh grip_monitor            ← wypisze węzły dostępne w pakiecie
U
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

[ $# -ge 1 ] || { echo "brakuje argumentów" >&2; echo >&2; usage >&2; exit 2; }

PKG="$1"; shift

# Jeden argument = pytanie „co ten pakiet oferuje", nie próba uruchomienia.
if [ $# -eq 0 ]; then
  echo "Węzły dostępne w pakiecie '$PKG':" >&2
  echo >&2
  run-in-devcontainer "ros2 pkg executables '$PKG'" || {
    echo >&2
    echo "Pakiet '$PKG' nie istnieje albo nie jest zbudowany." >&2
    echo "Zbuduj:  scripts/dev/build-colcon-workspace.sh" >&2
    exit 1
  }
  exit 0
fi

NODE="$1"; shift
run-in-devcontainer "ros2 run '$PKG' '$NODE' $*"
