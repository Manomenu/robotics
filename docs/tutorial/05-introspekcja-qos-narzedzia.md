# Etap 05 — Introspekcja żywego systemu: DDS, QoS i narzędzia

> Po tym etapie umiesz odpowiedzieć na pytanie „oba węzły żyją, a dane nie
> płyną — dlaczego" samymi narzędziami, bez otwierania kodu; i masz wreszcie
> ekran, na którym widać sygnał, a nie kolumnę liczb.

| | |
|---|---|
| wejście | etapy 01–04; `colcon build` przechodzi, oba węzły startują, w `projects/grab-fail-detection/bags/chwyt-3-stany/` leży nagranie z etapu 03 |
| czas | 3 wieczory: jeden na ekran z kontenera, dwa na QoS i narzędzia |
| kończy się | `/vacuum_pressure` rysuje się na żywym wykresie i z nagrania, a rozjazd QoS diagnozujesz w mniej niż dwie minuty, nie zaglądając w `ws/src/` |

---

## Po ludzku: co to jest w twoim świecie

| pojęcie robotyczne | odpowiednik z backendu | gdzie analogia pęka |
|---|---|---|
| profil QoS | timeouty, retry i acki w kliencie HTTP | to jest kontrakt **dwustronny**, sprawdzany przy zestawianiu połączenia; ustawiasz go u siebie, ale odrzuca cię druga strona — i robi to bez słowa |
| `RELIABLE` | TCP / at-least-once | gwarancja obowiązuje tylko w granicach kolejki `depth`; `KEEP_LAST(10)` nadpisuje najstarszą wiadomość i nikt nie krzyczy |
| odkrywanie DDS | service discovery, Consul, etcd | nie ma rejestru ani jednego miejsca z prawdą; każdy rozgłasza siebie multicastem, a `ros2 node list` to migawka z lokalnego demona, nie stan świata |
| `ROS_DOMAIN_ID` | namespace w K8s, vhost w RabbitMQ | izoluje przez numery portów UDP, nie przez uprawnienia; dwie wartości na jednej maszynie to dwa rozłączne światy i nic cię nie ostrzeże, że siedzisz w niewłaściwym |
| `ros2 topic echo` | `curl`, `kafkacat` | sam negocjuje QoS pod nadawcę, więc potrafi pokazywać dane, których twój węzeł nigdy nie dostanie — narzędzie mówi „działa", kod milczy |
| `rqt_graph` | diagram z APM-a | rysuje krawędź, gdy obie strony **siedzą na tym samym topiku**, a nie gdy faktycznie płyną tamtędy dane; niezgodne QoS wygląda na grafie identycznie jak działające połączenie |

---

## Po co to — czego bez tego nie da się zrobić

Dziś twój system działa, i to jest właśnie problem: nigdy nie widziałeś, jak
wygląda zepsuty, więc nie wiesz, które narzędzie by ci to pokazało.

Zmień jedną linię w `ws/src/grip_monitor/grip_monitor/grasp_monitor.py`:

```python
qos = QoSProfile(depth=10, reliability=ReliabilityPolicy.RELIABLE)
```

Nic się nie wysypie. Nie poleci wyjątek, proces nie zginie, build przejdzie.
A detektor przestanie orzekać cokolwiek — na zawsze. I teraz najgorsze:
**każde narzędzie, którego dziś używasz, powie ci, że jest dobrze.**

| co odpalasz | co zobaczysz | dlaczego kłamie |
|---|---|---|
| `list-running-nodes.sh` | `/vacuum_sensor` i `/grasp_monitor` | oba procesy żyją, bo niezgodność QoS nie zabija węzła |
| `list-topics.sh` | `/vacuum_pressure [std_msgs/msg/Float32]` | topic istnieje, typ się zgadza, hash typu się zgadza |
| `print-topic-messages.sh /vacuum_pressure` | liczby lecą | `ros2 topic echo` dobiera QoS pod nadawców, więc **dla siebie** podłącza się bez problemu |
| `measure-topic-rate.sh /vacuum_pressure` | ~50 Hz | `ros2 topic hz` subskrybuje na sztywno profilem `sensor_data`, czyli BEST_EFFORT — zawsze pasuje do tego nadawcy |
| `rqt_graph` | ładna strzałka czujnik → monitor | rysuje topik, nie przepływ |

Jedyne, co pokaże prawdę, to porównanie profili obu stron —
czyli `ros2 topic info -v`, czyli `show-topic-connections.sh`. Do tego
dochodzi `ros2 doctor`, który ma w Jazzy osobny test zgodności QoS i wypisze
nazwę topika wprost.

Drugi powód jest bardziej przyziemny: bez ekranu nie zobaczysz kształtu
sygnału. Zakomentowana detekcja zbocza w `grasp_monitor.py` (wada nr 3
z [roadmapy](./00-roadmapa.md)) sprawia, że werdykt leci 50 razy na sekundę.
W `print-topic-messages.sh` wygląda to jak normalna praca. Na wykresie
`/grasp_verdict` obok `/vacuum_pressure` widać to w trzy sekundy.

---

## Dlaczego to ciekawe

