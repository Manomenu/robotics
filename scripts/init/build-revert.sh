#!/usr/bin/env bash
# HOST. Kasuje artefakty budowy. Przydaje się, gdy colcon trzyma stary stan.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
rm -rf "$REPO/ws/build" "$REPO/ws/install" "$REPO/ws/log"
echo "-> ws/{build,install,log} usunięte"
