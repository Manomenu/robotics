# ~/repos/robotics

## Maksyma

**Co skrypt tworzy poza repo, to `<nazwa>-revert.sh` musi cofnąć.**

Skrypt, który zmienia coś na maszynie — instaluje pakiet, tworzy kontener,
zapisuje plik w `$HOME` — ma bliźniaka z sufiksem `-revert.sh`, który
przywraca stan sprzed. Skrypt bez skutków ubocznych (`scripts/dev/enter-devcontainer.sh`)
bliźniaka nie ma i to jest sygnał, że nic po sobie nie zostawia.

Konsekwencja: projekt nie dokłada się do `~/.dotfiles`. Wszystkie jego
zależności instalują się i odinstalowują skryptami z tego repo, bo tylko
wtedy usunięcie repo faktycznie kończy sprawę.

Reverty są idempotentne i mówią, czego nie ruszyły.

## Skąd się uruchamia

**Każdy skrypt pracujący z ROS-em działa i z Fedory, i z wnętrza kontenera.**

Wcześniej obowiązywała reguła „wyłącznie z Fedory", a skrypty uruchomione
w środku odmawiały startu. Powód był techniczny: opakowanie użyte w kontenerze
próbowałoby wejść do kontenera z kontenera. To było ograniczenie helpera,
nie właściwość problemu.

Dziś `run-in-devcontainer` **pyta, gdzie stoi**, i wybiera drogę:

    z Fedory     ->  podman exec do kontenera
    z kontenera  ->  wprost, bo już jesteśmy na miejscu

Obie drogi kończą się na `bash -lc`, czyli na powłoce logowania czytającej
`/etc/profile.d/ros2.sh`. To nie są dwa podobne wywołania, tylko jedno
polecenie w dwóch miejscach — dlatego wynik jest identyczny po obu stronach
(sprawdzone: `list-topics.sh` daje ten sam wydruk stąd i stamtąd).

Rozgałęzienie stoi **w jednym miejscu**. Dziewięć skryptów w `dev/` dostaje
pracę po obu stronach za darmo i żaden z nich nie wie, że granica istnieje.
Warunkiem jest to, że repo jest zamontowane pod tą samą ścieżką co na
Fedorze — dzięki temu `REPO_PATH` policzony ze ścieżki skryptu jest
prawdziwy w obu światach i nie ma czego tłumaczyć.

Konsekwencja jest ta sama co przedtem, ale teraz dosłowna: **nie ma czegoś
takiego jak zły terminal.** Wcześniej nie było, bo skrypt odmawiał. Teraz
nie ma, bo skrypt działa.

### Wyjątek: skrypty o kontenerze

Skrypt, który **dotyczy kontenera z zewnątrz** — stawia go, usuwa, zatrzymuje,
pyta podmana o stan — w środku nie ma czego zrobić, bo tam nie ma ani podmana,
ani `devcontainer` CLI. Takie skrypty wołają `require-fedora-host` i odmawiają,
mówiąc dlaczego. To jest `fedora/`, `container/` i `dev/enter-devcontainer.sh`
(do kontenera wchodzi się tylko z zewnątrz — w środku nie ma dokąd).

Reguła w obie strony: **`require-fedora-host` woła się wtedy i tylko wtedy,
gdy skrypt mówi o kontenerze. Skrypt mówiący o ROS-ie nie woła go nigdy.**

### `scripts/lib/`

Skoro każdy skrypt sam trafia do kontenera, to wejście powtarzało się
w dziewięciu plikach, a nazwa kontenera stała na sztywno w ośmiu. Wspólna
część siedzi w `scripts/lib/container.sh` — **bibliotece, nie poleceniu**:
`source`ują ją inne skrypty, a uruchomiona wprost odmawia i mówi dlaczego.

    inside-devcontainer              czy jesteśmy w środku (tylko pyta)
    require-fedora-host              przerywa, gdy jesteś W kontenerze
    require-devcontainer-cli         przerywa, gdy nie ma `devcontainer`
    require-devcontainer             przerywa, gdy nie ma kontenera
    run-in-devcontainer "POLECENIE"  wykonaj tam, gdzie trzeba
    enter-devcontainer               zostań w kontenerze

`inside-devcontainer` jest osobno, choć ma jedną linijkę, bo **pytanie
i decyzja to dwie różne rzeczy**: `require-fedora-host` odmawia,
`run-in-devcontainer` wybiera drogę, a obie potrzebują tej samej odpowiedzi.
Nazwa kontenera i nazwa jego użytkownika muszą zgadzać się z
`.devcontainer/devcontainer.json` — to jedyne miejsce w repo, gdzie te dwa
światy się spotykają.

Różnica między dwiema funkcjami wchodzącymi jest celowa. `run-in-devcontainer`
**nie** używa `exec` — wykonuje polecenie i wraca, więc skrypt może po nim
wypisać następny krok. Kod wyjścia dochodzi normalnie: przy `set -e` błąd
w kontenerze kończy skrypt tym samym kodem (sprawdzone: `exit 42` w kontenerze
daje 42 na Fedorze), więc podpowiedź „Dalej" nie pojawi się po niepowodzeniu.
`enter-devcontainer` używa `exec`, bo to przekazanie powłoki, a nie
wywołanie polecenia — nic po nim nie ma się wykonać.