**Zgodność QoS to wariancja typów, tylko w sieci.** Odbiorca *żąda* minimum,
którego potrzebuje. Nadawca *oferuje* to, co gwarantuje. Połączenie powstaje,
gdy oferta jest **nie słabsza** niż żądanie — dokładnie ta sama relacja
porządku co przy podtypach. Twoja intuicja z systemu typów działa tu w całości,
z jedną różnicą: kompilator odmawia głośno, a DDS po prostu nie zestawia
połączenia.

**Deadline i liveliness to jedyne miejsce w ROS-ie, gdzie middleware sam mówi
ci, że dane przestały płynąć.** Deklarujesz „spodziewam się próbki co 25 ms",
a gdy jej nie ma, dostajesz callback — nie z własnego watchdoga, tylko z
warstwy transportowej, która i tak liczy te odstępy. Dla celi chwytającej
to jest różnica między „ciśnienie trzyma" a „czujnik zamilkł pięć sekund
temu i nikt nie zauważył". Ta sama maszyneria, która potrafi po cichu
zerwać ci połączenie, jest jedyną, która potrafi zgłosić, że go nie ma.

**Odkrywanie działa bez rejestru.** Nie ma brokera, mastera ani pliku
z listą węzłów — węzły rozgłaszają swoje istnienie, słuchają rozgłoszeń
innych i same budują sobie mapę. `list-running-nodes.sh` nie czyta niczyjej
bazy: ogłasza się jako kolejny uczestnik i notuje, kto odpowie. Dlatego ta
lista bywa o sekundę spóźniona i dlatego pusta lista nie znaczy „nic nie
działa", tylko „nikt mi nie odpowiedział **w moim** domenie".

**Kontrakt jedzie razem z danymi.** Zajrzyj do `metadata.yaml` w swoim
nagraniu — jest tam `offered_qos_profiles` z `reliability: best_effort`
dla `/vacuum_pressure` i `reliable` dla `/grasp_verdict`. Bag zapisał nie
tylko, co leciało, ale i na jakich warunkach. Zwróć uwagę na `history: unknown`
i `depth: 0` w tym samym wpisie — to nie błąd zapisu, tylko fakt o DDS,
do którego wrócimy niżej.

---

## Dlaczego to trudne

**Objawem jest brak.** Cisza na topiku wygląda identycznie przy: literówce
w nazwie, innej przestrzeni nazw, innym `ROS_DOMAIN_ID`, niezgodnym QoS,
martwym nadawcy i pomylonym remapie. Sześć przyczyn, jeden objaw, zero
komunikatów. Backend daje ci w tej sytuacji 404, 415 albo connection refused
— tutaj dostajesz pusty ekran.

**Narzędzia dopasowują się, a twój kod nie.** To jest najgorszy możliwy układ
diagnostyczny: `echo` podłącza się do wszystkiego, `hz` mierzy tempo,
`rosbag2` nagrywa — a produkcyjny węzeł nie dostaje nic. Wniosek „skoro
narzędzie widzi, to kanał jest sprawny" jest fałszywy i kosztuje ludzi całe
popołudnia.

**Demon pamięta więcej, niż powinien.** `ros2 node list` i `topic list`
chodzą przez demona, który cache'uje graf. Węzeł zabity twardo potrafi
zostać na liście. Diagnozujesz wtedy system sprzed trzydziestu sekund.

**GUI z kontenera to cztery niezależne warstwy naraz** — serwer X kontra
Wayland, SELinux, mapowanie użytkowników w rootless podmanie i wtyczka
platformowa Qt. Każda ma własny komunikat błędu i każda obwinia nie tę
warstwę, co trzeba. „cannot open display" nie mówi ci, że winny jest brak
montowania gniazda.

**Połowa tego nie jest w dokumentacji.** To, że `hz` używa `sensor_data`,
że `echo` negocjuje, że `podman exec` nie przenosi zmiennych środowiskowych
z Fedory do kontenera — to wiedza plemienna. Sprawdzasz ją czytaniem źródeł
albo eksperymentem. Ten etap jest po to, żebyś sprawdził eksperymentem.

---

## Model pojęciowy

### Co jest pod topikiem

ROS 2 nie ma własnego transportu. Ma `rmw` — cienką warstwę abstrakcji, pod
którą siedzi implementacja DDS. W tym obrazie to Fast DDS (`rmw_fastrtps_cpp`),
bo taki jest domyślny w Jazzy. Twój węzeł to w świecie DDS *participant*,
publisher to *DataWriter*, subskrypcja to *DataReader*.

Odkrywanie idzie dwuetapowo i całkowicie rozgłoszeniowo: uczestnicy ogłaszają
swoje istnienie (SPDP), a potem wymieniają listy swoich endpointów wraz
z **pełnymi profilami QoS** (SEDP). Dopiero po tej wymianie każda strona
lokalnie liczy, czy oferta pasuje do żądania. To jest kluczowe: nikt nie
„prosi o połączenie" i nikt nikomu nie odmawia. Obie strony niezależnie
dochodzą do wniosku, że pary nie ma, i milkną.

`ROS_DOMAIN_ID` (domyślnie 0) przekłada się na numery portów UDP używanych
do odkrywania. Inna domena to inne porty, czyli inny świat na tej samej
karcie sieciowej. Zalecany zakres to 0–101; wyższe wartości potrafią kolidować
z portami efemerycznymi systemu.

