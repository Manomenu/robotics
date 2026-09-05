#!/usr/bin/env bash
# STAN KONTENERA — czy istnieje, czy chodzi, ile zajmuje.
#
# Co realnie robi: pyta wyłącznie podmana. NIE wchodzi do kontenera i przez
# to go nie uruchamia — w przeciwieństwie do wszystkiego w scripts/dev/ros2/.
# To jedyny sposób sprawdzenia stanu, który sam go nie zmienia.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/container.sh"

usage() {
  cat <<'U'
użycie: show-ros2-container-status.sh

  Bez argumentów. Wypisuje stan kontenera ros2 widziany z Fedory.
  Nie uruchamia go i nie wchodzi do środka.
U
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ $# -eq 0 ] || { usage >&2; exit 2; }

if ! podman container exists "$CONTAINER" 2>/dev/null; then
  echo "kontener:  BRAK"
  echo
  echo "Dalej:"
  echo "  scripts/container/create-container-for-ros2.sh"
  exit 0
fi

echo "kontener:  $CONTAINER"
echo "obraz:     $(podman container inspect "$CONTAINER" --format '{{.ImageName}}')"
echo "stan:      $(podman ps -a --filter "name=^${CONTAINER}$" --format '{{.Status}}')"
echo "sesje:     $(podman container inspect "$CONTAINER" --format '{{len .ExecIDs}}') aktywnych wejść"
echo "obraz waży: $(podman image inspect "$IMAGE" --format '{{.Size}}' 2>/dev/null | numfmt --to=iec 2>/dev/null || echo '?')"

case "$(podman ps -a --filter "name=^${CONTAINER}$" --format '{{.State}}')" in
  running)
    echo
    echo "Chodzi. Zatrzymanie:  scripts/container/stop-ros2-container.sh" ;;
  *)
    echo
    echo "Stoi. Wystartuje sam przy pierwszym wejściu do niego." ;;
esac
