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
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)/container.sh"

usage() {
  cat <<'U'
użycie: print-topic-messages.sh TOPIC [OPCJE ros2 topic echo...]

  TOPIC        pełna nazwa kanału ze slashem, np. /chatter
  OPCJE        przekazywane wprost do `ros2 topic echo`, m.in.:
    --once           jedna wiadomość i koniec
    --field POLE     tylko wybrane pole, np. --field data
    --no-arr         nie wypisuj zawartości tablic (przydatne przy obrazach)

przykłady:
  print-topic-messages.sh /chatter
  print-topic-messages.sh /chatter --once
  print-topic-messages.sh /vacuum_pressure --field data
U
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ $# -ge 1 ] || { usage >&2; exit 2; }

TOPIC="$1"; shift
run-in-devcontainer "ros2 topic echo '$TOPIC' $*"
