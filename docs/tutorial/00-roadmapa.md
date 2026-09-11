# Roadmapa: od węzła ROS-a do warstwy obserwowalności i testowalności

Dwanaście etapów, każdy w osobnym pliku. Nie jest to kurs ROS-a — ROS jest
tu materiałem, na którym uczysz się **widzieć i udowadniać**, co robot robi.

Piszesz software od lat. Ta roadmapa nie uczy cię programować; uczy cię,
czym w robocie jest to, co w backendzie nazywasz kontraktem API, fixture'em,
APM-em, health checkiem i testem regresji — i w którym miejscu ta analogia
pęka, bo robot ma czas, fizykę i stan, którego nie da się zrestartować.

---

## Skąd startujesz

Stan repo na dziś (to jest twoje wejście do etapu 01):

| masz | plik | co to naprawdę jest |
|---|---|---|
| środowisko | `.devcontainer/` | ROS 2 Jazzy w kontenerze podmana, repo zamontowane pod tą samą ścieżką |
| fałszywy czujnik | `ws/src/grip_monitor/grip_monitor/vacuum_sensor.py` | `Float32` na `/vacuum_pressure`, 50 Hz, parametr `state`, szum gaussowski |
| detektor | `ws/src/grip_monitor/grip_monitor/grasp_monitor.py` | średnia z 25 próbek, trzy progi, `String` na `/grasp_verdict` |
| jedno nagranie | `projects/grab-fail-detection/bags/chwyt-3-stany/` | 2124 wiadomości, 21 s, mcap — i ślad po kodzie, którego już nie ma |
| dziewięć narzędzi | `scripts/dev/ros2/` | list/show/print/measure/run/set — twój pierwszy zestaw do introspekcji |

I to jest dobry start, nie zaległość. Ale ten kod ma **cztery wady, które
zobaczysz dopiero, gdy spróbujesz go przetestować** — i dlatego roadmapa
zaczyna się od nich, a nie od Gazebo:

1. `String` z tekstem `'[state] sealed'` to nie jest wiadomość, tylko log
   udający dane. Nic tego nie zwaliduje, nic nie odróżni „sealed" od
   „Sealed", a za rok nikt nie wie, jakie wartości są dozwolone.
2. Wiadomość nie ma stempla czasu. Nie da się policzyć opóźnienia
   czujnik → werdykt, a to jest **pierwsza liczba, o którą zapyta każdy**,
   kto to wdroży.
3. Detekcja zbocza jest zakomentowana (`# self.last_state = ...`), więc
   werdykt leci 50 razy na sekundę zamiast raz na zmianę stanu. Na wykresie
   tego nie widać. Na łączu i w bagu — bardzo.
4. Logika siedzi w callbacku węzła, więc żeby ją sprawdzić, musisz
   uruchomić ROS-a. Czyli: nie sprawdzasz jej wcale.

Każda z tych czterech wad jest typowa, każda ma swój etap i każda znika
przez zrozumienie, a nie przez poprawkę.

Piąta rzecz nie jest wadą kodu, tylko faktem o danych — i najtańszą lekcją
w całym repo. W twoim nagraniu leżą werdykty `[state] empty`, a dzisiejszy
`grasp_monitor.py` publikuje `open`. Bag powstał na wersji, której już nie ma,
i nikt tego nigdzie nie zapisał. **Dane przeżywają kod.** Etapy 03 i 04 wracają
do tego, bo to samo zdarzy ci się w pracy — tyle że z nagraniem sprzed dwóch lat
i bez autora pod ręką.

Przy okazji: w tym samym nagraniu siedzi policzalny błąd. Okno 25 próbek przy
50 Hz sprawia, że po złapaniu przedmiotu średnia dochodzi do poziomu `sealed`
liniowo, przechodząc przez pasmo `leak`. Każde szczelne złapanie produkuje
**dokładnie 24 fałszywe werdykty „nieszczelność", przez 0,48 sekundy** — i one
są w twoim bagu. Nikt tego nie zauważył, bo nikt nigdy nie przepuścił tego
nagrania przez asercję.

---

## Dokąd to prowadzi

Po dwunastu etapach umiesz wejść do cudzego systemu robotycznego i w ciągu
jednego dnia odpowiedzieć na pytania, na które dziś nikt w zespole nie
odpowiada szybko:

- Co ten system w ogóle publikuje i **kto tego słucha**?
- Ile trwa droga od zdarzenia fizycznego do decyzji — p50, p95, **ogon**?
- Skąd wiemy, że działa? Co się stanie, gdy przestanie — i **czy się dowiemy**?
- Mamy nagranie awarii. Da się z niego zrobić test, który zapali się,
  gdy ktoś wprowadzi tę awarię ponownie?
