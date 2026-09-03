#!/usr/bin/env bash
# Uruchamiane WEWNĄTRZ kontenera przez ros2-init.sh.
# Wszystko, co tu robimy, żyje w kontenerze — poza jednym wyjątkiem:
# katalog domowy jest współdzielony z hostem, więc nie dotykamy ~/.bashrc.
# Sourcing ROS-a idzie do /etc/profile.d/, czyli do systemu plików kontenera.
set -euo pipefail

if ! dpkg -s ros-jazzy-desktop >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y curl gnupg software-properties-common
  sudo add-apt-repository universe -y

  if ! dpkg -s ros2-apt-source >/dev/null 2>&1; then
    V=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest \
        | grep -F '"tag_name"' | awk -F\" '{print $4}')
    CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
    curl -fsSL -o /tmp/ros2-apt-source.deb \
      "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${V}/ros2-apt-source_${V}.${CODENAME}_all.deb"
    sudo apt-get install -y /tmp/ros2-apt-source.deb
  fi

  sudo apt-get update
  sudo apt-get install -y ros-jazzy-desktop python3-colcon-common-extensions
fi

sudo tee /etc/profile.d/ros2.sh >/dev/null <<'PROFILE'
[ -f /opt/ros/jazzy/setup.bash ] && . /opt/ros/jazzy/setup.bash
[ -f "$HOME/repos/robotics/ws/install/setup.bash" ] && . "$HOME/repos/robotics/ws/install/setup.bash"
PROFILE

echo "-> ROS 2 Jazzy gotowy"
