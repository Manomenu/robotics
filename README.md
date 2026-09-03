# robotics

Nauka robotyki przez jeden projekt na raz. Wszystko, co dotyczy ROS-a,
żyje w kontenerze `ros2` (Ubuntu 24.04) — Fedora zostaje czysta.

## Start

    scripts/install-distrobox.sh   raz na maszynę
    scripts/ros2-create.sh         raz: kontener + ROS 2 Jazzy (~5 GB, kwadrans)
    scripts/ros2-enter.sh          codziennie: wejście do środowiska
    scripts/ros2-build.sh          budowa ws/ (colcon)

## Skrypty

| skrypt | co robi | co po nim zostaje | cofa |
|---|---|---|---|
| `install-distrobox.sh` | `dnf install distrobox` | pakiet na Fedorze | `install-distrobox-revert.sh` |
| `ros2-create.sh` | kontener `ros2` + ROS 2 Jazzy | kontener, obraz, `~/.ros`, `~/.colcon` | `ros2-create-revert.sh` |
| `ros2-provision.sh` | wnętrze kontenera (wołane przez `ros2-create.sh`) | tylko w kontenerze | — (ginie z kontenerem) |
| `ros2-enter.sh` | wejście do środowiska | nic | — |
| `ros2-build.sh` | `colcon build` | `ws/{build,install,log}` w repo | `ros2-build-revert.sh` |

Pełne wycofanie, w tej kolejności:

    scripts/ros2-build-revert.sh
    scripts/ros2-create-revert.sh
    scripts/install-distrobox-revert.sh
    rm -rf ~/repos/robotics

Zasada, którą to realizuje — patrz AGENTS.md.

## Układ

    ws/src/          pakiety ROS — wszystko, co musi być pakietem, idzie tu
    projects/<nazwa> notatki, analiza offline i dane danego projektu
    scripts/         obsługa środowiska TEGO repo
                     (skrypty maszynowe są w ~/scripts, nie tu)

Jeden colcon workspace na całe repo. Kolejny projekt = kolejny pakiet
w `ws/src/` plus katalog w `projects/`, nie nowe repo.

## Projekty

- `grab-fail-detection` — wykrywanie nieudanego chwytu z sygnałów celi
