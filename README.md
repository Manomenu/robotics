# robotics

Nauka robotyki przez jeden projekt na raz. Wszystko, co dotyczy ROS-a,
żyje w kontenerze `ros2` (Ubuntu 24.04) — Fedora zostaje czysta.

**Wszystkie polecenia poniżej odpalasz ze swojego terminala na Fedorze.**
Skrypty same wchodzą do kontenera; nie musisz nigdzie wchodzić przed nimi.

## Start

    scripts/init/install-distrobox.sh          raz na maszynę
    scripts/init/create-container-for-ros2.sh  raz: kontener + ROS 2 Jazzy (~5 GB, kwadrans)
    scripts/ros2/enter-ros2-container.sh       codziennie: wejście do środowiska
    scripts/dev/build-colcon-workspace.sh      po każdej zmianie w ws/src

## scripts/init — jednorazowe postawienie środowiska

Odpalane raz na maszynę. Kolejność uruchamiania jest kolejnością tabeli.
Nazwa każdego skryptu mówi, co on **tworzy**: distroboxa, kontener, ROS-a
w kontenerze.

| skrypt | co robi | co po nim zostaje | cofa |
|---|---|---|---|
| `install-distrobox.sh` | `dnf install distrobox` | pakiet na Fedorze | `install-distrobox-revert.sh` |
| `create-container-for-ros2.sh` | kontener `ros2` + ROS 2 Jazzy | kontener, obraz, `~/.ros`, `~/.colcon` | `create-container-for-ros2-revert.sh` |

## scripts/inside-distrobox — jedyne, czego nie odpalasz sam

Wszystko inne w tym repo uruchamiasz **z Fedory** — skrypty same wchodzą do
kontenera i same z niego wychodzą. Tu leży wyjątek: kod, który musi wykonać
się w środku. Ścieżka odbija miejsce po stronie hosta.

| skrypt | woła go | co robi |
|---|---|---|
| `init/install-ros2-in-container.sh` | `scripts/init/create-container-for-ros2.sh` | instaluje ROS 2 Jazzy + colcon w kontenerze; odmawia startu poza nim |

## scripts/dev — codzienna pętla pracy nad kodem

W przeciwieństwie do `init/` odpalane bez końca: po każdej zmianie w `ws/src`.

| skrypt | co robi | co po nim zostaje | cofa |
|---|---|---|---|
| `build-colcon-workspace.sh` | `colcon build --symlink-install` w kontenerze | `ws/{build,install,log}` — tylko w repo, maszyny nie dotyka | `build-colcon-workspace-revert.sh` |

Pełne wycofanie, w tej kolejności:

    scripts/dev/build-colcon-workspace-revert.sh
    scripts/init/create-container-for-ros2-revert.sh
    scripts/init/install-distrobox-revert.sh
    rm -rf ~/repos/robotics

## scripts/ros2 — oglądanie żywego systemu, nic nie zmieniają

Odpalasz je **z Fedory** — same wchodzą do kontenera. `-h` w każdym opisuje
parametry. Czasownik na początku nazwy mówi, czego się spodziewać:

| prefiks | co robi skrypt |
|---|---|
| `enter-` | zmienia twoją sesję — zostajesz w środku, aż wyjdziesz |
| `list-` | wypisuje, co istnieje, i kończy |
| `show-` | pokazuje szczegóły jednej wskazanej rzeczy i kończy |
| `print-` | strumień — leci, dopóki nie przerwiesz Ctrl+C |
| `measure-` | mierzy przez chwilę i podaje liczby — też do Ctrl+C |

| pytanie | skrypt | argumenty |
|---|---|---|
| jak wejść do środowiska | `enter-ros2-container.sh` | — |
| co w ogóle działa | `list-running-nodes.sh` | — |
| co ten węzeł nadaje i czego słucha | `show-node-connections.sh` | `WĘZEŁ`, np. `/talker` |
| jakie kanały istnieją | `list-topics.sh` | `[--no-types]`, domyślnie z typami |
| kto nadaje i kto słucha na kanale | `show-topic-connections.sh` | `TOPIC`, np. `/chatter` |
| co konkretnie tamtędy leci | `print-topic-messages.sh` | `TOPIC [--once] [--field POLE] [--no-arr]` |
| jak szybko to leci | `measure-topic-rate.sh` | `TOPIC [--window N]` |

Ten sam graf połączeń widać z dwóch stron: `show-node-connections.sh` patrzy
od strony węzła („co ja nadaję"), `show-topic-connections.sh` od strony kanału
(„kto mnie zasila"). Przy diagnozie „węzły żyją, a się nie widzą" potrzebne
są oba.
