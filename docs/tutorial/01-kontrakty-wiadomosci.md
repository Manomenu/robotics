# Etap 01 — Kontrakty: własne interfejsy zamiast String

> Po tym etapie twój werdykt jest typem, który da się zwalidować, wykreślić
> i porównać z tym, co leży w nagraniu — a nie tekstem, który każdy parsuje po swojemu.

| | |
|---|---|
| wejście | stan repo z [roadmapy](./00-roadmapa.md): pakiet `grip_monitor`, `String` na `/grasp_verdict`, nagranie w `projects/grab-fail-detection/bags/chwyt-3-stany/` |
| czas | 2–3 wieczory |
| kończy się | `ros2 topic echo /grasp_verdict` pokazuje pola z nazwami, a `ros2 interface show` wypisuje listę dozwolonych stanów |

## Po ludzku: co to jest w twoim świecie

Słownik ogólny jest w [roadmapie](./00-roadmapa.md). Tu są pojęcia, które
zobaczysz dopiero w tym etapie.

| w robocie | z czym ci się skojarzy | gdzie analogia pęka |
|---|---|---|
| `.msg` + `rosidl` | `.proto` + `protoc` | z jednego pliku generuje C, C++ i Pythona naraz, a moduł pythonowy jest cienką nakładką na bibliotekę C — dlatego pakiet `ament_python` nie umie tego zbudować |
| pakiet `*_msgs` | osobny artefakt ze schematami (`*-api.jar`, klient z OpenAPI) | nie ma repozytorium artefaktów ani wersji semantycznej; obowiązuje to, co w tej chwili leży w `ws/install` na twoim dysku |
| hasz typu `RIHS01_…` | `schema id` ze Schema Registry | nikt go nie sprawdza przed wysłaniem i nikt nie odrzuci wiadomości; niezgodność poznajesz po ciszy |
| stałe w `.msg` (`uint8 SEALED=3`) | `enum` | to nie jest typ, tylko nazwana liczba — nic nie zabroni wpisać `7` |
| `ros2 interface show` | `GET /openapi.json`, `\d tabela` | pokazuje typ **zainstalowany u ciebie**, a nie ten, którym nadaje druga strona |
| `.srv` | wywołanie RPC | zawołane synchronicznie z callbacka, na domyślnym jednowątkowym executorze, zakleszcza węzeł — czekasz na samego siebie |

## Po co to — czego bez tego nie da się zrobić

Całe wyjście systemu przechodzi przez cztery linie w
`ws/src/grip_monitor/grip_monitor/grasp_monitor.py`:

```python
def publish_state_change(self, msg: str):
    str_msg = String()
    str_msg.data = '[state] ' + msg
    self.pub.publish(str_msg)
```

To nie jest wiadomość, tylko `print()` wypuszczony na sieć.

**Nie ma listy dozwolonych wartości.** Trzy wywołania wyżej podają `'open'`,
`'leak'`, `'sealed'`; czwarte mogłoby podać `'Sealed'` albo `'sealead'` i nic
nie mrugnie po żadnej stronie. Literówka jest poprawną wiadomością, a jedynym
źródłem prawdy o dozwolonych wartościach jest `grep` po tym pliku.

**Parser po drugiej stronie to `split()`**: `msg.data.split(' ')[1] == 'sealed'`.
Ten `[1]` istnieje wyłącznie dlatego, że ktoś dokleił `'[state] '`. Prefiks
jest formatowaniem logu, nie kontraktem — więc zmiana formatowania logu
wywala konsumenta w produkcji.

**Nie ma gdzie włożyć stempla.** Pierwsze pytanie o ten system brzmi „ile
trwa droga od spadku ciśnienia do werdyktu". Dziś odpowiedź wymagałaby
wepchnięcia liczby do tego samego stringa i wyparsowania jej u odbiorcy.
Czym stempel jest naprawdę — [etap 02](./02-czas-zdarzenia-stan.md).

**Nie da się tego wykreślić.** `rqt_plot` i PlotJuggler rysują liczby, więc
najważniejszy wykres tego projektu — ciśnienie i decyzja na jednej osi czasu
— jest dziś niemożliwy ([etap 05](./05-introspekcja-qos-narzedzia.md)).

**Nagranie jest już skażone.** W `bags/chwyt-3-stany/` leży 1062 wiadomości
`std_msgs/msg/String`. Żeby policzyć z nich cokolwiek — choćby „ile razy stan
się zmienił" — musisz parsować tekst sprzed miesięcy. To są dane
historyczne, a format wiadomości to ich schemat; wybierając `String`,
wybrałeś schemat „jedna kolumna tekstowa".

Zdanie, na którym stoi cały etap: **ROS nie daje ci żadnego miejsca na
walidację.** Nie ma middleware'u, filtra ani hooka „sprawdź przed wysłaniem".
Jedynym mechanizmem, który cokolwiek sprawdza, jest system typów. Co ma być
pilnowane, musi zostać typem — albo nie będzie pilnowane wcale.

## Dlaczego to ciekawe

Kontrakt w ROS 2 jest **adresowany treścią**: typ nie ma numeru wersji, ma
hasz policzony ze swojej struktury. Nazwa typu nie znaczy nic, znaczy struktura.

