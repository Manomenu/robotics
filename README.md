# robotics

Nauka robotyki przez jeden projekt na raz. Wszystko, co dotyczy ROS-a, żyje
w kontenerze opisanym przez `.devcontainer/` — Fedora zostaje czysta.

---

## Pierwszy raz

Cztery kroki, każdy wypisuje następny, więc kolejności nie musisz pamiętać.

    ~/scripts/fedora/init/install-vsc.sh         VS Code + rozszerzenia (poza tym repo)
    scripts/fedora/install-devcontainer-cli.sh   devcontainer CLI (npm, globalnie)
    scripts/container/create-devcontainer.sh     obraz + kontener (~7 GB, kilka minut)
    code ~/repos/robotics                        → F1 → Reopen in Container
    scripts/dev/build-colcon-workspace.sh        pierwszy build

Krok pierwszy jest **spoza tego projektu** — VS Code i rozszerzenie Dev Containers
to narzędzia maszyny, przydatne w każdym projekcie z `.devcontainer/`, więc żyją
w `~/scripts/`. Reverty tego repo ich nie usuwają i nie powinny.

Sprawdzenie, że działa: w `ws/src/<pakiet>/…` import `rclpy` nie jest czerwony,
a `scripts/dev/ros2/list-topics.sh` z Fedory wypisuje `/rosout`.

---

## Dwa światy i podział pracy

To jest najważniejsza rzecz do zrozumienia w tym repo.

| gdzie | co tam robisz | jak wołasz ROS-a |
|---|---|---|
| **VS Code** (w kontenerze) | piszesz kod, uruchamiasz węzły, debugujesz | wprost: `ros2 run …`, `colcon build` |
| **Ghostty** (Fedora) | zaglądasz, co robi system; sprzątasz; stawiasz środowisko | przez `scripts/` |

**Skrypty z `scripts/` odpala się wyłącznie z Fedory.** Uruchomione w kontenerze
odmawiają i mówią, żeby użyć gołej komendy — bo tam opakowanie nie ma sensu.

Powód takiego podziału: gdy w VS Code masz uruchomiony węzeł, nie chcesz go
przerywać, żeby sprawdzić, co publikuje. Otwierasz Ghostty i pytasz stamtąd.

---

## Typowa sesja

**1. Piszesz** — w VS Code, w `ws/src/<pakiet>/`.

**2. Budujesz** — w terminalu VS Code:

    colcon build --symlink-install

`--symlink-install` sprawia, że przy zmianach w Pythonie wystarczy restart
węzła, bez ponownego budowania. Przy C++ i tak musisz przebudować.

**3. Uruchamiasz** — w drugim terminalu VS Code:

    ros2 run <pakiet> <węzeł>

Jeśli dostaniesz „package not found" tuż po pierwszym buildzie — otwórz nowy
terminal. Stary nie widzi `ws/install/`, bo powstało po jego starcie.

**4. Oglądasz** — z Ghostty, nie ruszając tamtych terminali:

    scripts/dev/ros2/list-running-nodes.sh
    scripts/dev/ros2/list-topics.sh
    scripts/dev/ros2/print-topic-messages.sh /vacuum_pressure
    scripts/dev/ros2/measure-topic-rate.sh /vacuum_pressure

**5. Kończysz** — kontener może chodzić dalej, nic nie kosztuje poza pamięcią.
Gdy chcesz go uśpić:

    scripts/container/stop-devcontainer.sh

---

## Kiedy przebudować kontener

| zmieniłeś | co zrobić |
|---|---|
| kod w `ws/src/` | `colcon build` |
| `.devcontainer/Containerfile` | **Rebuild Container** w VS Code, albo `create-devcontainer-revert.sh` + `create-devcontainer.sh` |
| `customizations` w `devcontainer.json` | wystarczy Reopen in Container |
| nic, a i tak nie działa | `build-colcon-workspace-revert.sh`, potem build od zera |

Nowy pakiet systemowy (apt) **dopisujesz do `Containerfile`**, nie instalujesz
w działającym kontenerze — inaczej zginie przy następnym odtworzeniu.

---

## Skrypty

Wszystkie mają `-h` z opisem parametrów. Wszystkie odpalasz z Fedory.

### `scripts/fedora/` — twój system, raz w życiu maszyny

| skrypt | co robi | cofa |
|---|---|---|
| `install-devcontainer-cli.sh` | `npm i -g @devcontainers/cli` — stawianie kontenera z terminala | `install-devcontainer-cli-revert.sh` |

Rozszerzenia Dev Containers **nie ma tutaj** — instaluje je
`~/scripts/fedora/init/install-vsc.sh` razem z resztą VS Code, bo to narzędzie
maszyny, a nie tego projektu. CLI i rozszerzenie robią to samo z dwóch stron:
pierwsze stawia kontener z Ghostty, drugie z edytora. Oba gadają z podmanem
przez `/usr/bin/docker` (pakiet `podman-docker`), więc nic nie trzeba przestawiać.

### `scripts/container/` — cykl życia kontenera

| skrypt | co robi | cofa |
|---|---|---|
| `create-devcontainer.sh` | stawia kontener z `.devcontainer/` | `create-devcontainer-revert.sh` |
| `show-devcontainer-status.sh` | stan, obraz, sesje — **bez uruchamiania kontenera** | — |
| `stop-devcontainer.sh` | zatrzymuje, nic nie kasując | — (wejście wystartuje go z powrotem) |