**Ta sama nauczka wyszła tu dwa razy.** Pierwsza wersja helpera miała `exec`
w obu funkcjach i przez to dwa skrypty musiały go omijać, wołając wejście
wprost. Druga odmawiała pracy w kontenerze i przez to połowa repo była
bezużyteczna z edytora. Za każdym razem objaw wyglądał jak „taki już jest
ten problem", a był ograniczeniem wspólnego kodu. Reguła: **gdy skrypt omija
wspólny kod albo odmawia bez powodu fizycznego, najpierw sprawdź, czy to nie
wspólny kod jest za wąski.**

### Dawne `scripts/inside-distrobox/`

Katalog zniknął przy przejściu z distroboxa na devcontainer i nie wróci.
Trzymał skrypty, które **musiały** wykonać się w środku — głównie instalację
ROS-a w świeżym kontenerze. Dziś to robi `.devcontainer/Containerfile` przy
budowie obrazu, czyli deklaratywnie i raz, zamiast skryptem po fakcie. Reszta
skryptów nie potrzebuje osobnego drzewa, bo działa po obu stronach.

## Nazewnictwo skryptów

Nazwa ma odpowiadać na pytanie, które zadaje się patrząc na `ls`: **co ten
skrypt zostawi po sobie na mojej maszynie?** Sam czasownik tego nie mówi.
`create.sh` i `build.sh` przeszły ten test dopiero po otwarciu pliku — to
znaczy, że go nie przeszły.

Trzy reguły, w tej kolejności:

1. **Rzeczownik, nie czynność.** Nazwa nazywa rzecz, która powstaje:
   `create-container`, nie `create`. `build-colcon-workspace`, nie `build`
   — bo „workspace" samo w sobie znaczy też VS Code, cargo i npm.
2. **Miejsce, jeśli jest niejednoznaczne.** Ten sam czasownik znaczy co
   innego na Fedorze i w kontenerze, więc miejsce wchodzi do nazwy:
   `install-ros2-in-container` — bo `install-ros2` na hoście byłoby
   dokładnie tym, czego to repo ma unikać. Podobnie `-for-ros2` mówi,
   czyj jest ten kontener, gdy kiedyś stanie obok niego drugi.
3. **Sufiks `-revert.sh` doklejany na końcu całej nazwy**, nigdy w środku:
   `create-container-for-ros2-revert.sh`. Dzięki temu bliźniaki sortują
   się obok siebie i widać gołym okiem, któremu skryptowi brakuje pary.

Cena jest taka, że nazwy są długie, a kolejność alfabetyczna przestaje być
kolejnością uruchamiania. Kolejność jest opisana w README i tam jej się
szuka — nazwy służą do rozpoznawania, nie do porządkowania.

### Skrypty, które nic nie tworzą

Reguła „rzeczownik zamiast czynności" dotyczy skryptów, które coś zostawiają
po sobie. Skrypty w `ros2/` nie zostawiają nic, więc ich nazwa mówi, **co
zobaczysz na ekranie**. Czasownik na początku jest częścią kontraktu:

    enter-     zmienia twoją sesję — zostajesz w środku
    list-      wypisuje, co istnieje, i kończy
    show-      szczegóły jednej wskazanej rzeczy, i kończy
    print-     strumień, leci do Ctrl+C
    measure-   mierzy i podaje liczby, też do Ctrl+C
    run-       uruchamia proces i trzyma terminal do Ctrl+C
    set-       zmienia stan działającego węzła i wraca

Dzięki temu z samej nazwy wiadomo, czy polecenie odda ci terminal, czy nie.

`run-` i `set-` zmieniają stan, a mimo to nie mają revertów — bo zmieniają
stan **procesu**, nie maszyny. Ctrl+C i restart węzła cofają wszystko.
Maksyma dotyczy tego, co przeżywa proces; tutaj nic nie przeżywa. Stąd
korekta wcześniejszego opisu `dev/ros2/`: to nie jest katalog „tylko czyta",
tylko „nic nie zostawia po sobie".

Skrypt nie robi dwóch rzeczy naraz. Dawne `nodes.sh` bez argumentu listowało,
a z argumentem pokazywało szczegóły; dawne `create-container-for-ros2.sh`
tworzyło kontener i od razu instalowało w nim ROS-a. W obu wypadkach żadna
nazwa nie mogła tego uczciwie opisać, bo nazwa opisuje jedną rzecz. Stąd
`list-running-nodes.sh` / `show-node-connections.sh` oraz
`create-container-for-ros2.sh` / `install-ros2-in-container.sh` osobno.