Jazzy ma dwie zmienne ograniczające zasięg odkrywania:
`ROS_AUTOMATIC_DISCOVERY_RANGE` z wartościami `OFF`, `LOCALHOST`, `SUBNET`
i `SYSTEM_DEFAULT`, oraz `ROS_STATIC_PEERS` — listę adresów, do których
trzeba dosięgnąć wprost, gdy multicast nie przechodzi. Przy `OFF` statyczni
sąsiedzi są ignorowani. Starsze `ROS_LOCALHOST_ONLY` jest przestarzałe,
choć nadal honorowane, i wyłącza tamte dwie. Domyślną wartość zakresu
i dokładną składnię listy sprawdź w dokumentacji Jazzy, zanim się na nich
oprzesz — to jest miejsce, w którym warto nie zgadywać.

### Dlaczego `devcontainer.json` ma `--network=host` i `--ipc=host`

To nie są ozdoby, tylko dwa warunki konieczne.

`--network=host` — rootless podman domyślnie daje kontenerowi własną sieć
użytkownika (slirp4netns/pasta), która nie przenosi multicastu. Bez tej flagi
odkrywanie nie wyszłoby poza kontener: `list-topics.sh` z Fedory i węzeł
w VS Code byłyby w dwóch różnych sieciach i nigdy by się nie zobaczyły.
Skutek uboczny: port `foxglove_bridge` jest widoczny na Fedorze wprost,
bez publikowania portów.

`--ipc=host` — Fast DDS przesyła wiadomości między procesami na tej samej
maszynie przez pamięć dzieloną, a segmenty leżą w `/dev/shm`. Osobna
przestrzeń IPC znaczy osobne `/dev/shm`. Klasyczny objaw przy braku tej
flagi: strony **widzą się** w grafie (bo odkrywanie idzie po UDP), a duże
wiadomości nie przechodzą, bo obie uzgodniły transport, którego nie dzielą.
Diagnoza zajmuje pół dnia, jeśli nie wiesz, że ta warstwa istnieje.

W `apt` jest drugie RMW: `ros-jazzy-rmw-cyclonedds-cpp`. Przełącza się je
zmienną `RMW_IMPLEMENTATION=rmw_cyclonedds_cpp`. Warto o tym wiedzieć nie
po to, żeby wybierać lepsze, tylko dlatego, że **zmiana implementacji zmienia
objawy**: inne domyślne transporty, inne zachowanie przy dużych wiadomościach,
inne limity. Jeśli błąd znika po zmianie RMW, to nie jest błąd w twoim kodzie.
Nie mieszaj implementacji między węzłami jednego systemu — to nie jest
wspierana konfiguracja.

### Siedem polityk

| polityka | co ustala | wartości | podlega zgodności |
|---|---|---|---|
| reliability | czy zgubione wiadomości są retransmitowane | `BEST_EFFORT`, `RELIABLE` | tak |
| durability | czy odbiorca, który przyszedł później, dostanie ostatnie wiadomości | `VOLATILE`, `TRANSIENT_LOCAL` | tak |
| history + depth | ile wiadomości trzymać w kolejce | `KEEP_LAST(n)`, `KEEP_ALL` | **nie** — polityka lokalna |
| deadline | maksymalny odstęp między wiadomościami, jaki nadawca obiecuje / odbiorca wymaga | czas | tak |
| lifespan | po jakim czasie wiadomość przestaje być ważna i nie zostaje dostarczona | czas | **nie** — działa u nadawcy |
| liveliness | kto i jak potwierdza, że nadawca jeszcze żyje | `AUTOMATIC`, `MANUAL_BY_TOPIC` | tak |
| liveliness lease duration | co ile to potwierdzenie musi przyjść | czas | tak |

Stąd `history: unknown, depth: 0` w `metadata.yaml` twojego baga i stąd
`History (Depth): UNKNOWN` przy zdalnych endpointach w `ros2 topic info -v`:
głębokość kolejki nigdy nie jedzie w ogłoszeniu, bo nie jest częścią
kontraktu. To nie jest luka w narzędziu. To jest fakt o DDS.

### Zasada zgodności: oferta nie słabsza niż żądanie

| nadawca oferuje | odbiorca żąda | wynik |
|---|---|---|
| `RELIABLE` | `RELIABLE` | łączy |
| `RELIABLE` | `BEST_EFFORT` | łączy (odbiorca chciał mniej) |
| `BEST_EFFORT` | `BEST_EFFORT` | łączy |
| `BEST_EFFORT` | `RELIABLE` | **nie łączy** |

| nadawca oferuje | odbiorca żąda | wynik |
|---|---|---|
| `TRANSIENT_LOCAL` | `TRANSIENT_LOCAL` | łączy |
| `TRANSIENT_LOCAL` | `VOLATILE` | łączy |
| `VOLATILE` | `VOLATILE` | łączy |
| `VOLATILE` | `TRANSIENT_LOCAL` | **nie łączy** |

Dla deadline'u jest tak samo, tylko odwrotnie liczbowo: nadawca musi obiecywać
odstęp **nie większy** niż wymagany przez odbiorcę. Dla liveliness
`MANUAL_BY_TOPIC` jest mocniejsze niż `AUTOMATIC`, a dzierżawa nadawcy musi
być nie dłuższa niż żądana.

