#!/usr/bin/env bash
# HOST. Instaluje ROS 2 Jazzy + colcon w istniejącym kontenerze ros2.
#
# Sam nic nie robi: wchodzi do kontenera i uruchamia tam swojego imiennika
# ze scripts/inside-distrobox/container/. Ta sama nazwa po obu stronach jest
# celowa — mówi, że to jedna czynność widziana z dwóch stron granicy.
#
# Nie ma własnego revertu: wszystko, co instaluje, żyje w kontenerze
# i ginie razem z nim, czyli cofa to create-container-for-ros2-revert.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/container.sh"

echo "-> instalacja wewnątrz kontenera (może potrwać kwadrans)"
run-in-ros2-container "bash '$HERE/../inside-distrobox/container/install-ros2-in-container.sh'"

cat <<'NEXT'

Dalej:

  scripts/dev/ros2/enter-ros2-container.sh        wejście do środowiska
  scripts/dev/ros2/list-running-nodes.sh          sprawdzenie, czy ROS odpowiada
NEXT
