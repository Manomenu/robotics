# robotics

Nauka robotyki przez jeden projekt na raz. Wszystko, co dotyczy ROS-a,
żyje w kontenerze `ros2` (Ubuntu 24.04) — Fedora zostaje czysta.

## Start

    scripts/init/install-distrobox.sh          raz na maszynę
    scripts/init/create-container-for-ros2.sh  raz: kontener + ROS 2 Jazzy (~5 GB, kwadrans)
    scripts/ros2/enter.sh                      codziennie: wejście do środowiska
    scripts/init/build-workspace.sh            po każdej zmianie w ws/src

## scripts/init — zmieniają maszynę, każdy ma revert

Kolejność uruchamiania jest kolejnością tabeli. Nazwa każdego skryptu mówi,
co on **tworzy**: distroboxa, kontener, ROS-a w kontenerze, workspace.

Skrypty w `init/.internal/` odpala inny skrypt, nie ty. Kropka w nazwie
katalogu jest po to, żeby nie wpadały pod rękę przy dopełnianiu ścieżek.

| skrypt | co robi | co po nim zostaje | cofa |
|---|---|---|---|
| `install-distrobox.sh` | `dnf install distrobox` | pakiet na Fedorze | `install-distrobox-revert.sh` |
| `create-container-for-ros2.sh` | kontener `ros2` + ROS 2 Jazzy | kontener, obraz, `~/.ros`, `~/.colcon` | `create-container-for-ros2-revert.sh` |
| `.internal/install-ros2-in-container.sh` | ROS 2 Jazzy + colcon **wewnątrz kontenera** — woła go `create-container-for-ros2.sh`, nie uruchamiaj z hosta | tylko w kontenerze | — (ginie z kontenerem) |
| `build-workspace.sh` | `colcon build` | `ws/{build,install,log}` w repo | `build-workspace-revert.sh` |

Pełne wycofanie, w tej kolejności:

    scripts/init/build-workspace-revert.sh
    scripts/init/create-container-for-ros2-revert.sh
    scripts/init/install-distrobox-revert.sh
    rm -rf ~/repos/robotics

## scripts/ros2 — oglądanie żywego systemu, nic nie zmieniają

Odpowiadają na cztery pytania o działającą sieć ROS-a, bez zaglądania
w kod węzłów. `-h` w każdym z nich opisuje parametry.

| pytanie | skrypt | argumenty |
|---|---|---|
| wejście do środowiska | `enter.sh` | — |
| co działa | `nodes.sh` | `[WĘZEŁ]` — bez argumentu lista, z argumentem szczegóły |
| jakie kanały | `topics.sh` | `[--no-types]` |
| kto nadaje, kto słucha | `who.sh` | `TOPIC` |
| co leci | `echo.sh` | `TOPIC [--once] [--field POLE] [--no-arr]` |
| jak szybko leci | `hz.sh` | `TOPIC [--window N]` |

Kolejność przy debugowaniu: `nodes` → `topics` → `who` → `echo`/`hz`.
Nazwy kanałów podaje się ze slashem, np. `/chatter`.

## Układ

    ws/src/          pakiety ROS — wszystko, co musi być pakietem, idzie tu
    projects/<nazwa> notatki, analiza offline i dane danego projektu
    scripts/init/    stawianie i rozbieranie środowiska
    scripts/ros2/    codzienna praca z żywym systemem
                     (skrypty maszynowe są w ~/scripts, nie tu)

Jeden colcon workspace na całe repo. Kolejny projekt = kolejny pakiet
w `ws/src/` plus katalog w `projects/`, nie nowe repo.

## Projekty

- `grab-fail-detection` — wykrywanie nieudanego chwytu z sygnałów celi