**Niezgodność nie jest błędem — jest ciszą.** Żaden proces nie rzuci wyjątku,
nie zwróci kodu błędu i nie zakończy się. `ros2 node list` pokaże komplet,
`ros2 topic list` pokaże topic, `rqt_graph` narysuje strzałkę, a dane nie
popłyną. To jest jedyne zdanie z tego etapu, które musisz umieć wyrecytować
o trzeciej w nocy.

Jest jeden półsygnał: `rclpy` sam rejestruje domyślny callback na zdarzenie
niezgodności i loguje ostrzeżenie w rodzaju *„New publisher discovered on
topic '/vacuum_pressure', offering incompatible QoS. No messages will be
received from it. Last incompatible policy: RELIABILITY"*. Pojawi się **raz**,
w momencie odkrycia drugiej strony, w strumieniu, na którym nikt nie stoi —
i tylko u tego, kto zdążył tę drugą stronę zobaczyć. Traktuj to jako prezent,
nie jako metodę. Metodą jest `ros2 topic info -v`. Samym logom przyglądamy
się w [etapie 06](./06-logi-diagnostyka-lifecycle.md).

### Który profil do czego — i dlaczego akurat tak w tym repo

`vacuum_sensor.py` oferuje `depth=10, BEST_EFFORT`. `grasp_monitor.py` żąda
tego samego, więc pasują. Ale werdykt na `grasp_verdict` idzie z profilu
domyślnego (`create_publisher(String, 'grasp_verdict', 10)`), czyli
`RELIABLE`, `VOLATILE`, `KEEP_LAST(10)`. To nie jest niedopatrzenie i nie jest
przypadek — to są dwa różne rodzaje danych.

| rodzaj danych | przykład tutaj | profil | dlaczego |
|---|---|---|---|
| strumień sensoryczny | `/vacuum_pressure`, 50 Hz | BEST_EFFORT, płytka kolejka | liczy się **najświeższa** próbka; retransmisja próbki sprzed 40 ms dostarcza ci nieaktualnej prawdy i zjada łącze. Przy 50 Hz zgubiona próbka zmienia średnią z 25 o 4% — nie zmienia decyzji |
| zdarzenie / decyzja | `/grasp_verdict` | RELIABLE | jest ich mało i każde znaczy coś innego. Zgubione „sealed → leak" to nie szum, tylko zły chwyt, o którym nikt się nie dowiedział |
| komenda | (jeszcze nie ma) | RELIABLE | komenda niedostarczona to ruch, który się nie wykonał |
| stan / konfiguracja | (etap 02) | RELIABLE + TRANSIENT_LOCAL | odbiorca, który wstał później, musi poznać aktualny stan, a nie czekać na kolejną zmianę |

Zasada do zapamiętania: **strumienie best effort, zdarzenia i komendy
reliable.** Reszta to niuanse.

I teraz ironia twojego repo: `/grasp_verdict` jest zadeklarowany jako kanał
zdarzeń — RELIABLE — ale przez zakomentowaną detekcję zbocza leci 50 Hz.
Płacisz koszt kanału zdarzeń za ruch strumienia. Na jednym robocie w piwnicy
to nie boli. Na dziesięciu przez WiFi — boli.

### Co widzi które narzędzie

| narzędzie | odpowiada na pytanie | czego nie pokaże |
|---|---|---|
| `ros2 node info` (`show-node-connections.sh`) | co ten węzeł nadaje, czego słucha, jakie ma usługi i akcje | QoS drugiej strony |
| `ros2 topic info -v` (`show-topic-connections.sh`) | kto stoi na tym kanale i **z jakim profilem QoS każdy z nich** | głębokości kolejki zdalnych endpointów (`UNKNOWN`) |
| `ros2 topic list -t` (`list-topics.sh`) | co w ogóle istnieje i jakiego typu | czy tamtędy cokolwiek leci |
| `ros2 param list/get/set` | co da się przestawić bez restartu | kto i kiedy to przestawił |
| `ros2 doctor` | zgodność QoS w każdej parze pub/sub, sieć, RMW, topiki bez odbiorców | przyczyny spoza ROS-a |
| `ros2 doctor --report` | pełny zrzut środowiska, w tym sekcja `QOS COMPATIBILITY LIST` | — |
| `rqt_graph` | kształt systemu, jednym spojrzeniem | QoS ani usług; krawędź rysuje przy samym istnieniu topika |