`show-devcontainer-status.sh` jest jedynym podglądem, który stanu nie zmienia:
pyta wyłącznie podmana. Każdy inny skrypt, wchodząc do kontenera, po drodze
go uruchomi.

### `scripts/dev/` — codzienna praca

| skrypt | co robi | cofa |
|---|---|---|
| `enter-devcontainer.sh` | oddaje ci powłokę w kontenerze, w katalogu repo | — |
| `build-colcon-workspace.sh` | `colcon build --symlink-install` bez wchodzenia | `build-colcon-workspace-revert.sh` |

### `scripts/dev/ros2/` — praca z żywym systemem

Czasownik w nazwie mówi dwie rzeczy: **czy polecenie odda ci terminal** i **czy
tylko patrzy, czy działa**.

| prefiks | oddaje terminal | zmienia coś |
|---|---|---|
| `list-`, `show-` | tak, od razu | nie |
| `print-`, `measure-` | nie, do Ctrl+C | nie |
| `run-` | nie, do Ctrl+C | **tak** — uruchamia proces |
| `set-` | tak, od razu | **tak** — zmienia działający węzeł |

Nic tutaj nie ma revertu i to jest celowe: `run-` kończy Ctrl+C, a `set-`
znika przy restarcie węzła. **Żadna z tych zmian nie przeżywa procesu**, więc
nie ma czego cofać — inaczej niż w `fedora/` i `container/`.

| co chcesz | skrypt | argumenty |
|---|---|---|
| uruchomić węzeł | `run-node.sh` | `PAKIET WĘZEŁ [--ros-args ...]` |
| zmienić parametr działającego węzła | `set-param.sh` | `WĘZEŁ PARAMETR WARTOŚĆ` |
| co w ogóle działa | `list-running-nodes.sh` | — |
| co ten węzeł nadaje i czego słucha | `show-node-connections.sh` | `WĘZEŁ`, np. `/talker` |
| jakie kanały istnieją | `list-topics.sh` | `[--no-types]` |
| kto nadaje i kto słucha na kanale | `show-topic-connections.sh` | `TOPIC` |
| co konkretnie tamtędy leci | `print-topic-messages.sh` | `TOPIC [--once] [--field POLE]` |
| jak szybko to leci | `measure-topic-rate.sh` | `TOPIC [--window N]` |

`run-node.sh` i `set-param.sh` podpowiadają, gdy nie wiesz, co podać:
`run-node.sh grip_monitor` wypisze węzły w pakiecie, `set-param.sh /vacuum_sensor`
wypisze parametry węzła.

Ten sam graf połączeń widać z dwóch stron: `show-node-connections` od strony
węzła („co ja nadaję"), `show-topic-connections` od strony kanału („kto mnie
zasila"). Przy diagnozie „węzły żyją, a się nie widzą" potrzebne są oba.

### `scripts/lib/`

`container.sh` — biblioteka, nie polecenie. Trzyma nazwę kontenera, jego
użytkownika i cztery funkcje wejścia. **Nazwa kontenera musi zgadzać się
z `--name` w `devcontainer.json`** — to jedyne miejsce, gdzie te dwa światy
są sprzęgnięte ręcznie.

---

## Gdy coś nie działa

| objaw | przyczyna | co zrobić |
|---|---|---|
| brak „Reopen in Container" w F1 | nie ma rozszerzenia | `~/scripts/fedora/init/install-vsc.sh` |
| `import rclpy` czerwony w VS Code | nie jesteś w kontenerze | F1 → Reopen in Container |
| `ros2: command not found` w Ghostty | to normalne — ROS jest tylko w kontenerze | użyj `scripts/dev/ros2/…` albo `enter-devcontainer.sh` |
| `package not found` tuż po buildzie | terminal starszy niż `ws/install/` | otwórz nowy terminal |
| węzły żyją, a się nie widzą | zwykle niedopasowane QoS | `show-topic-connections.sh TOPIC`, porównaj obie strony |
| pliki w `ws/build` mają złego właściciela | brak `--userns=keep-id` | sprawdź `runArgs` w `devcontainer.json` |
| skrypt mówi „jesteś wewnątrz kontenera" | odpalasz go z VS Code | użyj gołej komendy `ros2 …` |

---

## Sprzątanie

Pełne wycofanie, w tej kolejności — po nim po projekcie nie zostaje nic:

    scripts/dev/build-colcon-workspace-revert.sh    artefakty budowy w repo
    scripts/container/create-devcontainer-revert.sh kontener i obrazy (~7 GB)
    scripts/fedora/install-devcontainer-cli-revert.sh  devcontainer CLI
    rm -rf ~/repos/robotics

Zasada, na której to stoi: **co skrypt tworzy poza repo, to `-revert.sh` musi
cofnąć.** Dlatego projekt niczego nie dokłada do `~/.dotfiles` — wszystkie
zależności instalują się i odinstalowują skryptami stąd.

---

## Układ repo

    .devcontainer/     definicja środowiska (Containerfile + devcontainer.json)
    ws/src/            pakiety ROS — wszystko, co MUSI być pakietem
    ws/{build,install,log}   generowane przez colcon, w .gitignore
    projects/<nazwa>/  notatki, analiza offline, dane — ROS o tym nie wie
    scripts/           patrz wyżej

Jeden colcon workspace na całe repo. Kolejny projekt to kolejny pakiet
w `ws/src/` plus katalog w `projects/`, nie nowe repo.
