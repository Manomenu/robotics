#!/usr/bin/env bash
# WEWNĄTRZ KONTENERA — jedyny taki skrypt w repo, stąd scripts/inside-distrobox/.
# Wołany przez scripts/container/create-container-for-ros2.sh, nie z ręki.
#
# Nie wymaga własnego revertu: wszystko poza /etc/profile.d/ros2.sh żyje
# w kontenerze i ginie razem z nim. Dlatego NIE piszemy do ~/.bashrc —
# katalog domowy jest współdzielony z Fedorą.
set -euo pipefail

# Konwencja repo mówi, że reszta skryptów uruchamia się z Fedory. Ten jeden
# nie — a uruchomiony tam próbowałby aptem zmienić hosta, czego żaden revert
# by nie cofnął. Dlatego sprawdza, gdzie jest, zamiast na to liczyć.
[ -f /run/.containerenv ] || {
  echo "Ten skrypt działa tylko wewnątrz kontenera." >&2
  echo "Z Fedory uruchom: scripts/container/create-container-for-ros2.sh" >&2
  exit 1
}

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