Konsekwencja zaskakuje ludzi z backendu: **twój `.msg` jest schematem danych,
których już nie kontrolujesz.** Nagranie sprzed pół roku nosi w metadanych
hasz z chwili nagrania, a twój dzisiejszy kod nosi hasz dzisiejszy. Gdy się
różnią, nagranie i kod przestają do siebie pasować i nikt cię o tym nie
powiadomi. To nie jest API, które da się zdeprecjonować i wyłączyć za
kwartał — to jest format pliku.

Drugi ładny pomysł: **zero jest wartością domyślną i nie da się tego
wyłączyć.** Każde pole nowej wiadomości jest wyzerowane, więc cokolwiek
przypiszesz do `0`, dostaniesz od każdego, kto zapomniał ustawić pole. Stąd
reguła widoczna w połowie publicznych interfejsów ROS-a: `0` to `UNKNOWN`,
nigdy stan poprawny. „Zapomniałem" i „otwarty" nie mogą wyglądać tak samo.

Trzeci: **akcja nie jest osobnym mechanizmem transportowym.** Pod spodem to
trzy usługi i dwa topiki, sklejone konwencją i wygenerowane z jednego pliku
`.action` — w `ros2 topic list` wyglądają na topiki, „których nie powinno
tam być".

## Dlaczego to trudne

**Objawem niezgodności jest cisza.** W backendzie dostajesz 400, 415 albo
wyjątek deserializacji z nazwą pola. Tutaj oba węzły żyją, `ros2 topic list`
pokazuje topic — i nic nie leci, bo nie ma warstwy, która miałaby wypisać
komunikat. Diagnoza to porównanie dwóch haszy gołym okiem.

**Podział na dwa pakiety nie jest oczywisty i nic ci go nie podpowie.**
Katalog `msg/` w pakiecie `ament_python` zostaje zignorowany bez ostrzeżenia:
build kończy się zielonym „Finished", a błąd wychodzi kilka kroków dalej, jako
`ModuleNotFoundError`.

**Zmiana interfejsu jest zaraźliwa.** Trzeba przebudować wszystko, co tego
typu używa, i zrestartować każdy działający proces. Proces niezrestartowany
trzyma starą wersję typu w pamięci i wygląda na całkowicie zdrowego — żywy,
publikujący, niedopasowany. To najgorszy z możliwych przypadków.

**Projektujesz publiczne API, którego nie zmienisz po cichu.** Nazwa pola
wpisana dziś siedzi w każdym nagraniu, jakie zrobisz.

**Sporo z tego to wiedza plemienna**: że `*_msgs` nie może zawierać kodu, że
`member_of_group` musi tam być, że `--symlink-install` — które oszczędza ci
przebudowy przy zmianach w Pythonie — **nie działa** dla generowanych
interfejsów. Żadna z tych rzeczy nie krzyczy, gdy jej brakuje.

## Model pojęciowy

### Trzy mechanizmy i kiedy który

|  | topic | usługa (`.srv`) | akcja (`.action`) |
|---|---|---|---|
| kształt rozmowy | jednokierunkowy strumień, wielu do wielu | żądanie → odpowiedź, jeden do jednego | cel → feedback… → wynik |
| kto zaczyna | nadawca, sam z siebie | klient | klient |
| czas trwania | bez końca | milisekundy, ma wrócić od razu | sekundy do minut |
| stan pośredni | brak | brak | jest: `feedback` i status celu |
| anulowanie | nie dotyczy | brak | jest, i serwer musi je obsłużyć |
| gdy nie ma drugiej strony | publikujesz w próżnię, zero informacji | wisisz; timeout piszesz sam | `wait_for_server()` zwraca `False` |
| u nas | `/vacuum_pressure` 50 Hz, `/grasp_verdict` | „podaj ostatni werdykt" | „wykonaj chwyt" — [etap 08](./08-tf2-urdf-ros2-control.md) |

Reguła decyzyjna: **topic**, gdy odpowiadasz na „co jest teraz" bez przerwy
i niezależnie od tego, czy ktoś słucha. **Usługa**, gdy ktoś pyta o coś
konkretnego i musi wiedzieć, że dostał właśnie swoją odpowiedź. **Akcja**, gdy
zadanie trwa i pytający może chcieć je przerwać. Przypadki graniczne rozstrzyga
jedno pytanie: **czy da się to sensownie anulować w połowie?** Jeśli pytanie ma
sens — akcja. Jeśli nie ma, bo operacja trwa 2 ms — usługa. Jeśli nikt nie pyta,
tylko ty mówisz — topic.

### Anatomia pliku `.msg`

Lista pól, po jednym na linię: `typ nazwa`. Typy wbudowane: `bool`, `byte`,
`char`, `int8`…`int64`, `uint8`…`uint64`, `float32`, `float64`, `string`,
`wstring`. Typy z innych pakietów pisze się `pakiet/Typ`, bez segmentu `msg`
w środku: `std_msgs/Header`, `builtin_interfaces/Time`.

`builtin_interfaces/Time` to para `int32 sec` + `uint32 nanosec` i nic więcej
— żadnej strefy, żadnej informacji o tym, który zegar ją wystawił.
`std_msgs/Header` to ten `Time` pod nazwą `stamp` plus `string frame_id`, a
**narzędzia rozpoznają go po nazwie pola**: `ros2 topic delay`, `message_filters`
i rviz2 szukają pola `header` — wiadomość z gołym `stamp` jest nieostemplowana.

Tablice mają trzy postaci i różnica jest widoczna na łączu:

