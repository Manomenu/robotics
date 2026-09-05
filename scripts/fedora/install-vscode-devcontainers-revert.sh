#!/usr/bin/env bash
# HOST. Cofa install-vscode-devcontainers.sh.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/container.sh"
refuse-inside-container

code --uninstall-extension ms-vscode-remote.remote-containers 2>/dev/null \
  && echo "-> rozszerzenie usunięte" || echo "-> nie było go"
