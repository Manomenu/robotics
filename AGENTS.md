# ~/repos/robotics

## Maksyma

**Co skrypt tworzy poza repo, to `<nazwa>-revert.sh` musi cofnąć.**

Skrypt, który zmienia coś na maszynie — instaluje pakiet, tworzy kontener,
zapisuje plik w `$HOME` — ma bliźniaka z sufiksem `-revert.sh`, który
przywraca stan sprzed. Skrypt bez skutków ubocznych (`scripts/ros2/enter-ros2-container.sh`)
bliźniaka nie ma i to jest sygnał, że nic po sobie nie zostawia.

Konsekwencja: projekt nie dokłada się do `~/.dotfiles`. Wszystkie jego
zależności instalują się i odinstalowują skryptami z tego repo, bo tylko
wtedy usunięcie repo faktycznie kończy sprawę.

Reverty są idempotentne i mówią, czego nie ruszyły.

## Skąd się uruchamia

**Każdy skrypt w tym repo odpala się z Fedory, z twojego terminala.**

Nie ma kroku „najpierw wejdź do kontenera". Skrypt, który potrzebuje ROS-a,
sam robi `distrobox enter ros2 -- …` w środku i sam wychodzi. Ty zawsze
stoisz w tym samym miejscu.

Konsekwencja jest taka, że **nie ma czegoś takiego jak zły terminal**. Nie
musisz pamiętać, gdzie jesteś, ani czy dana sesja miała zrobiony `source`.
Skrypt albo działa, albo mówi, czego brakuje — nigdy nie robi czegoś innego
dlatego, że uruchomiłeś go z innego miejsca.

`scripts/ros2/enter-ros2-container.sh` nie jest wyjątkiem, tylko jedynym
skryptem, którego *celem* jest zostawić cię w środku. Reszta wchodzi
i wychodzi niezauważalnie.

### `scripts/lib/`

Skoro każdy skrypt sam wchodzi do kontenera, to wejście powtarzało się
w dziewięciu plikach, a nazwa kontenera stała na sztywno w ośmiu. Wspólna
część siedzi w `scripts/lib/container.sh` — **bibliotece, nie poleceniu**:
`source`ują ją inne skrypty, a uruchomiona wprost odmawia i mówi dlaczego.

    require-distrobox-installed        przerywa, gdy nie ma distroboxa
    require-ros2-container             przerywa, gdy nie ma kontenera
    run-in-ros2-container "POLECENIE"  wykonaj w kontenerze
    enter-ros2-container               zostań w kontenerze

Nazwy mówią `ros2-container`, a nie `distrobox`, bo distrobox jest szczegółem
implementacji — gdyby kiedyś zamienić go na gołe `podman exec`, te nazwy
zostaną prawdziwe. Nazwa `require-distrobox-installed` jest wyjątkiem
świadomym: ona dotyczy właśnie narzędzia, nie kontenera.

`run-in-ros2-container` i `enter-ros2-container` używają `exec`, więc muszą
być **ostatnią** instrukcją skryptu. Kod wyjścia polecenia z kontenera staje
się kodem wyjścia skryptu, co jest tu pożądane: `-h`, błędny argument i błąd
z wnętrza kontenera dają rozróżnialne kody.

### `scripts/inside-distrobox/`

Wyjątek jest jeden i ma własne drzewo. Skrypt, który **musi** wykonać się
wewnątrz kontenera, leży w `scripts/inside-distrobox/` — w podkatalogu
odbijającym miejsce, w którym leżałby po stronie hosta:

    scripts/init/create-container-for-ros2.sh          ← wołasz to z Fedory
    scripts/inside-distrobox/init/install-ros2-in-container.sh   ← to woła tamten

Nazwa katalogu zastępuje dawne `.internal/` i mówi więcej: nie „nie wołaj
tego ręcznie", tylko konkretnie **„tego nie da się wywołać stąd, gdzie
stoisz"**.

**Te same nazwy po obu stronach granicy są celowe.** Para

    scripts/init/install-ros2-in-container.sh                   ← wołasz to
    scripts/inside-distrobox/init/install-ros2-in-container.sh   ← to robi robotę

to jedna czynność widziana z dwóch stron: ta po stronie hosta tylko wchodzi
i deleguje, ta w środku wykonuje. Gdyby nazwy się różniły, trzeba by pamiętać
mapowanie; przy identycznych wystarczy pamiętać regułę o katalogu. Skrypty stamtąd sprawdzają to same — `install-ros2-in-container.sh`
odmawia startu, gdy nie widzi `/run/.containerenv`. Bez tego uruchomiony
na Fedorze próbowałby aptem zmienić hosta, a tego żaden revert by nie cofnął.

Reguła w obie strony: skrypt wymagający kontenera **musi** leżeć pod
`inside-distrobox/`, i żaden inny skrypt tam leżeć nie może.

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

Dzięki temu z samej nazwy wiadomo, czy polecenie odda ci terminal, czy nie.

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
- Kontener `ros2` jest granicą czystości: ROS, apt i wszystkie
  nieprzewidziane zależności żyją w nim, nie na Fedorze.
- Katalog domowy jest z kontenerem **współdzielony**. Nic z kontenera nie
  pisze do `$HOME` — sourcing ROS-a idzie do `/etc/profile.d/ros2.sh`,
  czyli do systemu plików kontenera.

## Układ

    ws/src/                  pakiety ROS — wszystko, co MUSI być pakietem
    projects/<nazwa>/        notatki, analiza offline, dane danego projektu
    scripts/init/               jednorazowe postawienie środowiska (każdy z revertem)
    scripts/dev/                codzienna pętla pracy nad kodem
    scripts/ros2/               oglądanie żywego systemu (bez skutków ubocznych)
    scripts/lib/                wspólny kod — source'owany, nie uruchamiany
    scripts/inside-distrobox/   jedyne, czego NIE odpalasz z Fedory

Podkatalog `scripts/` dzieli się **częstotliwością i skutkiem**, nie tematem:

- `init/` — raz na maszynę, zmienia Fedorę i podmana. Każdy ma revert.
- `dev/` — bez końca, po każdej zmianie w `ws/src`. Pisze wyłącznie w repo,
  więc revert kasuje artefakty budowy, a nie odinstalowuje cokolwiek.
- `ros2/` — bez końca, nie zmienia niczego. Dlatego jako jedyny nie ma
  revertów i to jest sygnał, nie przeoczenie.

Nazwy katalogów pilnują też cudzych znaczeń: `dev/`, a nie `control/`,
bo „control" w robotyce to warstwa sterowania (`ros2_control`, regulatory)
i taki katalog czytałoby się jako sterowniki napędów.

Jeden colcon workspace na całe repo. Kolejny projekt to kolejny pakiet
w `ws/src/` plus katalog w `projects/`, nie nowe repo.
