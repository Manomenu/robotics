#!/usr/bin/env bash
# HOST. Wejście do środowiska. Bez skutków ubocznych, więc bez revertu.
# bash -l, żeby złapać /etc/profile.d/ros2.sh z kontenera.
set -euo pipefail
exec distrobox enter ros2 -- bash -l
