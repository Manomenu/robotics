#!/usr/bin/env bash
# CO LECI — podsłuch treści wiadomości na kanale.
#
# Co realnie robi: dopisuje się jako kolejny odbiorca kanału i wypisuje, co
# tamtędy płynie. Nadawcy nie trzeba w tym celu zatrzymywać ani zmieniać —
# on się nawet nie zorientuje (poza tym, że Subscription count wzrośnie).
# Wchodzisz w środek strumienia: wiadomości sprzed uruchomienia nie zobaczysz.
#
# Ctrl+C kończy.
set -euo pipefail

usage() {
  cat <<'U'
użycie: echo.sh TOPIC [OPCJE ros2 topic echo...]

  TOPIC        pełna nazwa kanału ze slashem, np. /chatter
  OPCJE        przekazywane wprost do `ros2 topic echo`, m.in.:
    --once           jedna wiadomość i koniec
    --field POLE     tylko wybrane pole, np. --field data
    --no-arr         nie wypisuj zawartości tablic (przydatne przy obrazach)

przykłady:
  echo.sh /chatter
  echo.sh /chatter --once
  echo.sh /vacuum_pressure --field data
U
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ $# -ge 1 ] || { usage >&2; exit 2; }
podman container exists ros2 || { echo "brak kontenera ros2 — scripts/init/create-container.sh" >&2; exit 1; }

TOPIC="$1"; shift
exec distrobox enter ros2 -- bash -lc "ros2 topic echo '$TOPIC' $*"
