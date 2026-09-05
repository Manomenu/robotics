#!/usr/bin/env bash
# HOST. Zostawia cię w powłoce wewnątrz kontenera ros2.
# Bez skutków ubocznych, więc bez revertu — wyjście to zwykłe `exit`.
#
# Powłoka jest logowaniowa (bash -l), żeby wykonało się /etc/profile.d/ros2.sh,
# czyli source ROS-a i twojego workspace'u. Bez tego `ros2` nie istnieje.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)/container.sh"

enter-ros2-container
