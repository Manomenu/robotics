#!/usr/bin/env bash
# ZATRZYMANIE KONTENERA — zwalnia pamięć, nie kasuje niczego.
#
# Kontener po zatrzymaniu zachowuje wszystko: ROS-a, zainstalowane pakiety,
# stan. Wystartuje sam, gdy następnym razem coś do niego wejdzie.
# Do skasowania służy create-devcontainer-revert.sh — to co innego.
#
# Dlaczego to nie jest samo `podman stop`: podman odmawia zatrzymania,
# dopóki widzi aktywne sesje exec, a każde `podman enter` taką zakłada.
# Przerwane wejście potrafi zostawić wpis, który przeżywa swój proces —
# dlatego najpierw je sprzątamy, a dopiero potem zatrzymujemy.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/container.sh"

usage() {
  cat <<'U'
użycie: stop-devcontainer.sh

  Bez argumentów. Zatrzymuje kontener ros2, nic nie kasując.
  Najpierw sprząta osierocone sesje exec, bo inaczej podman odmówi.
U
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ $# -eq 0 ] || { usage >&2; exit 2; }

podman container exists "$CONTAINER" 2>/dev/null || { echo "-> kontenera $CONTAINER nie ma, nie ma czego zatrzymywać"; exit 0; }

STATE="$(podman ps -a --filter "name=^${CONTAINER}$" --format '{{.State}}')"
[ "$STATE" = running ] || { echo "-> kontener $CONTAINER już stoi ($STATE)"; exit 0; }

SESSIONS="$(podman container inspect "$CONTAINER" --format '{{range .ExecIDs}}{{.}} {{end}}')"
if [ -n "${SESSIONS// /}" ]; then
  N=0
  for id in $SESSIONS; do
    podman container cleanup --exec "$id" "$CONTAINER" >/dev/null 2>&1 && N=$((N+1)) || true
  done
  echo "-> sprzątnięte sesje exec: $N"
fi

podman stop "$CONTAINER" >/dev/null
echo "-> kontener $CONTAINER zatrzymany (nic nie skasowane)"

cat <<'NEXT'

Dalej:

  scripts/container/show-devcontainer-status.sh   podgląd stanu
  scripts/dev/enter-devcontainer.sh              wejście (wystartuje sam)
NEXT
