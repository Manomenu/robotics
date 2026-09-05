# ~/repos/robotics

## Maksyma

**Co skrypt tworzy poza repo, to `<nazwa>-revert.sh` musi cofnąć.**

Skrypt, który zmienia coś na maszynie — instaluje pakiet, tworzy kontener,
zapisuje plik w `$HOME` — ma bliźniaka z sufiksem `-revert.sh`, który
przywraca stan sprzed. Skrypt bez skutków ubocznych (`scripts/ros2/enter.sh`)
bliźniaka nie ma i to jest sygnał, że nic po sobie nie zostawia.

Konsekwencja: projekt nie dokłada się do `~/.dotfiles`. Wszystkie jego
zależności instalują się i odinstalowują skryptami z tego repo, bo tylko
wtedy usunięcie repo faktycznie kończy sprawę.

Reverty są idempotentne i mówią, czego nie ruszyły.

## Nazewnictwo skryptów

Nazwa ma odpowiadać na pytanie, które zadaje się patrząc na `ls`: **co ten
skrypt zostawi po sobie na mojej maszynie?** Sam czasownik tego nie mówi.
`create.sh` i `build.sh` przeszły ten test dopiero po otwarciu pliku — to
znaczy, że go nie przeszły.

Trzy reguły, w tej kolejności:

1. **Rzeczownik, nie czynność.** Nazwa nazywa rzecz, która powstaje:
   `create-container`, nie `create`. `build-workspace`, nie `build`.
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

### `init/.internal/`

Skrypt, którego **nie uruchamia człowiek**, idzie do `init/.internal/`.
Tam leży `install-ros2-in-container.sh`: woła go `create-container-for-ros2.sh`
już wewnątrz kontenera, a uruchomiony z hosta zainstalowałby ROS-a na
Fedorze — czyli złamałby maksymę bez żadnego revertu, który by to cofnął.

Kropka w nazwie katalogu jest celowa: takie skrypty nie mają wpadać pod
rękę przy dopełnianiu ścieżek. To nie jest ukrywanie, tylko oznaczenie,
że wywołanie ich wprost jest błędem, a nie opcją.

Skrypt w `.internal/` nie potrzebuje własnego revertu wtedy i tylko wtedy,
gdy wszystko, co tworzy, ginie razem z kontenerem.

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
    scripts/init/            stawianie i rozbieranie środowiska (każdy z revertem)
    scripts/init/.internal/  wołane przez inne skrypty, nie z ręki
    scripts/ros2/            oglądanie żywego systemu (bez skutków ubocznych)

Podział `scripts/` jest jednocześnie deklaracją: co leży w `init/`, zmienia
maszynę i musi mieć bliźniaka `-revert.sh`; co leży w `ros2/`, tylko czyta.

Jeden colcon workspace na całe repo. Kolejny projekt to kolejny pakiet
w `ws/src/` plus katalog w `projects/`, nie nowe repo.
