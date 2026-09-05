#!/usr/bin/env bash
# WEWNĄTRZ KONTENERA. Woła to devcontainer.json (postCreateCommand),
# raz, tuż po utworzeniu kontenera. Nie uruchamiasz tego z Fedory.
#
# Zadanie: sprawić, żeby ROS był dostępny w KAŻDEJ powłoce w kontenerze.
#
# Dlaczego /etc/profile.d/, a nie ~/.bashrc: .bashrc przerywa się na
# pierwszej linii dla powłok nieinteraktywnych, więc `podman exec bash -lc`
# odpalane przez skrypty z Fedory nigdy by go nie wykonało. /etc/profile.d/
# czyta każda powłoka logowaniowa — także nieinteraktywna.
set -euo pipefail

REPO=/home/maniumek/repos/robotics

sudo tee /etc/profile.d/ros2.sh >/dev/null <<PROFILE
[ -f /opt/ros/jazzy/setup.bash ] && . /opt/ros/jazzy/setup.bash
[ -f $REPO/ws/install/setup.bash ] && . $REPO/ws/install/setup.bash
PROFILE

echo "-> /etc/profile.d/ros2.sh zapisany"
