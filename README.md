# robotics

Nauka robotyki przez jeden projekt na raz. Wszystko, co dotyczy ROS-a,
żyje w kontenerze `ros2` (Ubuntu 24.04) — Fedora zostaje czysta.

**Wszystkie polecenia poniżej odpalasz ze swojego terminala na Fedorze.**
Skrypty same wchodzą do kontenera; nie musisz nigdzie wchodzić przed nimi.

## Start

    scripts/fedora/install-distrobox.sh              raz na maszynę
    scripts/container/create-container-for-ros2.sh   raz: pusty kontener (sekundy)
    scripts/container/install-ros2-in-container.sh   raz: ROS 2 Jazzy (~5 GB, kwadrans)
    scripts/dev/ros2/enter-ros2-container.sh             codziennie: wejście do środowiska
    scripts/dev/build-colcon-workspace.sh            po każdej zmianie w ws/src

Każdy z nich kończy się wypisaniem następnego kroku, więc kolejności nie
trzeba pamiętać — wystarczy czytać, co mówi ostatni uruchomiony.

## Podział scripts/

Katalog mówi, **czego dotyczy** skrypt, a nie jak bardzo jest zaawansowany:

| katalog | czego dotyczy | jak często |
|---|---|---|
| `fedora/` | twoja Fedora | raz na maszynę |
| `container/` | cykl życia kontenera `ros2`: powstaje, chodzi, stoi, znika | raz, plus stop/status kiedy chcesz |
| `inside-distrobox/` | kod wykonywany **w środku** kontenera; ścieżka odbija stronę hosta | wołany przez inne skrypty |
| `dev/` | kod w tym repo | po każdej zmianie w `ws/src` |
| `ros2/` | żywy system ROS-a | bez końca |
| `lib/` | wspólny kod — `source`owany, nie uruchamiany | — |

## scripts/fedora — jedyne, co zmienia twój system

| skrypt | co robi | co po nim zostaje | cofa |
|---|---|---|---|
| `install-distrobox.sh` | `dnf install distrobox` | pakiet na Fedorze | `install-distrobox-revert.sh` |

## scripts/container — cykl życia kontenera

| skrypt | co robi | cofa |
|---|---|---|
| `create-container-for-ros2.sh` | **pusty** kontener `ros2` (Ubuntu 24.04) | `create-container-for-ros2-revert.sh` |
| `install-ros2-in-container.sh` | ROS 2 Jazzy + colcon w tym kontenerze | — patrz niżej |
| `show-ros2-container-status.sh` | czy istnieje, czy chodzi, ile waży — **bez uruchamiania go** | — (nic nie zmienia) |
| `stop-ros2-container.sh` | zatrzymuje, nic nie kasując; najpierw sprząta osierocone sesje exec | — (`enter` wystartuje go z powrotem) |

`install-ros2-in-container.sh` jako jedyny tutaj nie ma własnego revertu,
i to jest celowe: wszystko, co instaluje, żyje w kontenerze i ginie razem
z nim. Cofa je `create-container-for-ros2-revert.sh`, który przy okazji
sprząta `~/.ros` i `~/.colcon` ze współdzielonego katalogu domowego.

**Kontener uruchamia się sam.** Nie ma skryptu `start-` i nie jest to
przeoczenie: `distrobox enter` startuje zatrzymany kontener, zanim do niego
wejdzie. Startuje go więc ten skrypt, który akurat pierwszy go potrzebuje —
choćby `list-topics.sh`. Zatrzymanie jest jawne, bo tylko ono wymaga decyzji.

## scripts/inside-distrobox — jedyne, czego nie odpalasz sam

Wszystko inne w tym repo uruchamiasz **z Fedory** — skrypty same wchodzą do
kontenera i same z niego wychodzą. Tu leży wyjątek: kod, który musi wykonać
się w środku. Ścieżka odbija miejsce po stronie hosta.

| skrypt | woła go | co robi |
|---|---|---|
| `container/install-ros2-in-container.sh` | `scripts/container/install-ros2-in-container.sh` | instaluje ROS 2 Jazzy + colcon; odmawia startu poza kontenerem |

## scripts/lib — wspólny kod, nie polecenia

`container.sh` trzyma nazwę kontenera, obraz i cztery funkcje, których używa
reszta skryptów: `require-distrobox-installed`, `require-ros2-container`,
`run-in-ros2-container "POLECENIE"`, `enter-ros2-container`. Uruchomiona
wprost odmawia — to biblioteka do `source`owania. Nazwę kontenera zmienia
się tutaj i tylko tutaj.

## scripts/dev — codzienna pętla pracy nad kodem

W przeciwieństwie do `init/` odpalane bez końca: po każdej zmianie w `ws/src`.

| skrypt | co robi | co po nim zostaje | cofa |
|---|---|---|---|
| `build-colcon-workspace.sh` | `colcon build --symlink-install` w kontenerze | `ws/{build,install,log}` — tylko w repo, maszyny nie dotyka | `build-colcon-workspace-revert.sh` |

Pełne wycofanie, w tej kolejności:

    scripts/dev/build-colcon-workspace-revert.sh
    scripts/container/create-container-for-ros2-revert.sh
    scripts/fedora/install-distrobox-revert.sh
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
