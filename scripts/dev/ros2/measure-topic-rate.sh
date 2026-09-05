#!/usr/bin/env bash
# JAK SZYBKO LECI — pomiar częstotliwości wiadomości na kanale.
#
# Co realnie robi: mierzy odstępy między kolejnymi wiadomościami i podaje
# średnią, odchylenie i min/max. Pierwszy wynik pojawia się po sekundzie.
#
# Po co: przy kilku sygnałach o różnych częstotliwościach (ciśnienie 50 Hz,
# prądy 500 Hz, obraz 5 Hz) to jest pierwsze pytanie, gdy coś gubi dane —
# czy nadawca zwolnił, czy odbiorca nie nadąża.
#
# Ctrl+C kończy.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)/container.sh"

usage() {
  cat <<'U'
użycie: measure-topic-rate.sh TOPIC [--window N]

  TOPIC        pełna nazwa kanału ze slashem, np. /chatter
  --window N   z ilu ostatnich wiadomości liczyć średnią (domyślnie 10000)
               mniejsze N = szybciej widać zmianę tempa

przykłady:
  measure-topic-rate.sh /chatter
  measure-topic-rate.sh /vacuum_pressure --window 50
U
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ $# -ge 1 ] || { usage >&2; exit 2; }

TOPIC="$1"; shift
run-in-devcontainer "ros2 topic hz '$TOPIC' $*"
