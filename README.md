# robotics

Nauka robotyki przez jeden projekt na raz. Wszystko, co dotyczy ROS-a,
żyje w kontenerze `ros2` (Ubuntu 24.04) — Fedora zostaje czysta.

## Start

    scripts/ros2-init.sh     # raz: kontener + ROS 2 Jazzy (~5 GB, kwadrans)
    scripts/ros2-enter.sh    # codziennie: wejście do środowiska
    scripts/ros2-build.sh    # budowa ws/ (colcon)
    scripts/ros2-clean.sh    # usunięcie kontenera i artefaktów budowy

## Układ

    ws/src/          pakiety ROS — wszystko, co musi być pakietem, idzie tu
    projects/<nazwa> notatki, analiza offline i dane danego projektu
    scripts/         obsługa środowiska TEGO repo
                     (skrypty maszynowe są w ~/scripts, nie tu)

Jeden colcon workspace na całe repo. Kolejny projekt = kolejny pakiet
w `ws/src/` plus katalog w `projects/`, nie nowe repo.

## Projekty

- `grab-fail-detection` — wykrywanie nieudanego chwytu z sygnałów celi