```
float32[]     wszystkie      # nieograniczona
float32[25]   okno           # dokładnie 25, stały rozmiar
float32[<=64] ostatnie       # najwyżej 64 — ograniczona
string<=16    krotka_nazwa   # ograniczony string
```

Ograniczaj, gdy znasz limit: nieograniczona tablica to alokacja na każdą
wiadomość i brak górnego oszacowania rozmiaru, a przy 50 Hz to jest liczba,
którą ktoś kiedyś będzie chciał znać.

Stałe to nazwane liczby pisane wielkimi literami (`uint8 OPEN=1`). Trafiają
do wygenerowanego kodu jako atrybuty klasy (`GraspVerdict.OPEN`) i wypisuje
je `ros2 interface show`. **Nie są typem** — generator nie sprawdzi, czy
`state` ma jedną z nich, sprawdzi tylko, czy mieści się w `uint8`.

Komentarze (`#`) są jedyną dokumentacją kontraktu, jaka jedzie razem z nim do
każdego, kto go zainstaluje. Piszesz je dla kogoś, kto za rok wykona
`ros2 interface show` i nie ma do kogo zadzwonić.

### Projekt `GraspVerdict.msg`

```
# Werdykt detektora chwytu. Liczony ze średniej okna próbek /vacuum_pressure.
# Publikowany na /grasp_verdict przez węzeł grasp_monitor.

# Stempel powstania werdyktu i źródło. Semantyka stempla: etap 02.
std_msgs/Header header

# Dozwolone wartości pola `state`. Innych nie ma.
# 0 jest zarezerwowane dla UNKNOWN, bo puste pole ma wyglądać na puste.
uint8 UNKNOWN=0
uint8 OPEN=1
uint8 LEAK=2
uint8 SEALED=3

# Stan chwytu. Porównuj ze stałymi powyżej, nigdy z gołą liczbą.
uint8 state

# Jak mocno wierzymy w `state`: 0.0 zgadywanie, 1.0 pewne.
# Dziś liczone z marginesu progu; kalibracja z danych to etap 10.
float32 confidence

# TYLKO dla człowieka i dla logów. Maszyna nie decyduje na tym polu.
string reason

# Stempel ostatniego pomiaru, z którego policzono ten werdykt.
# Zostawiony wyzerowany do etapu 02.
builtin_interfaces/Time source_stamp
```

| pole | po co jest | co bez niego |
|---|---|---|
| `header` | narzędzia poznają po nim wiadomość ostemplowaną; `frame_id` mówi, który chwytak | nie policzysz opóźnienia i nie zsynchronizujesz dwóch strumieni |
| `state` | jedyne pole, na którym maszyna ma prawo decydować | wracasz do parsowania tekstu |
| `confidence` | detektor progowy zawsze coś zwróci; odbiorca musi odróżnić „na pewno" od „chyba" | każdy werdykt wygląda na równie pewny, a nie jest |
| `reason` | człowiek czytający `echo` albo nagranie musi wiedzieć, dlaczego akurat to | debugowanie wymaga odtworzenia całej sytuacji |
| `source_stamp` | werdykt powstaje później niż pomiar, to dwie różne chwile | nie oddzielisz opóźnienia czujnika od opóźnienia liczenia |