- Ta zmiana nic nie psuje — **na jakich danych to sprawdziłeś**?

To jest realna, wąska i słabo obsadzona rola: test/tooling/platform
engineer w robotyce. Firma z dziesięcioma robotami w polu utonie bez niej,
a w ogłoszeniach nadal szuka „ROS developera".

---

## Jak się uczyć tą roadmapą

**Jeden etap to nie jedno posiedzenie.** Realnie 2–4 wieczory. Etap jest
skończony, gdy spełniasz „kończy się" z nagłówka pliku — nie gdy
przeczytasz.

**Pętla, która działa (i jest nieprzyjemna):**

1. Przeczytaj sekcje „po co / ciekawe / trudne" **zanim** cokolwiek zrobisz.
   Bez tego zadania są klikaniem i nie zostają w głowie.
2. Zrób zadania po kolei. Każde ma „Gotowe, gdy:" — to jedyne kryterium.
3. **Zepsuj to.** Po każdym zadaniu zmień jedną rzecz tak, żeby przestało
   działać, i sprawdź, czy twoje narzędzia to pokazują. Jeśli nie pokazują —
   to jest prawdziwe zadanie tego etapu, nie to z listy.
4. Odpowiedz na pytania ze „Sprawdź się" **z głowy, na głos**. Te, przy
   których się zawahasz, wróć i przeczytaj.
5. Zapisz w „Dziennik" na końcu pliku: co cię zaskoczyło, co ci zajęło
   najwięcej czasu, i jedno zdanie, którego nie umiałbyś napisać tydzień temu.

**Nie czytaj do przodu.** Etapy są ustawione tak, że każdy naprawia problem,
który zobaczyłeś w poprzednim. Czytane bez tego bólu brzmią jak ceremoniał.

### Budowa każdego etapu

Wszystkie pliki mają ten sam układ, żebyś wiedział, czego gdzie szukać, gdy
wrócisz do nich za pół roku:

| sekcja | po co tam jest |
|---|---|
| **Po ludzku** | tłumaczenie pojęć na twój świat i miejsce, w którym analogia pęka |
| **Po co to / ciekawe / trudne** | powód, żeby to zrobić, i uczciwe ostrzeżenie, gdzie boli |
| **Wycinek prawdziwej roboty** | scena z firmy, w której ta umiejętność jest czyjąś płatną pracą — po co ci to poza nauką |
| **Model pojęciowy** | wiedza. Czytasz przed zadaniami, wracasz w trakcie |
| **Zadania** | każde ma **Cel** (co będziesz mieć), **Ćwiczysz** (po co akurat ono) i **Gotowe, gdy** (kryterium, jedyne) |
| **Pułapki** | objaw → przyczyna → co zrobić. Tu zaglądasz, gdy stoisz |
| **Sprawdź się** | pytania, na które odpowiadasz z głowy. Wahanie = wróć do modelu |
| **Dziennik** | twoje notatki, wypełniane zanim przejdziesz dalej |

**Wycinek prawdziwej roboty czytaj przed zadaniami, nie po.** Bez niego zadania
są ćwiczeniem, a z nim są miniaturą dnia pracy — a to zupełnie inaczej siedzi
w głowie i inaczej się o tym opowiada na rozmowie.

**Zasada, na której stoi cała roadmapa:** *narzędzie, które nigdy nie
pokazało ci czegoś, czego nie wiedziałeś, jest dekoracją.* Dotyczy to
tak samo wykresu, jak testu, jak dashboardu.

---

## Mapa etapów