`show-node-connections.sh` i `show-topic-connections.sh` to **dwie strony
tego samego grafu**: pierwszy patrzy od węzła („co ja nadaję"), drugi od
kanału („kto mnie zasila"). Przy diagnozie „węzły żyją, a się nie widzą"
zaczynasz od pierwszego, żeby potwierdzić, że obie strony w ogóle siedzą
na tej nazwie, a kończysz na drugim, bo tylko on pokazuje profile.

### Demon

`ros2` startuje w tle demona (jednego na `ROS_DOMAIN_ID`), który utrzymuje
obraz grafu, żeby każde `topic list` nie musiało czekać sekundy na odkrywanie.
Cena: wyniki bywają nieaktualne, zwłaszcza po twardym zabiciu procesu.

    ros2 daemon status
    ros2 daemon stop        # wstanie sam przy następnym poleceniu
    ros2 topic list --no-daemon

Gdy dwa polecenia dają sprzeczne odpowiedzi, `--no-daemon` jest rozstrzygający.
Zmiana `ROS_DOMAIN_ID` daje osobnego demona — to nie ten sam proces
odpowiada ci raz tak, raz inaczej.

---

## Zadania

### Zadanie 05.1 — Ekran dla kontenera (rdzeń)

**Cel:** zobaczyć w kontenerze jakiekolwiek okno, zanim zaczniesz walczyć
z konkretnym narzędziem.

Nie zaczynaj od `rviz2`. Zacznij od diagnozy, warstwa po warstwie — i pamiętaj,
że `rviz2 --help` niczego nie dowodzi, bo nie otwiera okna.

```bash
scripts/dev/enter-devcontainer.sh
echo "DISPLAY=[$DISPLAY]"      # dziś: pusto
ls /tmp/.X11-unix              # dziś: nie ma czego montować
```

Fakty o twoim środowisku, sprawdzone, żebyś nie tracił na to wieczoru:

- host to Fedora na Wayland; okna X-owe obsługuje XWayland, którego gniazdo
  leży w `/tmp/.X11-unix`;
- w obrazie **nie ma** wtyczki platformowej Qt dla Waylanda (są `xcb`,
  `offscreen`, `vnc`, `minimal`), więc natywny Wayland odpada bez dokładania
  pakietu — idziesz przez XWayland i `QT_QPA_PLATFORM=xcb`;
- w obrazie **nie ma** `xeyes` ani `xclock`; dołóż `x11-apps` do
  `Containerfile`, to najtańszy tester ekranu, jaki istnieje.

Punkt wyjścia do `.devcontainer/devcontainer.json` — hipoteza, nie wyrocznia:

```jsonc
"runArgs": [
  "--name=robotics-ros2",
  "--network=host",
  "--ipc=host",
  "--userns=keep-id",
  "-v", "/tmp/.X11-unix:/tmp/.X11-unix",
  "--security-opt", "label=disable"
],
"containerEnv": {
  "DISPLAY": "${localEnv:DISPLAY}",
  "QT_QPA_PLATFORM": "xcb"
}
```

Cztery rzeczy, o które łatwo się rozbić:

1. **`containerEnv`, nie `remoteEnv`.** `remoteEnv` dotyczy procesów, które
   uruchamia VS Code. Skrypty z `scripts/dev/ros2/` wchodzą przez
   `podman exec` i `remoteEnv` ich nie obejmie. `containerEnv` siedzi na
   samym kontenerze, więc `podman exec` je dziedziczy.
2. **SELinux.** Odmowa dostępu do gniazda to najczęściej etykieta, nie prawa.
   Na `/tmp/.X11-unix` **nie dawaj `:z` ani `:Z`** — przeetykietowałbyś katalog
   **hosta** i mógłbyś popsuć sobie sesję graficzną. Bezpieczniejsze jest
   `--security-opt label=disable` dla tego kontenera. Odmowy sprawdzasz na
   Fedorze: `sudo ausearch -m AVC -ts recent`.
3. **`xhost` po stronie hosta.** `xhost +SI:localuser:$(id -un)` wpuszcza
   twojego użytkownika. Działa, bo `--userns=keep-id` mapuje UID 1:1 — bez
   tej flagi proces w kontenerze miałby inny UID i nie przeszedłby. Nie
   przeżywa wylogowania; jeśli okna przestały wstawać „bez powodu", zacznij
   stąd. `xhost +` bez ograniczeń zostaw w spokoju.
4. **`runArgs` działają tylko przy tworzeniu kontenera.** Samo „Reopen in
   Container" nic nie zmieni — potrzebny jest
   `scripts/container/create-devcontainer-revert.sh`
   i `scripts/container/create-devcontainer.sh`.

Drabinka diagnostyczna, w tej kolejności: `echo $DISPLAY` → `ls /tmp/.X11-unix`
→ `xeyes` → `rqt_graph`. Pierwsze narzędzie, które zawiedzie, mówi ci, która
warstwa jest winna. Odwrotna kolejność daje komunikat Qt o brakującej wtyczce
platformowej i dwie godziny w złym miejscu.

**Gotowe, gdy:** `xeyes` z kontenera rysuje oczy na twoim pulpicie, a zmiany
siedzą w `Containerfile` i `devcontainer.json`, nie w twojej pamięci.

### Zadanie 05.2 — Druga droga: Foxglove bez GUI w kontenerze (rdzeń)

**Cel:** mieć podgląd systemu, który nie potrzebuje ekranu po stronie robota.

Dołóż do `.devcontainer/Containerfile`:

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
      ros-jazzy-rqt-common-plugins \
      ros-jazzy-plotjuggler-ros \
      ros-jazzy-foxglove-bridge \
      ros-jazzy-topic-tools \
      x11-apps \
 && rm -rf /var/lib/apt/lists/*
```

Potem, w kontenerze:

```bash
ros2 launch foxglove_bridge foxglove_bridge_launch.xml
```

Most wystawia WebSocket (domyślnie port 8765). Dzięki `--network=host` ten
port jest na Fedorze wprost — sprawdź `ss -ltn | grep 8765` z Ghostty, zanim
zaczniesz podejrzewać przeglądarkę. Podłącz się do `ws://localhost:8765`
i zbuduj układ z trzema panelami: wykres `/vacuum_pressure`, surowe
wiadomości `/grasp_verdict`, lista topiców.

**To jest droga, którą realnie używa się na prawdziwym robocie.** Tam też nie
ma monitora, nie ma X-ów i nie ma kogo prosić o `xhost`. Jest sieć i jest
przeglądarka na twoim laptopie. Wszystko, czego nauczysz się tutaj, przenosi
się na maszynę w hali bez zmian; wszystko, czego nauczysz się o XWaylandzie,
zostaje na biurku.

**Gotowe, gdy:** widzisz w przeglądarce żywy wykres ciśnienia, a `set-param.sh
/vacuum_sensor state sealed` przestawia go na oczach.

### Zadanie 05.3 — Ten sam graf trzema narzędziami (rdzeń)

**Cel:** zobaczyć, że „graf" to trzy różne widoki i żaden nie jest kompletny.

Przy działających obu węzłach obejrzyj ten sam system:

```bash
scripts/dev/ros2/show-node-connections.sh /grasp_monitor
scripts/dev/ros2/show-topic-connections.sh /vacuum_pressure
```

i na koniec `rqt_graph` (albo panel topiców w Foxglove). Wypisz sobie na
kartce, czego brakuje w każdym z trzech.

**Gotowe, gdy:** umiesz wskazać po jednej rzeczy widocznej tylko w jednym
z tych trzech widoków.

### Zadanie 05.4 — Przeczytaj QoS obu stron (rdzeń)

**Cel:** nauczyć się czytać wydruk, który za chwilę uratuje ci wieczór.

```bash
scripts/dev/ros2/show-topic-connections.sh /vacuum_pressure
scripts/dev/ros2/show-topic-connections.sh /grasp_verdict
```

Dla każdego endpointu dostaniesz nazwę węzła, typ, hash typu, GID i blok
`QoS profile:` z siedmioma liniami. Porównaj `Reliability` nadawcy i odbiorcy
na obu topikach. Sprawdź, czy widzisz `History (Depth): UNKNOWN` i czy umiesz
powiedzieć, skąd się bierze. Zerknij też na `offered_qos_profiles`
w `projects/grab-fail-detection/bags/chwyt-3-stany/metadata.yaml` — to ten
sam kontrakt, tylko zapisany na dysku.

Na koniec `ros2 doctor` i `ros2 doctor --report`; znajdź sekcję
`QOS COMPATIBILITY LIST`.

**Gotowe, gdy:** umiesz z pamięci powiedzieć, która strona `/vacuum_pressure`
oferuje, a która żąda, i dlaczego ta para działa.

### Zadanie 05.5 — Wykres na żywo i z nagrania (rdzeń)

**Cel:** zobaczyć kształt sygnału, a nie kolumnę liczb.

```bash
ros2 run plotjuggler plotjuggler
```

Najpierw na żywo: źródło „ROS2 Topic Subscriber", `/vacuum_pressure`
i `/grasp_verdict` na jednym wykresie. Przestawiaj `state` przez
`set-param.sh` i patrz na przejścia. Potem to samo z pliku: wczytaj
`projects/grab-fail-detection/bags/chwyt-3-stany/` jako źródło danych.
PlotJuggler ma własne ustawienia QoS w oknie wyboru topiców — jeśli na żywo
nic nie widać, a z pliku widać, szukaj tam.

To jest najlepszy stosunek wartości do wysiłku w całym tym etapie:
dziesięć minut na narzędzie, po których pierwszy raz widzisz swoje dane.
`rqt_plot` z obrazu robi to samo słabiej — warto go raz odpalić, żeby
wiedzieć, czego się nie traci.

O `rviz2` uczciwie: bez modelu robota i bez drzewa TF nie masz w nim jeszcze
czego oglądać. Odpal go raz, żeby potwierdzić, że ekran działa, i zostaw —
wraca w [etapie 08](./08-tf2-urdf-ros2-control.md) z prawdziwym zadaniem.

**Gotowe, gdy:** masz na ekranie trzy poziomy ciśnienia i widzisz gołym okiem,
że werdykt leci ciągle, a nie na zmianie stanu.

### Zadanie 05.6 — Zepsuj to: RELIABLE u odbiorcy (rdzeń, obowiązkowe)

**Cel:** zmierzyć, ile zajmuje ci diagnoza ciszy — narzędziami, bez kodu.

Włącz stoper. W `ws/src/grip_monitor/grip_monitor/grasp_monitor.py` zmień
`ReliabilityPolicy.BEST_EFFORT` na `RELIABLE` w profilu subskrypcji.
Przy `--symlink-install` wystarczy restart węzła. Teraz **zamknij edytor**
i diagnozuj:

    list-topics.sh              → topic jest, typ się zgadza
    show-topic-connections.sh   → dwa endpointy, dwa różne Reliability

Cel: poniżej dwóch minut. Potem sprawdź się drugą drogą — `ros2 doctor`
powinien wypisać błąd zgodności z nazwą topika. Zerknij też, czy w terminalu
monitora pojawiła się linia WARN o „incompatible QoS"; jeśli nie, tym lepiej
dla nauczki.

Po drodze zrób dwie rzeczy, które psują intuicję na zawsze: odpal
`print-topic-messages.sh /vacuum_pressure` i `measure-topic-rate.sh
/vacuum_pressure`. Oba pokażą, że kanał żyje. Zapisz sobie dlaczego.

**Gotowe, gdy:** trafiasz w przyczynę w dwie minuty, potrafisz wskazać dwie
linie wydruku, które ją dowodzą, i umiesz wytłumaczyć, czemu echo widzi dane.

### Zadanie 05.7 — `topic_tools drop`: gubienie pakietów na żądanie (rdzeń)

**Cel:** zepsuć strumień bez dotykania kodu i zobaczyć, co to robi z detektorem.

```bash
scripts/dev/ros2/run-node.sh grip_monitor vacuum_sensor \
  --ros-args -r vacuum_pressure:=vacuum_pressure_raw
ros2 run topic_tools drop /vacuum_pressure_raw 4 5 /vacuum_pressure
```

`drop` przepuszcza jedną wiadomość na pięć. Monitor nie wie o niczym — widzi
swój topic jak zawsze. Zmierz tempo (`measure-topic-rate.sh`) i policz, ile
teraz trwa napełnienie `deque(maxlen=25)` w `grasp_monitor.py`. Przy 50 Hz
to pół sekundy. Przy 10 Hz — dwie i pół.

To jest wynik tego zadania i warto go zapisać w
`projects/grab-fail-detection/NOTES.md`: **twój detektor nie ma pojęcia
o czasie, tylko o liczbie próbek.** Gubienie pakietów nie pogarsza mu
dokładności — przesuwa mu okno czasowe, a tego nie widać w żadnym wykresie
werdyktu. Sprawdź przy okazji `ros2 topic info -v /vacuum_pressure`: profil
oferowany przez `drop` to teraz profil węzła `drop`, nie twojego czujnika.
Spróbuj też `throttle` i `relay`; składnię potwierdź w README pakietu.

**Gotowe, gdy:** masz zmierzone opóźnienie werdyktu po zmianie tempa i umiesz
powiedzieć, dlaczego rośnie.

### Zadanie 05.8 — Dwa światy i dwóch nadawców (rozszerzenie)

**Cel:** zobaczyć izolację domen i to, co robi dwóch nadawców na jednym kanale.

Część pierwsza. W terminalu VS Code (w kontenerze) ustaw `export
ROS_DOMAIN_ID=7` i uruchom tam czujnik. Z drugiego terminala, bez tej zmiennej,
odpal `list-running-nodes.sh`. Potem spróbuj przekazać domenę z Fedory:

```bash
ROS_DOMAIN_ID=7 scripts/dev/ros2/list-running-nodes.sh
```

i sprawdź, czy to w ogóle zadziałało. Podpowiedź: zajrzyj do
`scripts/lib/container.sh` i zobacz, jak wygląda wywołanie `podman exec`.
Odpowiedź na pytanie „czy skrypty z `dev/` naprawdę dają ten sam wynik po obu
stronach granicy" jest tutaj ciekawsza, niż się spodziewasz.

Część druga. Wróć do jednej domeny i uruchom **drugi** czujnik:

```bash
scripts/dev/ros2/run-node.sh grip_monitor vacuum_sensor \
  --ros-args -r __node:=vacuum_sensor_2 -p state:=sealed
```

Pierwszy niech zostanie na `open`. Teraz `show-topic-connections.sh
/vacuum_pressure` pokaże `Publisher count: 2`, `measure-topic-rate.sh`
pokaże około 100 Hz, a monitor policzy średnią z **przeplecionych** próbek
z dwóch źródeł. Zobacz, jaki werdykt z tego wychodzi.

**Gotowe, gdy:** umiesz wyjaśnić, czemu dwóch nadawców — jeden `open`, drugi
`sealed` — daje pewny werdykt, którego nie potwierdza żaden z nich.

---

## Pułapki

| objaw | przyczyna | co zrobić |
|---|---|---|
| `cannot open display` | brak `DISPLAY` albo brak montowania `/tmp/.X11-unix` | zadanie 05.1; sprawdź w tej kolejności: `echo $DISPLAY`, `ls /tmp/.X11-unix` |
| `Authorization required, but no authorization protocol specified` | gniazdo jest, ale serwer X nie wpuszcza | na Fedorze `xhost +SI:localuser:$(id -un)`; pamiętaj, że to nie przeżywa wylogowania |
| `Permission denied` na `/tmp/.X11-unix` | SELinux | `sudo ausearch -m AVC -ts recent` na Fedorze; `--security-opt label=disable`, **nie** `:Z` na tym katalogu |
| Qt: `could not load the Qt platform plugin "wayland"` | w obrazie nie ma wtyczki waylandowej | `QT_QPA_PLATFORM=xcb` i droga przez XWayland |
| zmieniłeś `runArgs`, nic się nie zmieniło | `runArgs` działają tylko przy tworzeniu kontenera | `create-devcontainer-revert.sh`, potem `create-devcontainer.sh` |
| `ros2 run topic_tools ...` — nie ma pakietu | zainstalowany w działającym kontenerze albo wcale | dopisz do `Containerfile` i przebuduj; `apt install` w środku ginie przy odtworzeniu |
| `ros2 node list` pokazuje węzeł, którego już nie ma | demon cache'uje graf | `ros2 daemon stop` albo `--no-daemon` na poleceniu |
| `echo` pokazuje dane, twój węzeł nie dostaje nic | `echo` dobiera QoS pod nadawcę, twój kod ma go na sztywno | `show-topic-connections.sh TOPIC` i porównaj `Reliability` obu stron |
| `measure-topic-rate.sh` pokazuje 50 Hz, choć odbiorca milczy | `ros2 topic hz` subskrybuje profilem `sensor_data`, czyli BEST_EFFORT — zawsze pasuje | `hz` mierzy nadawcę, nie połączenie; nie używaj go jako dowodu |
| `list-running-nodes.sh` pusty, choć węzeł chodzi | inny `ROS_DOMAIN_ID` po którejś stronie | `echo $ROS_DOMAIN_ID` w obu terminalach; pamiętaj o osobnym demonie na domenę |
| zmienna z Fedory nie dociera do kontenera | `podman exec` w `scripts/lib/container.sh` nie przekazuje środowiska hosta | ustaw ją w terminalu **wewnątrz** kontenera (zadanie 05.8) |
| węzły w kontenerze widzą się, ale duże wiadomości nie przechodzą | brak `--ipc=host`, rozjechana pamięć dzielona | sprawdź `runArgs` w `devcontainer.json` |
| Foxglove w przeglądarce nie łączy się z `ws://localhost:8765` | most nie działa, zły port albo przeglądarka blokuje niezabezpieczony WebSocket | najpierw `ss -ltn \| grep 8765` z Ghostty, dopiero potem podejrzewaj przeglądarkę; w razie czego aplikacja desktopowa |
| problem znika po `RMW_IMPLEMENTATION=rmw_cyclonedds_cpp` | to była właściwość implementacji DDS, nie twojego kodu | zanotuj i nie „napraw" tego zmianą RMW na stałe bez zrozumienia |

---

## Sprawdź się

1. Nadawca oferuje BEST_EFFORT, odbiorca żąda RELIABLE. Co dokładnie
   zobaczysz w `ros2 node list`, `ros2 topic list` i `rqt_graph` — i dlaczego
   każde z nich wygląda normalnie?
2. Dlaczego `ros2 topic hz` pokaże tempo na kanale, z którego twój węzeł nie
   dostaje nic, a `ros2 topic echo` bywa jeszcze bardziej mylące?
3. Czemu `history` i `depth` nie biorą udziału w sprawdzaniu zgodności i skąd
   bierze się `UNKNOWN` w wydruku `topic info -v`?
4. `/vacuum_pressure` ma BEST_EFFORT, a `/grasp_verdict` RELIABLE. Uzasadnij
   oba wybory jednym zdaniem każdy, nie powołując się na to, że „tak jest
   w kodzie".
5. Dlaczego `--ipc=host` i `--network=host` są warunkiem działania, a nie
   optymalizacją? Który z nich psuje odkrywanie, a który transport?
6. Masz dwa terminale i różne `ROS_DOMAIN_ID`. Ile działa demonów, co pokaże
   każdy z nich i dlaczego to nie jest awaria?
7. Kiedy `rqt_graph` narysuje krawędź, której w rzeczywistości nie ma?
8. Dlaczego podgląd przez `foxglove_bridge` jest na prawdziwym robocie
   bardziej użyteczny niż przekazane GUI, mimo że pokazuje mniej?

---

## Co przeczytać

- `https://docs.ros.org/en/jazzy/` — strony o ustawieniach QoS i o konfiguracji
  środowiska (`ROS_DOMAIN_ID`, zasięg odkrywania). Czytaj dla wartości
  domyślnych i dokładnej semantyki `ROS_AUTOMATIC_DISCOVERY_RANGE`, bo to
  jest rzecz, którą trzeba sprawdzić, a nie zapamiętać.
- `https://design.ros2.org/` — artykuły o ROS na DDS i o politykach QoS
  (deadline, liveliness, lifespan). Po to, żeby zrozumieć, **dlaczego** te
  polityki wyglądają tak, a nie inaczej — to są decyzje projektowe, nie API.
- `https://github.com/eProsima/Fast-DDS` — dokumentacja domyślnej
  implementacji: transport przez pamięć dzieloną, discovery, konfiguracja XML.
  Wracasz tu, gdy objawy zależą od RMW.
- `https://github.com/ros-tooling/topic_tools` — README z dokładną składnią
  `relay`, `throttle`, `drop`. Zaglądasz raz i kopiujesz.
- `https://github.com/foxglove/ros-foxglove-bridge` — parametry mostu
  (port, filtrowanie topiców, limity). Przyda się, gdy topików będzie sto,
  a nie dwa.
- `https://github.com/facontidavide/PlotJuggler` — skróty i możliwości, których
  nie widać po ikonach; zwłaszcza transformacje serii i zapis układu paneli.

---

## Dziennik

    Data:

    1. Która warstwa GUI zjadła najwięcej czasu — DISPLAY, SELinux, xhost
       czy Qt? Co było pierwszym sygnałem, że to właśnie ta?

    2. Ile zajęła ci diagnoza z zadania 05.6 przy pierwszej próbie?
       A ile przy drugiej, po tygodniu?

    3. Które narzędzie okłamało cię najbardziej przekonująco i dlaczego
       mu uwierzyłeś?

    4. Co zobaczyłeś na wykresie, czego nie widać było w `print-topic-messages`?

    5. Jedno zdanie o QoS, którego nie umiałbyś napisać tydzień temu.

Dalej → [Etap 06 — Logi, diagnostyka, cykl życia](./06-logi-diagnostyka-lifecycle.md)