**Dlaczego `uint8` bije stringa.** Porównanie to `==` na liczbie — nie ma
wielkości liter, spacji na końcu ani kodowania. Zbiór dozwolonych wartości
jedzie w jednym pliku razem z danymi. Wygenerowany setter pilnuje zakresu, więc
`msg.state = 300` rzuca `AssertionError` w momencie przypisania, a nie
u odbiorcy. I jest liczbą — wykreślisz ją i policzysz z nagrania („Po co to").

**Czego `uint8` nie robi.** Nie zabroni wpisać `7`. Konsument, który dostanie
nieznaną wartość, ma ją potraktować jak `UNKNOWN`, a nie wywalić się.

**Dlaczego mimo to zostaje pole tekstowe.** `reason` odpowiada na „dlaczego",
a wyliczenie wszystkich możliwych „dlaczego" w kontrakcie, który dopiero
powstaje, to przeinżynierowanie. Cena jest realna: **ktoś kiedyś zacznie
`reason` parsować.** Jedyna obrona to zasada „żaden fakt nie mieszka wyłącznie
w `reason`" — gdy odbiorca zaczyna czegoś stamtąd potrzebować, ta rzecz
awansuje na osobne, typowane pole.

Uczciwie: `GraspVerdict` jest **większy** na łączu niż `String`. Płacisz za
stempel, `confidence` i `reason`. Różnica polega na tym, że wiesz, za co
płacisz, i każdy bajt ma nazwę.

### Dlaczego potrzebny jest drugi pakiet

`rosidl` jest zestawem makr CMake'a. Jako krok budowania czyta `.msg`,
wypluwa kod w C, C++ i Pythonie, kompiluje biblioteki natywne i instaluje
moduł pythonowy będący nakładką na te biblioteki. Pakiet `ament_python` nie
uruchamia CMake'a w ogóle — jego budowanie to `setup.py`. **Nie da się tego
obejść konfiguracją.**

Stąd układ z każdego poważnego repo ROS-a: interfejsy mieszkają w osobnym
pakiecie `ament_cmake` z sufiksem `_msgs` i nie zawierają kodu. Kto chce
tylko gadać z twoim systemem, instaluje same schematy — bez twojej
implementacji i bez jej zależności.

`ws/src/grip_monitor_msgs/package.xml`:

```xml
<?xml version="1.0"?>
<?xml-model href="http://download.ros.org/schema/package_format3.xsd" schematypens="http://www.w3.org/2001/XMLSchema"?>
<package format="3">
  <name>grip_monitor_msgs</name>
  <version>0.0.0</version>
  <description>Interfejsy detektora chwytu podciśnieniowego.</description>
  <maintainer email="maniumek@todo.todo">maniumek</maintainer>
  <license>Apache-2.0</license>

  <buildtool_depend>ament_cmake</buildtool_depend>

  <build_depend>rosidl_default_generators</build_depend>
  <exec_depend>rosidl_default_runtime</exec_depend>

  <depend>std_msgs</depend>
  <depend>builtin_interfaces</depend>

  <member_of_group>rosidl_interface_packages</member_of_group>

  <export>
    <build_type>ament_cmake</build_type>
  </export>
</package>
```

Cztery wpisy, których nie zgadniesz. `buildtool_depend ament_cmake` razem
z `build_type` deklaruje „mnie buduje CMake". `build_depend
rosidl_default_generators` to generatory,
potrzebne tylko przy budowaniu; oficjalny tutorial pokazuje tu
`buildtool_depend` — przy kompilacji skrośnej to poprawniejszy tag, u ciebie
oba działają tak samo. `exec_depend rosidl_default_runtime` to biblioteki
potrzebne przy **uruchamianiu** u każdego, kto tego typu używa; bez nich
pakiet zbuduje się i nie zadziała na czystej maszynie. `member_of_group
rosidl_interface_packages` zgłasza pakiet do grupy, po której generatory
i `rosdep` rozpoznają pakiety z interfejsami — bez tego nic nie krzyknie,
a zależności rozjadą się przy instalacji.

`ws/src/grip_monitor_msgs/CMakeLists.txt`:

```cmake
cmake_minimum_required(VERSION 3.8)
project(grip_monitor_msgs)

find_package(ament_cmake REQUIRED)
find_package(rosidl_default_generators REQUIRED)
find_package(std_msgs REQUIRED)
find_package(builtin_interfaces REQUIRED)

rosidl_generate_interfaces(${PROJECT_NAME}
  "msg/GraspVerdict.msg"
  "srv/GetLastVerdict.srv"
  DEPENDENCIES std_msgs builtin_interfaces
)

ament_export_dependencies(rosidl_default_runtime)
ament_package()
```

Zależności trzeba wpisać w **trzech** miejscach i to jest najczęstszy błąd
w tym pliku: `find_package` (żeby CMake je znalazł), `DEPENDENCIES` (żeby
generator wiedział, że `GraspVerdict` odwołuje się do cudzych typów)
i `<depend>` w `package.xml` (żeby wiedział o tym system pakietów). Brak
któregokolwiek daje inny, niepodobny do pozostałych komunikat.

Po stronie pakietu pythonowego wystarczy `<depend>grip_monitor_msgs</depend>`
w `ws/src/grip_monitor/package.xml` i zwykły import
`from grip_monitor_msgs.msg import GraspVerdict`. `setup.py` nie wymaga
zmiany. Wpis w `package.xml` nie jest ozdobą: z niego colcon liczy kolejność
budowania, a `rosdep` — co doinstalować. Bez niego build przejdzie (Python
nic nie importuje w trakcie budowania) i złamie się przy pierwszym
uruchomieniu na czystym środowisku.

### Introspekcja: czym jest ten typ naprawdę

```bash
ros2 interface list | grep grip_monitor      # co w ogóle istnieje
ros2 interface show grip_monitor_msgs/msg/GraspVerdict
ros2 interface proto grip_monitor_msgs/msg/GraspVerdict
```

`show` rozwija typy zagnieżdżone, więc widzisz `header` razem z wnętrzem,
i wypisuje stałe, czyli listę dozwolonych stanów — dokumentacja kontraktu,
której nie da się zdezaktualizować, bo czytana z zainstalowanego typu. `proto`
drukuje pusty egzemplarz w YAML-u, gotowy do wklejenia w `ros2 topic pub`;
domyślnie w cudzysłowach, `--no-quotes` je zdejmuje.

Te polecenia mówią o **typie zainstalowanym u ciebie**, nie o tym, którym
nadaje druga strona. Tamten sprawdzisz wyłącznie przez hasz.

### Hasze typów RIHS01

Zajrzyj do `projects/grab-fail-detection/bags/chwyt-3-stany/metadata.yaml`:

```yaml
    - topic_metadata:
        name: /grasp_verdict
        type: std_msgs/msg/String
        serialization_format: cdr
        type_description_hash: RIHS01_df668c740482bbd48fb39d76a70dfd4bd59db1288021743503259e948f6b1a18
      message_count: 1062
```

`RIHS` to ROS Interface Hashing Standard, `01` to jego wersja, reszta to
skrót policzony ze **struktury** typu — z nazw i typów pól, nie z nazwy
samego typu. Dwa typy o różnych nazwach i identycznej budowie mają ten sam
hasz; jeden typ po zmianie nazwy pola ma dwa różne hasze.

Ten sam hasz zobaczysz na żywym systemie: `ros2 topic info --verbose /grasp_verdict`
wypisuje blok na każdy koniec połączenia, a w bloku `Topic type` i `Topic type
hash`. To jest **jedyne** miejsce, w którym sprawdzisz, czy nadawca i odbiorca
mówią o tym samym.

Po co to jest: nagranie nie zapisuje definicji do czytania przez człowieka,
tylko odcisk palca typu. Gdy za rok odtworzysz je na nowym kodzie, hasz jest
jedyną rzeczą, która powie, czy to ma prawo zadziałać — bo **interfejs jest
schematem danych historycznych, nie tylko API na żywo**.

### Wersjonowanie: nie ma go

W ROS 2 nie ma negocjacji wersji. Nie ma nagłówka `Accept`, nie ma rejestru
schematów, nie ma tłumaczenia między wersjami. Nie dlatego, że nikt o tym nie
pomyślał — dlatego, że DDS jest peer-to-peer i **nie ma brokera, w którym
takie tłumaczenie mogłoby zamieszkać**.

1. Zmiana `.msg` to przebudowa wszystkiego i restart każdego procesu —
   niezrestartowany wygląda zdrowo („Dlaczego to trudne").
2. Zmiana `.msg` **unieważnia stare nagrania**. To, co wczoraj było twoim
   zbiorem testowym, dziś jest archiwum.
3. Dlatego pakiety `*_msgs` trzyma się osobno i zmienia **rzadko**. Osobny
   pakiet to nie ceremoniał, tylko granica, którą widać w historii gita
   i przy której zatrzymuje się code review.

Gdy naprawdę musisz zmienić kontrakt: dodaj nowy typ obok starego zamiast
przerabiać istniejący, albo przegraj nagrania na nowy typ
([etap 03](./03-bagi-jako-dane.md)).

### Konwencje nazewnicze

| rzecz | zasada | przykład |
|---|---|---|
| plik interfejsu | `CamelCase`, w katalogu `msg/`, `srv/` albo `action/` | `GraspVerdict.msg` |
| nazwa wiadomości | rzeczownik — wiadomość jest **rzeczą**, nie czynnością | `GraspVerdict`, nie `CheckGrasp` |
| bez sufiksu `Msg` | typ już leży w katalogu `msg/` | `GraspVerdict`, nie `GraspVerdictMsg` |
| nazwa usługi | czasownik jest na miejscu — usługa jest czynnością | `GetLastVerdict`, `SetThreshold` |
| nazwa akcji | czasownik rozkazujący, nazwa zadania | `ExecuteGrasp` |
| pola | `snake_case`, bez podkreśleń na brzegach | `source_stamp` |
| stałe | `WIELKIMI_LITERAMI` | `SEALED` |
| pakiet | `<coś>_msgs`, **wyłącznie interfejsy, zero kodu** | `grip_monitor_msgs` |

Pułapka spoza tabeli: nazwa pola trafia do C, C++ i Pythona naraz, więc nie
może być słowem kluczowym żadnego z nich (`class`, `from`, `template`).

## Zadania

Wszystko poniżej robisz w kontenerze — terminal VS Code albo
`scripts/dev/enter-devcontainer.sh`. Do podglądu z drugiej strony służą
skrypty z `scripts/dev/ros2/`.

### Zadanie 01.1 — Zobacz, czego dziś nie masz (rdzeń)

**Cel:** zobaczyć, że nazwa topicu nie jest kontraktem, a hasz typu jest.
**Ćwiczysz:** czytanie haszu jako tożsamości typu — czytany jest ciekawostką,
a tu masz go dwa razy: sprzed miesięcy i z żywego systemu, do porównania.

```bash
scripts/dev/ros2/run-node.sh grip_monitor vacuum_sensor --ros-args -p state:=sealed
scripts/dev/ros2/run-node.sh grip_monitor grasp_monitor      # drugi terminal
ros2 topic info --verbose /grasp_verdict                     # trzeci
ros2 interface show std_msgs/msg/String
grep type_description_hash projects/grab-fail-detection/bags/chwyt-3-stany/metadata.yaml
```

Porównaj hasz `std_msgs/msg/String` z żywego systemu z tym z `metadata.yaml`
sprzed miesięcy. Potem wyobraź sobie, że `String` dostaje drugie pole —
i zastanów się, kto miałby ci o tym powiedzieć.

**Gotowe, gdy:** hasz z `ros2 topic info -v` jest znak w znak taki sam jak
w `metadata.yaml`, i umiesz powiedzieć, dlaczego to nie jest przypadek.

### Zadanie 01.2 — Pakiet `grip_monitor_msgs` i `GraspVerdict.msg` (rdzeń)

**Cel:** mieć własny typ, widoczny dla `ros2 interface`.
**Ćwiczysz:** podział na dwa pakiety — jedyny sposób, żeby zobaczyć, że zielony
build potrafi nie zbudować niczego, bo `ament_python` nie wie o katalogu `msg/`.

```bash
cd /home/maniumek/repos/robotics/ws/src
ros2 pkg create --build-type ament_cmake --license Apache-2.0 grip_monitor_msgs
mkdir -p grip_monitor_msgs/msg
```

Wpisz `package.xml` i `CMakeLists.txt` z sekcji „Dlaczego potrzebny jest
drugi pakiet" (na razie bez linii z `srv/`) oraz `msg/GraspVerdict.msg`.
Katalogi `include/` i `src/` wygenerowane przez `ros2 pkg create` skasuj —
w pakiecie z interfejsami nie ma kodu.

```bash
scripts/dev/build-colcon-workspace.sh
# nowy terminal, inaczej nie zobaczy ws/install
ros2 interface list | grep grip_monitor
ros2 interface show grip_monitor_msgs/msg/GraspVerdict
ros2 interface proto grip_monitor_msgs/msg/GraspVerdict
```

Zanim to zrobisz, eksperyment na trzydzieści sekund: wrzuć ten sam plik
`.msg` do `ws/src/grip_monitor/msg/` i zbuduj. Build przejdzie,
`ros2 interface list` nie pokaże nic. Zapamiętaj tę porażkę — jest zielona.

**Gotowe, gdy:** `ros2 interface show` wypisuje twoje pola razem
z rozwiniętym `header` i czterema stałymi, a `proto` drukuje szkielet,
w którym `state` ma wartość `0`.

### Zadanie 01.3 — Przepnij `grasp_monitor` na nowy typ (rdzeń)

**Cel:** publikować werdykt jako dane, nie jako tekst.
**Ćwiczysz:** projekt pól w działaniu — dopiero przepisując callback widzisz, że
`state`, `confidence` i `reason` odpowiadają na trzy różne pytania.

Dodaj `<depend>grip_monitor_msgs</depend>` do `ws/src/grip_monitor/package.xml`,
zamień publisher na `self.create_publisher(GraspVerdict, 'grasp_verdict', 10)`
i przepisz publikowanie:

```python
        if is_at_level(mean, 0):
            self.publish_verdict(GraspVerdict.OPEN, window_confidence(mean, 0.0), f'mean={mean:.2f}')

        if mean < -1 and mean > -58:
            # Okno „leak" ma 57 jednostek szerokości — stąd niska pewność na sztywno.
            self.publish_verdict(GraspVerdict.LEAK, 0.5, f'mean={mean:.2f}')

        if is_at_level(mean, -59):
            self.publish_verdict(GraspVerdict.SEALED, window_confidence(mean, -59.0), f'mean={mean:.2f}')

    def publish_verdict(self, state: int, confidence: float, reason: str) -> None:
        msg = GraspVerdict()
        # Zaślepka. Który zegar i czym to się różni od stempla pomiaru — etap 02.
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = 'vacuum_gripper'
        msg.state = state
        msg.confidence = confidence
        msg.reason = reason
        self.pub.publish(msg)


def window_confidence(mean: float, level: float) -> float:
    return float(max(0.0, 1.0 - abs(mean - level)))
```

`source_stamp` zostaje wyzerowany i ma tak zostać. Przebuduj, uruchom oba
węzły, zajrzyj:

```bash
scripts/dev/ros2/print-topic-messages.sh /grasp_verdict --once
scripts/dev/ros2/print-topic-messages.sh /grasp_verdict --field state
```

Sprawdź jeszcze walidację, której `String` nigdy nie dawał — w `python3`
w kontenerze: `m = GraspVerdict(); m.state = 300` rzuca `AssertionError` tu
i teraz, a `m.state = 7` przechodzi, bo zakres to nie enum.

**Gotowe, gdy:** `echo` pokazuje `header`, `state`, `confidence`, `reason`
i wyzerowany `source_stamp`, a `--field state` daje strumień liczb, który da
się wykreślić.

### Zadanie 01.4 — Zepsuj to: stare nagranie na nowym kodzie (rdzeń)

**Cel:** zobaczyć, jak wygląda niezgodność kontraktu, gdy nikt jej nie zgłasza.
**Ćwiczysz:** rozpoznawanie ciszy jako objawu. Przeczytana jest ciekawostką;
21 sekund pustego terminala przy dwóch żywych węzłach — nie jest.

Nagrania nie ma w gicie (`**/bags/` w `.gitignore`) — nie nadpisz go.
Zatrzymaj wszystkie węzły i odtwórz stare nagranie:
`ros2 bag play projects/grab-fail-detection/bags/chwyt-3-stany`.

W drugim terminalu odpal podsłuch napisany pod **nowy** typ —
`/tmp/sniff.py` w kontenerze, uruchamiany przez `python3`:

```python
import rclpy
from rclpy.node import Node
from grip_monitor_msgs.msg import GraspVerdict

rclpy.init()
node = Node('sniff')
node.create_subscription(GraspVerdict, '/grasp_verdict', lambda m: print(m.state), 10)
rclpy.spin(node)
```

**Co zobaczysz:** `sniff.py` nie wypisze ani jednej linii przez całe
21 sekund odtwarzania. Bez wyjątku, bez ostrzeżenia, bez logu. Jedyny ślad
jest w `ros2 topic info --verbose /grasp_verdict`: jeden nadawca typu
`std_msgs/msg/String` z haszem `RIHS01_df66…` i jeden odbiorca typu
`grip_monitor_msgs/msg/GraspVerdict` z haszem zupełnie innym. Nazwa topicu ta
sama, więc obie strony uważają, że są na miejscu. Nie są.

Drugi wariant: zostaw grające nagranie i **dodatkowo** uruchom nowy
`grasp_monitor`. Na `/grasp_verdict` są teraz dwa typy naraz —
`ros2 topic list -t` wypisze oba w nawiasach, a `ros2 topic echo
/grasp_verdict` odmówi komunikatem w rodzaju „Cannot echo topic
'/grasp_verdict', as it contains more than one type". To jedyny moment
w tym etapie, w którym ROS mówi wprost, że coś jest nie tak — i mówi to
narzędzie CLI, nie warstwa transportowa.

**Gotowe, gdy:** masz w `projects/grab-fail-detection/NOTES.md` oba hasze
z `topic info -v` i jedno zdanie o tym, ile błędów dostałeś w wariancie
pierwszym.

### Zadanie 01.5 — Zepsuj to mocniej: ta sama nazwa, inny hasz (rdzeń)

**Cel:** zobaczyć wariant groźniejszy — gdy nazwa typu się zgadza.
**Ćwiczysz:** hasz przeciwko nazwie — i to, że niezgodność mieszka w pamięci
procesu, a nie w plikach. Z czytania `.msg` tego nie widać, bo tam jej nie ma.

1. Uruchom `vacuum_sensor` i `grasp_monitor`, sprawdź, że werdykty lecą.
2. **Nie zatrzymując ich**, dopisz do `GraspVerdict.msg` pole
   `float32 mean_pressure` i przebuduj workspace.
3. W nowym terminalu uruchom `python3 /tmp/sniff.py` z zadania 01.4.
4. `ros2 topic info --verbose /grasp_verdict`.

Nadawca to proces sprzed przebudowy — trzyma starą definicję w pamięci
i o zmianie nie wie. Odbiorca załadował nową.

**Co zobaczysz:** dwa różne `Topic type hash` pod **tą samą** nazwą typu. To
jest gwarantowane i to jest właściwy objaw do zapamiętania. Czy wiadomości
dojdą, dojdą przekłamane, czy nie dojdą wcale — zależy od RMW i od tego, jak
zmieniłeś strukturę; sprawdź to u siebie i **zapisz wynik**, bo to jest
dokładnie ten rodzaj faktu o środowisku, którego nie ma w dokumentacji.

Zwróć uwagę, czego tu nie ma: nikt nie wypisał „niezgodna wersja typu".
Gdybyś zamiast węzła użył `ros2 topic pub`, nie odtworzyłbyś tego wcale — CLI
wczytuje typ przy każdym uruchomieniu. Do tego błędu potrzebny jest **długo
żyjący proces**, czyli dokładnie to, czym jest każdy robot. Posprzątaj: usuń
dodane pole albo zrestartuj wszystko.

**Gotowe, gdy:** umiesz z pamięci wymienić trzy rzeczy, które trzeba zrobić
po zmianie `.msg`, i wiesz, która z nich jest najczęściej pomijana.

### Zadanie 01.6 — Usługa „podaj ostatni werdykt" (rozszerzenie)

**Cel:** dołożyć drugi mechanizm tam, gdzie strumień nie wystarcza.
**Ćwiczysz:** regułę decyzyjną z tabeli trzech mechanizmów — „kto nie słuchał,
nie usłyszy" znaczy coś dopiero, gdy sam potrzebujesz odpowiedzi po fakcie.

Narzędzie, które właśnie wstało, nie usłyszało niczego, co poleciało wcześniej.
Stąd usługa — `ws/src/grip_monitor_msgs/srv/GetLastVerdict.srv`:

```
# Żądanie jest puste — pytasz o stan „teraz". Wzorzec: std_srvs/srv/Trigger.
---
# valid=false znaczy: jeszcze nic nie policzyłem, okno się nie napełniło.
bool valid
grip_monitor_msgs/GraspVerdict verdict
```

Dopisz `"srv/GetLastVerdict.srv"` do `rosidl_generate_interfaces`, zapamiętuj
w `grasp_monitor.py` ostatnią opublikowaną wiadomość i dołóż serwer:

```python
        self.create_service(GetLastVerdict, 'get_last_verdict', self.on_get_last_verdict)

    def on_get_last_verdict(self, request, response):
        response.valid = self.last_verdict is not None
        if self.last_verdict is not None:
            response.verdict = self.last_verdict
        return response
```

```bash
ros2 service list -t
ros2 interface show grip_monitor_msgs/srv/GetLastVerdict
ros2 service call /get_last_verdict grip_monitor_msgs/srv/GetLastVerdict "{}"
```

Zawołaj też usługę przy **zatrzymanym** węźle i policz, ile czekasz, zanim
cokolwiek się wydarzy. Nie ma domyślnego timeoutu.

Trzeci mechanizm, akcja, pasuje do „wykonaj chwyt": zjedź, przyssij, unieś,
sprawdź — z feedbackiem i anulowaniem. Sens ma, gdy jest co ruszać, czyli przy
symulacji — [etap 08](./08-tf2-urdf-ros2-control.md). Plik możesz napisać już
teraz: `action/ExecuteGrasp.action`, trzy sekcje rozdzielone przez `---` (cel,
wynik, feedback), plus `<depend>action_msgs</depend>` — bez niego się nie zbuduje.

**Gotowe, gdy:** `ros2 service call` zwraca strukturę z `valid: true`
i kompletnym `verdict`, a ty umiesz uzasadnić, czemu to nie jest kolejny topic.

## Pułapki

| objaw | przyczyna | co zrobić |
|---|---|---|
| `colcon build` zielony, `ros2 interface list \| grep grip_monitor` pusty | `msg/` leży w pakiecie `ament_python`; rosidl nigdy go nie zobaczył, bo nie było CMake'a | przenieś do pakietu `ament_cmake` z `rosidl_generate_interfaces` |
| `ModuleNotFoundError: No module named 'grip_monitor_msgs'` | terminal starszy niż `ws/install` albo brak przebudowania po zmianie `.msg` | nowy terminal (profil sam sourcuje workspace); `--symlink-install` **nie** obejmuje generowanych interfejsów — po każdej zmianie `.msg` budujesz |
| generator woła o `std_msgs`, choć `find_package` jest | brak `DEPENDENCIES std_msgs` w `rosidl_generate_interfaces` albo `<depend>` w `package.xml` | zależność musi być w trzech miejscach naraz |
| `ros2 topic echo` odmawia: „contains more than one type" | dwa źródła publikują różne typy pod tą samą nazwą topicu (`bag play` starego nagrania obok nowego węzła) | zatrzymaj jedno źródło; nazwa topicu nie jest kontraktem, typ jest |
| węzły żyją, `topic info` pokazuje oba końce, nic nie dochodzi | różne hasze typu: proces nie został zrestartowany po przebudowie albo odtwarzasz stare nagranie | `ros2 topic info --verbose TOPIC`, porównaj `Topic type hash` po obu stronach |
| `AssertionError` przy `msg.state = 300` | wygenerowany setter pilnuje zakresu `uint8` | to cecha, nie usterka; ale `7` przejdzie — konsument ma traktować nieznane wartości jak `UNKNOWN` |
| `ros2 service call` wisi bez komunikatu | nie ma serwera pod tą nazwą, a usługa nie ma domyślnego timeoutu | `ros2 service list -t`, potem `ros2 node info /grasp_monitor` |
| węzeł zamiera przy wywołaniu usługi z callbacka | domyślny executor jest jednowątkowy — blokujesz wątek, który miałby odebrać odpowiedź | `call_async` i obsługa future'a albo osobna grupa callbacków |
| generator wywala się komunikatem o C++, a ty piszesz w Pythonie | nazwa pola jest słowem kluczowym w którymś z języków docelowych (`class`, `from`, `template`) | zmień nazwę pola |
| po zmianie `.msg` stare nagrania „są puste" | inny hasz = inny typ; rosbag2 zapisał hasz z chwili nagrania | nie przerabiaj `*_msgs` w locie — dodaj nowy typ albo przegraj nagrania ([etap 03](./03-bagi-jako-dane.md)) |

## Sprawdź się

1. Dlaczego pakiet `ament_python` nie potrafi wygenerować `.msg` i dlaczego
   nie da się tego obejść konfiguracją?
2. Hasz typu liczy się ze struktury, nie z nazwy. Co z tego wynika dla
   nagrania zrobionego pół roku temu?
3. Masz `uint8 state` ze stałymi i `string state_name`. Które z tych pól może
   zniknąć bez straty i dlaczego to nie jest `state`?
4. Dlaczego `0` w `GraspVerdict` to `UNKNOWN`, a nie `OPEN`? Odpowiedz przez
   to, co dzieje się z polem, którego nikt nie ustawił.
5. „Podaj ostatni werdykt" — usługa czy topic? A „wykonaj chwyt"? Uzasadnij
   przez pytanie o anulowanie.
6. Zostawiłeś w wiadomości pole `string reason`. Wymień koszt tej decyzji
   i zasadę, która przed nim broni.
7. Zmieniasz `float32 confidence` na `float64`. Co przestaje działać i które
   z tego zauważysz od razu?
8. Dlaczego niezgodność typów objawia się ciszą, a nie błędem? Odpowiedź ma
   dotyczyć architektury DDS, nie niedopatrzenia.

## Co przeczytać

- `https://docs.ros.org/en/jazzy/` — tworzenie własnych interfejsów i pakiety
  `ament_cmake`. Przeczytaj po zadaniu 01.2, żeby zobaczyć, ile z tego było
  do odgadnięcia.
- `https://design.ros2.org/` — dokumenty o interfejsach i o tym, dlaczego
  ROS 2 nie ma negocjacji wersji. Miejsce na „dlaczego tak", którego
  w tutorialach nie ma.
- `https://github.com/ros2/rosidl` — źródła generatora i opis standardu
  haszowania typów. Zajrzyj, gdy zechcesz wiedzieć, co dokładnie wchodzi
  do `RIHS01_`.
- `https://github.com/ros2/common_interfaces` — `std_msgs`, `sensor_msgs`,
  `geometry_msgs` w oryginale. Najlepszy przegląd dobrze zaprojektowanych
  wiadomości — zobacz, jak `sensor_msgs` używa stałych i ograniczonych tablic.
- `https://www.ros.org/reps/` — REP-y o konwencjach nazewniczych i o opisie
  typów. Czytasz, gdy ktoś w code review powie „to się tak nie nazywa",
  a ty chcesz wiedzieć, czy ma rację.

## Dziennik

Uzupełnij po skończeniu etapu, zanim przejdziesz dalej.

- Co mnie zaskoczyło w tym, jak wygląda niezgodność kontraktu?
- Co zjadło najwięcej czasu — projekt wiadomości czy zmuszenie budowania do
  współpracy?
- Które pole `GraspVerdict.msg` dodałem odruchowo i nadal nie umiem uzasadnić?
- Co w zadaniu 01.5 zobaczyłem naprawdę: ciszę, śmieci, czy jednak działało?
- Jedno zdanie, którego nie umiałbym napisać tydzień temu:

Dalej → [Etap 02 — Czas, zdarzenia, stan](./02-czas-zdarzenia-stan.md)