Zamiast łączyć kroki, **każdy skrypt kończy wypisaniem następnego** wraz ze
ścieżką do niego. Kolejność mieszka w komunikatach, a nie w pamięci — i nie
rozjeżdża się po zmianie nazw, bo widać ją przy pierwszym uruchomieniu.

## Granice

- `~/scripts` — maszyna (przeżywa projekty). `repo/scripts` — projekt.
  Test: czy przyda się w NASTĘPNYM projekcie? VS Code i rozszerzenie
  Dev Containers — tak, więc siedzą w `~/scripts/fedora/init/install-vsc.sh`.
  `devcontainer` CLI i obraz z ROS-em — nie, więc są tutaj. Konsekwencja:
  reverty tego repo nie usuwają narzędzi maszyny i nie powinny próbować.
- Kontener `ros2` jest granicą czystości: ROS, apt i wszystkie
  nieprzewidziane zależności żyją w nim, nie na Fedorze.
- Katalog domowy jest z kontenerem **współdzielony**. Nic z kontenera nie
  pisze do `$HOME` — sourcing ROS-a idzie do `/etc/profile.d/ros2.sh`,
  czyli do systemu plików kontenera.

## Układ

    ws/src/                  pakiety ROS — wszystko, co MUSI być pakietem
    projects/<nazwa>/        notatki, analiza offline, dane danego projektu

    scripts/fedora/             twoja Fedora — jedyne, co dotyka systemu
    scripts/container/          cykl życia kontenera: powstaje, chodzi, stoi, znika
    scripts/lib/                wspólny kod — source'owany, nie uruchamiany

    scripts/dev/                CODZIENNA PRACA
    scripts/dev/ros2/               oglądanie żywego systemu ROS-a

Podkatalog `scripts/` nazywa **rzecz, której skrypt dotyczy** — Fedory,
kontenera, kodu, żywego ROS-a. Nie „etap" i nie „poziom trudności".
Poprzedni podział (`init/`) mówił *kiedy* się to odpala, i rozpadł się
dokładnie wtedy, gdy doszły stop i status: „raz na maszynę" przestało być
prawdą, choć kontenera dotyczyły tak samo jak `create`.

### Częstotliwość: `dev/` kontra reszta

Nazwa katalogu mówi, czego skrypt dotyczy. Ale **`dev/` niesie jeszcze jedną
informację, której nie niesie żaden inny katalog: że użyjesz tego dzisiaj.**

Poza `dev/` wszystko jest jednorazowe albo prawie. `fedora/` odpalisz raz
w życiu tej maszyny. `container/` raz przy stawianiu, potem najwyżej `stop`
i `status`, gdy sam się nad tym zastanowisz. `inside-distrobox/` nigdy —
woła je co innego. `lib/` w ogóle się nie odpala.

W `dev/` jest odwrotnie: `build-colcon-workspace.sh` po każdej zmianie
w `ws/src`, a `dev/ros2/*` bez przerwy, przez cały czas pracy. To dlatego
`ros2/` siedzi **wewnątrz** `dev/`, a nie obok: oglądanie działającego
systemu nie jest osobną czynnością od pisania go, tylko jego drugą połową.
Piszesz, budujesz, patrzysz, poprawiasz — i te trzy ostatnie kroki są
w jednym katalogu.

Praktyczna konsekwencja: **kompletując polecenie ścieżką, zaczynasz od
`scripts/dev/` i tam jest wszystko, czego potrzebujesz w trakcie sesji.**
Reszta drzewa to konfiguracja, do której wracasz raz na kilka miesięcy albo
gdy coś się psuje. Gdyby kiedyś doszedł skrypt używany codziennie, a nie
dotyczący ani kodu, ani żywego ROS-a — trafia do `dev/`, bo częstotliwość
wygrywa z tematem dopiero na tym poziomie.

Skutki nadal widać w rewertach, tylko teraz jako konsekwencję, nie kryterium:
`fedora/` i `container/` mają bliźniaki `-revert.sh`, `dev/` kasuje artefakty
budowy, `dev/ros2/` nie ma żadnego — bo nic tam nie przeżywa procesu.

Nazwy katalogów pilnują też cudzych znaczeń: `dev/`, a nie `control/`,
bo „control" w robotyce to warstwa sterowania (`ros2_control`, regulatory)
i taki katalog czytałoby się jako sterowniki napędów.

**Kontener startuje niejawnie.** Nie ma skryptu `start-`, bo `distrobox enter`
sam uruchamia zatrzymany kontener. Skutek uboczny wart zapamiętania: nawet
`scripts/dev/ros2/list-topics.sh`, opisany jako „tylko czyta", potrafi wystartować
kontener i wypisać przy tym ścianę logów distroboxa. Jedyny sposób sprawdzenia
stanu bez zmieniania go to `container/show-devcontainer-status.sh`, który
pyta wyłącznie podmana. Zatrzymanie jest jawne, bo tylko ono wymaga decyzji.

Jeden colcon workspace na całe repo. Kolejny projekt to kolejny pakiet
w `ws/src/` plus katalog w `projects/`, nie nowe repo.
