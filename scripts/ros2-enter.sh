#!/usr/bin/env bash
# Wejście do środowiska. bash -l, żeby złapać /etc/profile.d/ros2.sh
# (sourcing ROS-a i overlaya workspace'u, jeśli zbudowany).
set -euo pipefail
exec distrobox enter ros2 -- bash -l