| # | etap | co zyskujesz | główne narzędzia |
|---|---|---|---|
| [01](./01-kontrakty-wiadomosci.md) | Kontrakty: własne interfejsy | dane, które da się zwalidować i wersjonować | `rosidl`, `ros2 interface`, typy RIHS |
| [02](./02-czas-zdarzenia-stan.md) | Czas, zdarzenia, stan | stemple, opóźnienie, zdarzenie ≠ stan | `use_sim_time`, `/clock`, QoS durability |
| [03](./03-bagi-jako-dane.md) | Bagi jako dane testowe | nagranie staje się fixture'em | `rosbag2`, mcap, `rosbag2_py` |
| [04](./04-piramida-testow.md) | Piramida testów | test, który umie zawieść | `pytest`, `launch_testing_ros`, `colcon test` |
| [05](./05-introspekcja-qos-narzedzia.md) | Introspekcja i QoS | diagnoza „węzły są, a się nie widzą" | `ros2 doctor`, PlotJuggler, Foxglove, rviz2 |
| [06](./06-logi-diagnostyka-lifecycle.md) | Logi, diagnostyka, cykl życia | system, który sam mówi, że mu źle | `/rosout`, `diagnostic_updater`, lifecycle |
| [07](./07-gazebo-stanowisko.md) | Gazebo jako stanowisko | awarie na żądanie, powtarzalnie | Gazebo Harmonic, `ros_gz_bridge` |
| [08](./08-tf2-urdf-ros2-control.md) | Geometria i napędy | model, TF, sterowniki, chwyt w symulacji | URDF/xacro, `tf2`, `ros2_control` |
| [09](./09-latencja-i-tracing.md) | Pomiar i tracing | liczby zamiast wrażeń, ogon zamiast średniej | `ros2 topic delay`, `ros2 trace`, LTTng |
| [10](./10-ewaluacja-na-danych.md) | Ewaluacja detektora | próg wybrany z danych, nie z sufitu | macierz pomyłek, przemiatanie progów |
| [11](./11-ci-i-awarie.md) | CI i wstrzykiwanie awarii | regresja zapala się sama | GitHub Actions, `tc netem`, chaos |
| [12](./12-flota-i-dalej.md) | Flota i dalsza droga | telemetria poza robotem, plan na dalej | Foxglove/MQTT/Prometheus, SLO, normy |

Etapy 01–04 naprawiają fundament (bez nich reszta nie ma czego mierzyć).
05–06 to warstwa obserwowalności na żywym systemie. 07–08 dokładają
symulator, czyli jedyne miejsce, gdzie awarię da się wywołać na żądanie.
09–11 to profesjonalizacja: liczby, dane, automat. 12 wychodzi poza jeden
robot.

---

## Słownik: twój świat → robotyka

Tabela do powieszenia nad biurkiem. Ostatnia kolumna jest ważniejsza niż
druga — **analogia niesie cię do pierwszej pułapki i tam cię zostawia.**

| w backendzie | w ROS 2 | gdzie analogia pęka |
|---|---|---|
| schemat API / protobuf | `.msg`, `.srv`, `.action` | nie ma negocjacji wersji — niezgodny hash typu to cisza, nie błąd 400 |
| REST call | usługa (`srv`) | brak odbiorcy = czekasz w nieskończoność, nie dostajesz 404 |
| zadanie w kolejce | akcja (`action`) | ma feedback, cancel i stan pośredni; i może zostawić świat w połowie ruchu |
| pub/sub (Kafka) | topic + DDS | brak brokera i brak retencji; kto nie słuchał, nie usłyszy (chyba że `transient_local`) |
| nagłówki HTTP / trace context | `header.stamp` + `frame_id` | stempel to nie metadana, tylko **dane** — bez niego pomiar jest niemożliwy |
| VCR / nagrane odpowiedzi | rosbag2 | odtwarza wiadomości, nie odtwarza czasu, kolejności ani QoS |
| healthcheck / liveness probe | `/diagnostics`, heartbeat | „żyje" nie znaczy „widzi"; czujnik potrafi publikować stare śmieci |
| readiness probe, faza startu | węzeł cyklu życia (lifecycle) | stan jest sterowany z zewnątrz i **obserwowalny**, to nie jest wewnętrzna sprawa procesu |
| APM / distributed tracing | `ros2_tracing` + LTTng | śledzisz callbacki i executor, nie żądania; nie ma ID korelacji z pudełka |
| p95 latency | to samo | ale ogon bije w fizykę: spóźniona decyzja to upuszczony przedmiot, nie wolniejsza strona |
| staging | symulacja (Gazebo) | staging kłamie inaczej — tarcie, opóźnienie i szum są tam za ładne |
| testy integracyjne | `launch_testing` | uruchamiasz procesy i czekasz na zdarzenia w czasie rzeczywistym; flaky jest domyślne |
| feature flag | parametr ROS-a | da się zmienić w locie, ale nikt nie zapisuje, że zmieniłeś |
| logi aplikacji | `/rosout` | to jest **topic** — podlega QoS i można go nagrać razem z danymi |

---

## Co dokładasz do środowiska

Wszystko idzie do `.devcontainer/Containerfile` — nigdy `apt install`
w działającym kontenerze (zginie przy odtworzeniu; `AGENTS.md` mówi o tym
wprost). Wersje sprawdzone w tym obrazie, w repozytorium ROS-a dla Jazzy:

| etap | pakiety apt |
|---|---|
| 05 | `ros-jazzy-rqt-common-plugins`, `ros-jazzy-plotjuggler-ros`, `ros-jazzy-foxglove-bridge`, `ros-jazzy-topic-tools` |
| 06 | `ros-jazzy-diagnostic-updater`, `ros-jazzy-diagnostic-aggregator` |
| 07–08 | `ros-jazzy-ros-gz` (ciągnie Gazebo Harmonic jako pakiety `*-vendor`), `ros-jazzy-ros2-control`, `ros-jazzy-ros2-controllers`, `ros-jazzy-gz-ros2-control` |
| 09 | `ros-jazzy-ros2trace`, `ros-jazzy-tracetools-analysis`, `lttng-tools` |

Już masz w obrazie (nie instaluj): `rosbag2-storage-mcap`, `rosbag2-py`,
`rviz2`, `rqt-graph`, `rqt-plot`, `tf2-tools`, `launch-testing`,
`launch-testing-ros`, `message-filters`, `tracetools`.

### Jedna rzecz do zrobienia zanim dojdziesz do etapu 05

**Twój kontener nie ma przekazanego ekranu.** Sprawdzone: `podman inspect`
nie pokazuje ani zmiennej `DISPLAY`, ani montowania `/tmp/.X11-unix`.
Konsekwencja: `rviz2`, `rqt`, PlotJuggler i GUI Gazebo **nie wstaną**, a
komunikat błędu będzie mówił o „cannot open display", nie o kontenerze.

To jest pierwsze zadanie etapu 05 i celowo nie jest załatwione z góry:
przekazanie GUI z kontenera na Fedorze (Wayland + SELinux + podman rootless)
jest dokładnie tym rodzajem problemu, który w tej robocie spotkasz co
tydzień, a rozwiązuje się go raz i zapisuje w `Containerfile`.

---

## Zasady obowiązujące we wszystkich etapach

1. **Każda zmiana środowiska idzie do `.devcontainer/Containerfile`.**
   Kontener ma być odtwarzalny z pliku, nie z twojej pamięci.
2. **Każdy etap kończy się czymś, co widać** — wydrukiem, wykresem,
   czerwonym testem, plikiem. „Zrozumiałem" nie jest efektem.
3. **Test, który nigdy nie zapalił się na czerwono, nie jest testem.**
   Zanim uznasz go za gotowy, zepsuj kod i zobacz, że pada.
4. **Nowy pakiet ROS-a to `ws/src/<nazwa>/`, nowy projekt to katalog
   w `projects/`.** Jedno repo, jeden workspace — jak w `AGENTS.md`.
5. **Nazwy skryptów trzymają konwencję z `AGENTS.md`**: `list-`/`show-`
   oddają terminal i nic nie zmieniają, `print-`/`measure-` trzymają do
   Ctrl+C, `run-`/`set-` zmieniają stan procesu.
6. **Notatki z projektu lądują w `projects/grab-fail-detection/NOTES.md`**,
   dziennik nauki — w pliku etapu. To dwie różne rzeczy: pierwsza to
   dziennik systemu, druga twój.

---

## Czego tu nie ma i dlaczego

| pominięte | dlaczego |
|---|---|
| nawigacja, SLAM, Nav2 | inny dział robotyki (mobilna); twoja cela stoi w miejscu |
| MoveIt 2 w głąb | planowanie ruchu to osobna specjalizacja; w etapie 08 pojawia się tylko tyle, ile potrzeba, by ramię się ruszyło |
| percepcja 3D i sieci neuronowe | najgłębsza studnia w robotyce; etap 10 daje ci metryki, którymi ocenisz **cudzy** model — i to jest twoja rola |
| bezpieczeństwo funkcjonalne (ISO 13849, IEC 61508) | to nie jest warstwa software'u aplikacyjnego; etap 12 mówi, co musisz o tym wiedzieć, żeby nie obiecać czegoś, czego nie wolno |
| C++ / `rclcpp` | Python wystarczy do wszystkiego w tej roadmapie poza `ros2_control`; C++ dokładaj, gdy trafisz na 1 kHz albo cudzy kod |
| real-time (PREEMPT_RT) | etap 09 pokazuje, gdzie kończy się Python i zaczyna ten temat — świadomie na granicy |

---

## Dziennik postępów

    [ ] 01  kontrakty: własne interfejsy
    [ ] 02  czas, zdarzenia, stan
    [ ] 03  bagi jako dane testowe
    [ ] 04  piramida testów
    [ ] 05  introspekcja i QoS
    [ ] 06  logi, diagnostyka, cykl życia
    [ ] 07  Gazebo jako stanowisko
    [ ] 08  geometria i napędy
    [ ] 09  latencja i tracing
    [ ] 10  ewaluacja na danych
    [ ] 11  CI i wstrzykiwanie awarii
    [ ] 12  flota i dalsza droga

Dalej → [Etap 01 — Kontrakty: własne interfejsy](./01-kontrakty-wiadomosci.md)
