# Etap 06 — Logi, diagnostyka i cykl życia węzła

> Po tym etapie twój system sam mówi, że mu źle — maszynie, nie tobie — a „gotowy do pracy" przestaje być domysłem i staje się stanem, o który można zapytać z zewnątrz.

| | |
|---|---|
| wejście | etapy 01–05; oba węzły działają, umiesz je obejrzeć narzędziami z `scripts/dev/ros2/` i wiesz, co QoS robi z `/vacuum_pressure` |
| czas | 3 wieczory (dwa na diagnostykę, jeden na lifecycle) |
| kończy się | zabijasz `vacuum_sensor` w trakcie pracy i w ciągu sekundy widzisz `STALE` na `/diagnostics_agg`, bez zaglądania w cokolwiek innego |

## Po ludzku: co to jest w twoim świecie

| pojęcie robotyczne | odpowiednik z backendu | gdzie analogia pęka |
|---|---|---|
| `DiagnosticStatus.level` | status w `/healthz`: up/down | ma cztery wartości, a czwarta (`STALE`) znaczy „nie wiem", nie „źle" — i to ona ratuje ci tyłek |
| `Updater` publikujący co 1 s | eksporter metryk pod `/metrics` | to **push**, nie pull: gdy proces padnie, nikt tego nie zescrapuje, więc brak wpisu musi zinterpretować ktoś trzeci |
| `diagnostic_aggregator` + YAML | reguły alertingu w Prometheusie | reguły leżą obok robota i chodzą **na** robocie; nie ma centrali, która zauważy, że cały robot zamilkł |
| `throttle_duration_sec` | rate limiter w loggerze | limit jest per **miejsce w kodzie**, nie per komunikat i nie per klucz — wspólna funkcja pomocnicza zdusi wszystkie wywołania w jeden kubełek |
| przejście `activate` | rolling update, feature flag | wywołuje je ktoś z zewnątrz, w dowolnym momencie, także w środku ruchu — i nie ma niczego takiego jak „drain" |
| `~/.ros/log/` | plik logu usługi | plik jest per **proces**, nie per usługa, nikt go nie rotuje, a w tym kontenerze ginie razem z kontenerem |

## Po co to — czego bez tego nie da się zrobić

Uruchom oba węzły i zabij `vacuum_sensor` (Ctrl+C w jego terminalu). Popatrz,
co się dzieje:

- `/vacuum_pressure` przestaje istnieć,
- `grasp_monitor` żyje, `list-running-nodes.sh` go pokazuje,
- `frame` w `grasp_monitor` zostaje z ostatnimi 25 próbkami i nigdy się nie
  zmienia, bo `on_measurement` już się nie wykonuje,
- `/grasp_verdict` **milczy**,
- nic nigdzie nie krzyczy.

To jest najgorsza awaria, jaka ci się może przytrafić: system wygląda na
zdrowy, bo wszystko, co miało być czerwone, po prostu zniknęło. W backendzie
odpowiednikiem jest metryka, która przestała przychodzić — i dlatego alert
oparty na `error_rate > 0` się nie zapala. Tutaj kosztuje to celę, która
przez trzy godziny „chwyta" powietrze i nikt tego nie zauważa, bo nikt nie
patrzy na terminal.

Drugi przypadek jest w `ws/src/grip_monitor/grip_monitor/vacuum_sensor.py`,
w ostatniej linii `_get_state_value()`:

```python
raise RuntimeError('Invalid state')
```

Wywołane z callbacka timera, 50 razy na sekundę. Zrób
`scripts/dev/ros2/set-param.sh /vacuum_sensor state bzdura` — skrypt
odpowie **sukcesem**, bo `ros2 param set` nie ma czego odrzucić: parametr
jest zadeklarowany, typ się zgadza, nikt nie sprawdza wartości. Dwadzieścia
milisekund później węzeł umiera na wyjątku w timerze. Narzędzie, które
spowodowało awarię, zgłosiło powodzenie. Awaria wygląda na niezwiązaną
z akcją, która ją wywołała.

Bez tego etapu nie da się odpowiedzieć na trzy pytania, które w tej robocie
padają najczęściej: **skąd wiemy, że działa**, **czy się dowiemy, gdy
przestanie**, i **kiedy wolno uznać, że węzeł jest gotowy**.

## Dlaczego to ciekawe

**Brak sygnału nie jest sygnałem.** `Updater` wewnątrz `vacuum_sensor` nigdy
nie zgłosi śmierci `vacuum_sensor` — bo żeby coś zgłosić, trzeba żyć. Ciszę
potrafi zinterpretować wyłącznie ktoś, kto ma **listę oczekiwanych pozycji**.
Dlatego `diagnostic_aggregator` nie jest ozdobnikiem nad `diagnostic_updater`,
tylko jedynym miejscem, gdzie nieobecność zamienia się w `STALE`. To jest
dokładnie ta sama różnica co między `up == 0` a brakiem serii czasowej —
z tą przewagą, że tutaj lista oczekiwanych pozycji jest plikiem YAML w repo,
a nie wiedzą z głowy dyżurnego.

**Log jest topikiem.** `/rosout` jedzie tym samym transportem co pomiary,
więc podlega tym samym regułom: ma QoS, ma opóźnienie, można go nagrać.
Konsekwencja jest ładniejsza, niż wygląda: jedno nagranie zawiera i pomiary,
i to, co węzeł o tych pomiarach **myślał**, na jednej osi czasu, bez
korelowania po żadnym `trace-id`. W backendzie łączenie logów z metrykami
jest projektem na kwartał. Tutaj wychodzi za darmo, bo to jedna szyna.

**Gotowość jest usługą.** Węzeł cyklu życia wystawia `~/change_state`
i `~/get_state` — czyli stan procesu przestaje być jego prywatną sprawą.
Nie „węzeł pewnie już wstał, dajmy `sleep 2`", tylko `ros2 lifecycle get`
i odpowiedź. Trzecia rzecz, którą wystawia, jest jeszcze lepsza:
`~/transition_event` to **topic**, więc historię gotowości też da się nagrać
i obejrzeć na tej samej osi co awarię.

## Dlaczego to trudne

Log wygląda na obserwowalność i nią nie jest. Zespół z czterdziestoma
`get_logger().warn()` jest przekonany, że ma monitoring — do pierwszej
awarii w nocy, gdy okazuje się, że nikt tych ostrzeżeń nie czytał, bo nie
było komu.

Diagnostyka jest **umową ustną**. Nic nie waliduje nazw pozycji, nikt nie
wymusza, co znaczy `WARN`, a agregator dopasowuje pozycje po zwykłych
stringach. Literówka w YAML-u nie jest błędem — pozycja po prostu wpada do
gałęzi `Other` i twoja gałąź wygląda na zdrową. To jest cicha porażka
w narzędziu, którego zadaniem jest wykrywanie cichych porażek.

Dławienie logów ma stan przypisany do **miejsca wywołania**, nie do treści.
Refaktor, w którym wyciągasz logowanie do wspólnej metody, potrafi zmienić
„po jednym ostrzeżeniu na sekundę z każdego z pięciu warunków" w „jedno
ostrzeżenie na sekundę łącznie, losowo które". Nic o tym nie powie.

Wyjątek w callbacku zachowuje się różnie w zależności od executora
i to jest wiedza plemienna, nie dokumentacja. Pod `SingleThreadedExecutor`
(czyli pod zwykłym `rclpy.spin()`) leci w górę i zabija proces. Pod
`MultiThreadedExecutor` ląduje w future zadania, którego nikt nie odczyta —
węzeł żyje dalej i **milczy**, a timer wywoła się znowu za 20 ms.

Lifecycle jest opcjonalny i połowa ekosystemu go nie używa, więc twój ładnie
zarządzany węzeł i tak startuje obok trzech, które robią wszystko w `__init__`.
A sam mechanizm ma pułapkę wbudowaną: zarządza **wyjściem** (publisherem),
nie **wejściem** (subskrypcją).

## Model pojęciowy

### Trzy kanały, które początkujący wrzuca do jednego worka

To jest tabela, do której wracamy przez cały etap:

| kanał | odbiorca | tempo | przykład z tego projektu |
|---|---|---|---|
| **logi** (`/rosout`) | człowiek, który przyjdzie **po fakcie** | nieregularne, rzadkie | „start: state=sealed, 50 Hz, BEST_EFFORT, depth=10" przy starcie `vacuum_sensor` |
| **dane** (topic) | inny program, **na bieżąco** | stałe, tu 50 Hz | `Float32` na `/vacuum_pressure`, `String` na `/grasp_verdict` |
| **diagnostyka** (`/diagnostics`) | **automat** pilnujący zdrowia | stałe, wolne, 1 Hz | „vacuum_pressure: 50.1 Hz, OK" i „wejście: brak danych od 3.2 s, STALE" |

Zasada, z której wynika cała reszta: **jeśli coś ma wywołać reakcję maszyny,
to nie może być logiem.** Log nie ma odbiorcy. Nikt się nie subskrybuje na
`WARN` i nikt nie zatrzyma celi, bo w linii 47 poleciał `error()`.

Odwrotnie też: **to, co nie jest dla człowieka, nie ma prawa być w logu.**

| nie loguj | bo to jest | idzie przez |
|---|---|---|
| wartości pomiarowych (`-59.2 hPa`) | dane | topic, tu `/vacuum_pressure` |
| „mam 50 Hz i wszystko gra" | stan zdrowia | `/diagnostics` |
| „chwyt się udał" | zdarzenie do dalszego przetwarzania | wiadomość, tu `/grasp_verdict` |

W logu zostaje to, czego żaden z tych kanałów nie uniesie: konfiguracja przy
starcie, decyzje jednorazowe, kontekst awarii. Test na komunikat startowy:
**czy odpowiada na pytanie, które zadam sobie za tydzień, oglądając bag?**
Wersja, wartości parametrów, nazwy topików, profil QoS — tak. „Node started" —
nie.

### `/rosout` jest topikiem, nie plikiem

`ros2 topic echo /rosout` to zdalny `tail -f` **całego systemu naraz**,
z każdego procesu, bez wchodzenia na maszynę i bez zgadywania, w którym
terminalu co się dzieje. Typ wiadomości to `rcl_interfaces/msg/Log`:

```bash
ros2 interface show rcl_interfaces/msg/Log
```

Pola, które ci się przydadzą: `stamp`, `level`, `name` (nazwa loggera —
domyślnie nazwa węzła), `msg`, oraz `file`, `function`, `line`. Poziomy to
`DEBUG=10`, `INFO=20`, `WARN=30`, `ERROR=40`, `FATAL=50` — te same liczby co
w `logging` Pythona, i to nie jest przypadek.

Trzy konsekwencje bycia topikiem:

1. **Da się to nagrać razem z danymi.** `ros2 bag record /vacuum_pressure
   /grasp_verdict /rosout /diagnostics` daje jeden plik, w którym masz
   pomiar i zdanie, które węzeł o nim napisał, z zachowaną kolejnością.
2. **Podlega QoS.** `/rosout` nie jedzie na domyślnym profilu — rcl używa
   dla niego osobnego, z głęboką historią i trwałością, żeby subskrybent,
   który podłączy się sekundę później, zobaczył jeszcze ostatnie komunikaty.
   Zobacz sam: `ros2 topic info /rosout --verbose` i porównaj z tym, co ten
   sam wydruk pokazuje dla `/vacuum_pressure`. Dlaczego te profile w ogóle
   muszą do siebie pasować — [etap 05](./05-introspekcja-qos-narzedzia.md).
3. **Kosztuje.** Każde wywołanie loggera to publikacja DDS z nagłówkiem
   (nazwa, plik, funkcja, linia, stempel). Log o pomiarze jest **większy niż
   sam pomiar** — 4 bajty `Float32` kontra kilkaset bajtów zdania o nim.

Poza topikiem ten sam komunikat leci jeszcze na stderr i do pliku.
**Trzy miejsca na jedno wywołanie.** Stąd arytmetyka: `info()` w callbacku
timera 50 Hz to 150 zapisów na sekundę, 4,3 miliona na osiem godzin zmiany.
To nie jest „dużo logów", to jest atak DoS na samego siebie — i widać to
w jitterze pętli, czyli w tym, co akurat mierzysz.

### Logowanie w rclpy — to, co naprawdę warto znać

```python
self.get_logger().debug('szczegół dla ciebie, domyślnie niewidoczny')
self.get_logger().info('fakt o konfiguracji')
self.get_logger().warn('coś jest nie tak, ale jadę dalej')
self.get_logger().error('nie wykonałem tego, co miałem')
self.get_logger().fatal('kończę')
```

Domyślny próg to `INFO`, więc `debug()` nigdzie nie trafia, dopóki nie
podniesiesz poziomu. Z linii poleceń:

```bash
# wszystko, łącznie z wnętrznościami rcl/rmw — zaleje ci ekran
scripts/dev/ros2/run-node.sh grip_monitor vacuum_sensor --ros-args --log-level DEBUG

# tylko ten jeden logger — prawie zawsze o to ci chodzi
scripts/dev/ros2/run-node.sh grip_monitor vacuum_sensor \
  --ros-args --log-level vacuum_sensor:=DEBUG
```

Loggery podrzędne dzielą jeden węzeł na kanały, które da się włączać osobno:

```python
self._log_diag = self.get_logger().get_child('diag')   # nazwa: vacuum_sensor.diag
```

Zysk jest podwójny: `--log-level vacuum_sensor.diag:=DEBUG` włącza tylko ten
strumień, a w nagranym `/rosout` pole `name` pozwala odfiltrować go offline,
miesiąc później, bez uruchamiania czegokolwiek.

**Dławienie.** Trzy modyfikatory, wszystkie jako argumenty nazwane:

| modyfikator | znaczenie | kiedy |
|---|---|---|
| `throttle_duration_sec=2.0` | najwyżej raz na 2 s z tego miejsca w kodzie | warunek utrzymujący się w pętli 50 Hz |
| `once=True` | raz na proces, z tego miejsca | „wykryłem konfigurację X" |
| `skip_first=True` | pomiń pierwsze wystąpienie | w parze z throttle: nie krzycz o czymś, co samo minie po jednej próbce |

```python
self.get_logger().warn(
    f'okno niepełne: {len(self.frame)}/{self.frame.maxlen}',
    throttle_duration_sec=2.0,
    skip_first=True,
)
```

Stan dławienia jest trzymany **per miejsce wywołania** (plik, funkcja,
linia). Dwie różne linie dławią się niezależnie. Jedna linia w pętli — razem.
Wspólna metoda `self._warn(...)` wołana z pięciu miejsc — wszystkie pięć
w jednym kubełku, i to jest ta pułapka, którą zobaczysz dopiero wtedy, gdy
zabraknie ci ostrzeżenia w logu z awarii.

**Format i kolory** ustawia się zmiennymi środowiskowymi, nie kodem:

```bash
export RCUTILS_CONSOLE_OUTPUT_FORMAT='[{severity}] [{time}] [{name}]: {message}'
export RCUTILS_COLORIZED_OUTPUT=1     # 1 wymusza, 0 wyłącza
export RCUTILS_LOGGING_USE_STDOUT=1   # logi na stdout zamiast stderr
```

W tym repo jest tu haczyk: `run-node.sh` z Fedory wchodzi przez
`podman exec` **bez przekazywania środowiska**, więc twój `export` na
Fedorze nie dojedzie. Zmienne ustawiasz w terminalu VS Code (już jesteś
w kontenerze) albo wprost w poleceniu.

**Pliki.** Ten sam komunikat ląduje w katalogu `$ROS_LOG_DIR`, domyślnie
`~/.ros/log/`, w pliku na **proces** (nazwa zawiera nazwę, PID i stempel
czasu). Rotacji nie ma żadnej — katalog rośnie w nieskończoność i sprząta
się go samemu (`find ~/.ros/log -mtime +7 -delete`). W tym kontenerze dochodzi
druga rzecz: `remoteUser` to `ubuntu`, czyli `$HOME` to `/home/ubuntu`,
a zamontowane jest wyłącznie repo pod `/home/maniumek/repos/robotics`.
**Twoje logi leżą w warstwie zapisywalnej kontenera i giną przy jego
odtworzeniu.** Jeśli mają przeżyć, ustaw `ROS_LOG_DIR` na ścieżkę wewnątrz
repo i dopisz ją do `.gitignore`.

### Diagnostyka: `diagnostic_updater`

Model jest prosty i to jest jego zaleta. `Updater` trzyma listę **zadań**;
raz na sekundę woła każde z nich, zbiera wyniki i publikuje jedną
`diagnostic_msgs/DiagnosticArray` na `/diagnostics`. Zadanie to funkcja,
która dostaje `DiagnosticStatusWrapper` i ma go wypełnić:

```python
import diagnostic_updater
from diagnostic_msgs.msg import DiagnosticStatus

self._diag = diagnostic_updater.Updater(self)     # MUSI żyć w self
self._diag.setHardwareID('cela-1')
self._diag.add('czestotliwosc publikacji', self._diag_rate)


def _diag_rate(self, stat):
    stat.add('hz', f'{hz:.1f}')            # pary klucz-wartość, wszystko stringi
    stat.add('oczekiwane_hz', '50.0')
    stat.summary(DiagnosticStatus.WARN, f'za wolno: {hz:.1f} Hz')
    return stat                            # zwrot jest obowiązkowy
```

Cztery poziomy: `OK=0`, `WARN=1`, `ERROR=2`, `STALE=3`. Pary klucz-wartość
są tym, co odróżnia diagnostykę od logu — to **struktura**, którą coś innego
przeczyta i wyświetli, a nie zdanie do przeczytania oczami.

Pakiet ma też gotowe klasy do pilnowania częstotliwości i wieku stempla —
`FrequencyStatus` / `FrequencyStatusParam`, `TimeStampStatus` /
`TimeStampStatusParam`, `HeaderlessTopicDiagnostic`, `TopicDiagnostic`,
`DiagnosedPublisher`. Sygnatury konstruktorów sprawdź w źródle zamiast
zgadywać — to jest mało kodu i warto go przeczytać:

```bash
python3 -c "import diagnostic_updater, os; print(os.path.dirname(diagnostic_updater.__file__))"
```

Napisz najpierw własne liczenie Hz (Zadanie 06.2), potem podmień na gotowe.
Odwrotna kolejność uczy klikania.

### Dlaczego sam `Updater` nie wystarczy: `diagnostic_aggregator`

`/diagnostics` to **płaska lista** wszystkiego, co żyje. Na prawdziwej celi
ma dwieście pozycji z piętnastu procesów, a ty potrzebujesz jednego
światełka „cela: OK". Do tego służy druga warstwa: `aggregator_node`
z pakietu `diagnostic_aggregator` czyta `/diagnostics`, dopasowuje pozycje
regułami z YAML-a, buduje z nich **drzewo** i publikuje je na
`/diagnostics_agg`, a sam korzeń osobno na `/diagnostics_toplevel_state`.

Ale prawdziwy powód, dla którego ta warstwa istnieje, jest inny:
**agregator jako jedyny wie, czego się spodziewać.** Trzyma pozycje, które
kiedyś widział, i gdy któraś przestanie przychodzić, po `timeout` sekund
oznacza ją jako `STALE` — zamiast po cichu usunąć z listy. To jest jedyne
miejsce w całym łańcuchu, w którym cisza zamienia się w sygnał.

### `STALE` — najważniejszy poziom i najczęściej pominięty

`ERROR` znaczy „czujnik mówi, że jest źle". `STALE` znaczy „czujnik przestał
mówić". To są dwie zupełnie różne awarie i dwie różne reakcje:

| poziom | co wiesz | co robisz |
|---|---|---|
| `OK` | mierzy i jest dobrze | nic |
| `WARN` | mierzy, wartość poza normą | notujesz, może zwalniasz |
| `ERROR` | mierzy i jest źle | zatrzymujesz operację |
| `STALE` | **nie wiesz nic** | zatrzymujesz operację i szukasz, gdzie urwało |

`STALE` jest pomijany, bo żeby go wystawić, trzeba mierzyć **czas od
ostatniego zdarzenia**, a to wymaga uznania, że brak zdarzenia jest
informacją. W tym repo masz to jak na tacy: dziś zabicie `vacuum_sensor`
daje ciszę na `/grasp_verdict` i zdrowo wyglądający system. Po tym etapie —
`STALE` w ciągu sekundy, z dwóch niezależnych powodów naraz: `grasp_monitor`
sam zgłosi „nie dostaję danych", a agregator zauważy, że pozycje
`vacuum_sensor` w ogóle zniknęły.

### Fail loud, not silent

Wróćmy do `RuntimeError` w callbacku timera. Co się dzieje naprawdę:

| executor | zachowanie | co widzi obserwator |
|---|---|---|
| `SingleThreadedExecutor` (czyli `rclpy.spin()`) | wyjątek leci w górę, `spin()` się kończy, traceback na stderr, proces pada | topic znika; `/rosout` **nie ma nic**, bo traceback Pythona nie przechodzi przez logger ROS-a; `node.destroy_node()` i `shutdown()` po `spin()` nigdy się nie wykonają |
| `MultiThreadedExecutor` | wyjątek ląduje w future zadania, którego nikt nie sprawdza | węzeł żyje, publikacja przepada, timer tyka dalej — **cisza bez śladu** |

Obie opcje są złe, a druga jest gorsza. Prawidłowe zachowanie węzła, który
wykrył, że nie umie policzyć tego, co miał policzyć:

1. **Nie publikuj śmieci.** Lepiej nic niż wartość, której nie umiesz obronić.
2. **Powiedz to diagnostyką**, poziomem `ERROR`, z parą klucz-wartość mówiącą,
   co dokładnie jest złe (`state=bzdura`).
3. **Powiedz to raz logiem**, na poziomie `fatal`/`error`, dla człowieka,
   który przyjdzie później.
4. **Przejdź w stan błędu**, czyli u nas: zdezaktywuj się, zamiast umrzeć.
   Martwy proces nie ma jak powiedzieć, dlaczego umarł.

I jeszcze wcześniej: **odrzuć złą wartość na granicy**.
`add_on_set_parameters_callback` pozwala zwrócić
`SetParametersResult(successful=False, reason=...)`, a wtedy `ros2 param set`
mówi „failed" i **nic się nie zmienia**. Awaria zostaje przypisana do
akcji, która ją wywołała — to jest cała treść „fail loud".

### Węzły cyklu życia (managed nodes)

Zwykły węzeł ma jeden stan: „proces chodzi". Węzeł zarządzany ma maszynę
stanów, sterowaną **z zewnątrz** przez usługi:

```
   unconfigured --configure--> inactive --activate--> active
        ^                          |  ^                  |
        |                          |  +----deactivate----+
        +---------cleanup----------+
   (z każdego stanu) --shutdown--> finalized
```

- **unconfigured** — proces żyje, nic nie zrobił. Parametry nie wczytane,
  publisherów nie ma.
- **inactive** — wszystko zbudowane, nic nie leci. To jest stan „gotowy".
- **active** — pracuje.
- **finalized** — koniec, zostaje tylko sprzątnąć proces.

W `rclpy`: `LifecycleNode`, metody `on_configure`, `on_activate`,
`on_deactivate`, `on_cleanup`, `on_shutdown`, każda zwraca
`TransitionCallbackReturn.SUCCESS` albo `FAILURE`. Publisher tworzysz przez
`create_lifecycle_publisher()` — i on **nie wypuszcza wiadomości, dopóki
węzeł nie jest aktywny**, bez żadnego `if` w twoim kodzie.

Z CLI:

```bash
ros2 lifecycle nodes                          # kto w ogóle jest zarządzany
ros2 lifecycle list /grasp_monitor            # jakie przejścia są teraz możliwe
ros2 lifecycle get /grasp_monitor             # aktualny stan
ros2 lifecycle set /grasp_monitor configure
ros2 lifecycle set /grasp_monitor activate
ros2 topic echo /grasp_monitor/transition_event   # historia zmian stanu
```

**Po co to z twojej perspektywy.** To jest jedyny standardowy sposób, żeby
„gotowość" węzła była **faktem obserwowalnym z zewnątrz**, a nie domysłem.
Bez tego jedyne, co masz, to „proces istnieje" — a proces istnieje również
wtedy, gdy wisi na wczytywaniu kalibracji albo czeka na urządzenie, którego
nie ma.

Analogia do sondy readiness działa i jest dobra. **Pęka w dwóch miejscach.**
Po pierwsze: readiness to pytanie („czy jesteś gotów?"), a tu jest rozkaz
(„masz być aktywny") — stanem steruje ktoś z zewnątrz i może cię wyłączyć
**w środku pracy**, także wtedy, gdy przedmiot wisi już na przyssawce.
Po drugie: nie ma load balancera, który przestanie ci wysyłać ruch.
Subskrypcja utworzona w `on_configure` **dostaje wiadomości również
w stanie inactive** i twój callback się wykona. Lifecycle zarządza
wyjściem, nie wejściem — bramkowanie wejścia jest twoje.

**Uporządkowany start.** Test integracyjny, który startuje procesy
i czeka `sleep(2)`, jest flaky z definicji; lifecycle daje mu warunek
zamiast czekania — po szczegóły idź do
[etapu 04](./04-piramida-testow.md). **Uporządkowane zamknięcie.**
`deactivate` to jedyny standardowy sposób powiedzenia „przestań działać,
ale nie umieraj": proces zostaje, trzyma parametry, dalej publikuje
diagnostykę i dalej wiesz, że istnieje. `kill` daje ciszę, a ciszy nie da
się odróżnić od awarii. Dla porządku: to jest porządek w warstwie software'u,
**nie** jest to zatrzymanie awaryjne w rozumieniu bezpieczeństwa — prawdziwy
e-stop celi jest sprzętowy i nie przechodzi przez ROS-a.

## Zadania

### Zadanie 06.1 — Pakiety, poziomy i dławienie (rdzeń)

**Cel:** logi w obu węzłach mówią coś użytecznego i nie zapychają szyny.

Dopisz do `.devcontainer/Containerfile`, w miejscu przewidzianym na pakiety:

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
      ros-jazzy-diagnostic-updater \
      ros-jazzy-diagnostic-aggregator \
 && rm -rf /var/lib/apt/lists/*
```

Potem **Rebuild Container** w VS Code. Do `ws/src/grip_monitor/package.xml`
dopisz `<depend>diagnostic_updater</depend>`, `<depend>diagnostic_msgs</depend>`
i `<depend>lifecycle_msgs</depend>`.

W `vacuum_sensor.py` dołóż komunikat startowy, który za tydzień odpowie na
twoje pytania z baga:

```python
self.get_logger().info(
    f'start: state={self.get_parameter("state").value}, '
    f'{1 / self._period:.0f} Hz, topic={self.pub.topic_name}, qos=BEST_EFFORT/depth=10'
)
```

W `_tick()` **nie loguj pomiaru na `info`** — to są dane. Jeśli chcesz go
widzieć przy debugowaniu, to `debug()` z `throttle_duration_sec=1.0`.
W `grasp_monitor.py` zrób komunikat startowy z rozmiarem okna i progami,
a ostrzeżenie o niepełnym oknie zadław jak w przykładzie z modelu pojęciowego.

Porównaj oba światy z Fedory: `ros2 topic echo /rosout` przed zmianą
i po niej (przez `scripts/dev/ros2/print-topic-messages.sh /rosout`).

**Gotowe, gdy:** `print-topic-messages.sh /rosout` pokazuje przy starcie
dwa czytelne komunikaty konfiguracyjne i **nic więcej** przez następną
minutę, mimo że `/vacuum_pressure` leci 50 Hz.

### Zadanie 06.2 — Diagnostyka częstotliwości w `vacuum_sensor` (rdzeń)

**Cel:** węzeł sam mierzy, czy dowozi obiecane 50 Hz, i mówi to maszynie.

```python
self._ticks = 0
self._window_start = self.get_clock().now()
self._diag = diagnostic_updater.Updater(self)
self._diag.setHardwareID('cela-1')
self._diag.add('vacuum_pressure: czestotliwosc', self._diag_rate)
```

W `_tick()` zwiększ `self._ticks`. W `_diag_rate` policz Hz z okna, wyzeruj
licznik, wystaw `hz`, `oczekiwane_hz` i `state` jako pary klucz-wartość,
a poziom ustaw na `WARN`, gdy odchyłka przekracza 10%.

Potem podmień własne liczenie na gotowe `FrequencyStatus` z pakietu —
sygnatury konstruktorów odczytaj ze źródeł (ścieżka jak w modelu pojęciowym).

**Gotowe, gdy:** `print-topic-messages.sh /diagnostics` pokazuje raz na
sekundę pozycję z poziomem `0` i wartością `hz` około 50, a po uruchomieniu
węzła z `--ros-args -p` wymuszającym wolniejszy timer poziom zmienia się
na `1` bez dotykania kodu.

### Zadanie 06.3 — „Czy ja w ogóle dostaję dane" (rdzeń)

**Cel:** `grasp_monitor` odróżnia „nie ma chwytu" od „nie mam danych".

Zapamiętuj czas ostatniej próbki (`self._last_rx = self.get_clock().now()`
w `on_measurement`) i dodaj zadanie diagnostyczne:

```python
def _diag_input(self, stat):
    if self._last_rx is None:
        stat.summary(DiagnosticStatus.STALE, 'nie przyszla ani jedna probka')
        return stat
    age = (self.get_clock().now() - self._last_rx).nanoseconds / 1e9
    stat.add('wiek_ostatniej_probki_s', f'{age:.2f}')
    stat.add('probek_w_oknie', f'{len(self.frame)}/{self.frame.maxlen}')
    if age > 1.0:
        stat.summary(DiagnosticStatus.STALE, f'brak danych od {age:.1f} s')
    elif len(self.frame) < self.frame.maxlen:
        stat.summary(DiagnosticStatus.WARN, 'okno jeszcze sie nie zapelnilo')
    else:
        stat.summary(DiagnosticStatus.OK, f'wiek {age:.2f} s')
    return stat
```

**Gotowe, gdy:** przy zabitym `vacuum_sensor` pozycja `grasp_monitor`
na `/diagnostics` pokazuje poziom `3` i rosnący `wiek_ostatniej_probki_s`,
a `grasp_monitor` nadal żyje.

### Zadanie 06.4 — Agregator: z płaskiej listy zrób drzewo (rdzeń)

**Cel:** jedno światełko na całą celę, które gaśnie także wtedy, gdy węzeł
przestał istnieć.

Najpierw odczytaj **dokładne** nazwy pozycji — agregator dopasowuje po
stringu, więc przepisujesz je co do znaku:

```bash
scripts/dev/ros2/print-topic-messages.sh /diagnostics --once
```

`ws/src/grip_monitor/config/analyzers.yaml`:

```yaml
analyzers:
  ros__parameters:
    path: Cela
    czujnik:
      type: diagnostic_aggregator/GenericAnalyzer
      path: Czujnik
      timeout: 2.0
      startswith: ['vacuum_pressure']
    detektor:
      type: diagnostic_aggregator/GenericAnalyzer
      path: Detektor
      timeout: 2.0
      contains: ['grasp']
```

Uruchom:

```bash
scripts/dev/ros2/run-node.sh diagnostic_aggregator aggregator_node \
  --ros-args --params-file ws/src/grip_monitor/config/analyzers.yaml
```

Klucz najwyższego poziomu musi być nazwą węzła agregatora — sprawdź
`scripts/dev/ros2/list-running-nodes.sh`; gdy parametry nie wchodzą, użyj
uniwersalnego `/**:` zamiast `analyzers:`.

**Gotowe, gdy:** `print-topic-messages.sh /diagnostics_toplevel_state`
pokazuje jedną pozycję z poziomem `0`, a pozycje z `/diagnostics` mają
w `/diagnostics_agg` nazwy w drzewie (`/Cela/Czujnik/...`) i żadna nie
wylądowała w gałęzi `Other`.

### Zadanie 06.5 — `grasp_monitor` jako węzeł cyklu życia (rdzeń)

**Cel:** gotowość detektora staje się stanem, o który da się zapytać.

```python
from rclpy.lifecycle import LifecycleNode, State, TransitionCallbackReturn


class GraspMonitor(LifecycleNode):
    def __init__(self):
        super().__init__('grasp_monitor')
        self._active = False
        self.frame = deque(maxlen=25)

    def on_configure(self, state: State) -> TransitionCallbackReturn:
        qos = QoSProfile(depth=10, reliability=ReliabilityPolicy.BEST_EFFORT)
        self.pub = self.create_lifecycle_publisher(String, 'grasp_verdict', 10)
        self.sub = self.create_subscription(Float32, 'vacuum_pressure', self.on_measurement, qos)
        return TransitionCallbackReturn.SUCCESS

    def on_activate(self, state: State) -> TransitionCallbackReturn:
        self.frame.clear()
        self._active = True
        return super().on_activate(state)      # BEZ tego publisher zostanie niemy

    def on_deactivate(self, state: State) -> TransitionCallbackReturn:
        self._active = False
        return super().on_deactivate(state)
```

Na początku `on_measurement` dodaj `if not self._active: return` i zobacz,
dlaczego to jest potrzebne, usuwając tę linię na chwilę. W zadaniu
diagnostycznym rozróżnij „nieaktywny" (to `OK`, tak miało być)
od „aktywny i głodny" (`STALE`).

**Gotowe, gdy:** po starcie `ros2 lifecycle get /grasp_monitor` mówi
`unconfigured`, `/grasp_verdict` nie istnieje, a po `configure` + `activate`
werdykty lecą; `deactivate` je zatrzymuje bez zabijania procesu,
a `/grasp_monitor/transition_event` pokazuje każde z tych przejść.

### Zadanie 06.6 — Zepsuj to (rdzeń, obowiązkowe)

**Cel:** zobaczyć na własne oczy różnicę między systemem, który milczy,
a systemem, który krzyczy.

**Wariant A — zabij czujnik, porównaj dwa światy.** Najpierw świat sprzed
zmian: `git stash`, zbuduj, uruchom oba węzły, podglądaj `/grasp_verdict`
i zabij `vacuum_sensor` Ctrl+C. Zapisz, ile czasu minęło, zanim
**cokolwiek** powiedziało ci, że jest źle. Potem `git stash pop`, zbuduj,
uruchom oba węzły plus agregator i powtórz dokładnie to samo.

**Wariant B — bzdurny parametr.** Przy działającym czujniku:

```bash
scripts/dev/ros2/set-param.sh /vacuum_sensor state bzdura
```

Zanotuj, co odpowiedział skrypt, co stało się z procesem, czy w `/rosout`
jest jakikolwiek ślad i czy `/diagnostics` zdążyło cokolwiek powiedzieć.
Potem napraw to według „fail loud": walidacja w
`add_on_set_parameters_callback`, a w samym `_tick()` — zamiast `raise` —
przejście w stan błędu (`ERROR` w diagnostyce, jeden `fatal()` i brak
publikacji).

**Gotowe, gdy:** w wariancie A świat „przed" daje ciszę i zdrowo wyglądający
system, a świat „po" pokazuje `STALE` na `/diagnostics_agg` w ciągu sekundy;
w wariancie B `set-param.sh` kończy się **niepowodzeniem**, węzeł żyje dalej
i publikuje poprzedni stan, a nie śmieci.

### Zadanie 06.7 — Jedna oś czasu (rozszerzenie)

**Cel:** mieć nagranie, w którym widać i pomiary, i to, co węzły o nich
myślały.

```bash
ros2 bag record -s mcap -o projects/grab-fail-detection/bags/awaria-czujnika \
  /vacuum_pressure /grasp_verdict /rosout /diagnostics /diagnostics_agg
```

W trakcie nagrywania odegraj wariant A z poprzedniego zadania. Potem
przeczytaj bag offline i wypisz wszystko posortowane po czasie zapisu —
mechanika czytania bagów jest w [etapie 03](./03-bagi-jako-dane.md):

```python
reader = rosbag2_py.SequentialReader()
reader.open(
    rosbag2_py.StorageOptions(uri=BAG, storage_id='mcap'),
    rosbag2_py.ConverterOptions('cdr', 'cdr'),
)
types = {t.name: t.type for t in reader.get_all_topics_and_types()}
while reader.has_next():
    topic, data, t_ns = reader.read_next()
    msg = deserialize_message(data, get_message(types[topic]))
    print(f'{t_ns / 1e9:.3f}  {topic:24s}  {msg}')
```

**Gotowe, gdy:** w jednym wydruku widzisz kolejno: ostatni pomiar, ciszę
na `/vacuum_pressure`, a kilkaset milisekund później wpis z `/diagnostics`
z poziomem `3` — i umiesz podać z tego wydruku, ile dokładnie trwało
wykrycie awarii.

## Pułapki

| objaw | przyczyna | co zrobić |
|---|---|---|
| `--log-level DEBUG` zalewa ekran komunikatami z rcl/rmw | to jest poziom **globalny**, dotyczy wszystkich loggerów w procesie | użyj postaci z nazwą: `--log-level vacuum_sensor:=DEBUG` |
| `throttle_duration_sec` dławi za mocno — brakuje ostrzeżeń, których się spodziewasz | stan dławienia jest per miejsce wywołania, a ty logujesz przez wspólną metodę pomocniczą | loguj z osobnych linii albo daj każdemu warunkowi własne wywołanie |
| `RuntimeError` zabił węzeł, ale w `/rosout` i w bagu nie ma po tym śladu | traceback Pythona idzie na stderr procesu, nie przez logger ROS-a | łap wyjątek i zgłoś go `self.get_logger().fatal()` plus `ERROR` w diagnostyce |
| `/diagnostics` istnieje, ale jest puste | `Updater` trzymany w zmiennej lokalnej (GC go sprząta) albo nie ma dodanego żadnego zadania | przypisz do `self.`, dodaj co najmniej jedno `add()` |
| pozycja nie trafia do twojej gałęzi, ląduje w `Other` | `GenericAnalyzer` dopasowuje po dokładnym stringu nazwy | odczytaj nazwę z `/diagnostics --once` i przepisz co do znaku |
| węzeł umarł, a `/diagnostics_agg` wciąż pokazuje `OK` | za długi `timeout` analizatora albo `discard_stale: true`, które usuwa pozycje zamiast oznaczać | ustaw `timeout` rzędu 2 s i zostaw `discard_stale` domyślne |
| `ros2 lifecycle list /grasp_monitor` mówi, że nie ma takiego węzła | to nadal zwykły `Node` — nie ma usług `change_state`/`get_state` | sprawdź `ros2 lifecycle nodes`; dziedzicz po `LifecycleNode` |
| po `activate` publisher nadal milczy | nadpisany `on_activate` bez `super().on_activate(state)` | dopisz `return super().on_activate(state)` |
| węzeł „nieaktywny", a mimo to liczy i zapełnia okno | lifecycle zarządza publisherem, nie subskrypcją | bramkuj callback własną flagą ustawianą w `on_activate`/`on_deactivate` |
| `export RCUTILS_CONSOLE_OUTPUT_FORMAT` na Fedorze nie działa | `run-node.sh` wchodzi przez `podman exec` bez przekazywania środowiska | ustaw zmienną w terminalu VS Code albo wprost w treści polecenia |
| przekierowanie `> plik.txt` nie łapie ani jednej linii logu | logi idą domyślnie na **stderr** | `2>&1` albo `RCUTILS_LOGGING_USE_STDOUT=1` |
| logi z `~/.ros/log/` zniknęły po odtworzeniu kontenera | `$HOME` w kontenerze to `/home/ubuntu`, a zamontowane jest tylko repo | ustaw `ROS_LOG_DIR` na ścieżkę w repo i dopisz ją do `.gitignore` |

## Sprawdź się

1. Dlaczego `Updater` wewnątrz `vacuum_sensor` nigdy nie zgłosi awarii
   polegającej na śmierci `vacuum_sensor` — i kto może ją zgłosić?
2. Czym różni się `ERROR` od `STALE` i dlaczego reakcja na te dwa poziomy
   jest inna?
3. Masz komunikat „ciśnienie spadło do -59 hPa". Czy to log, dane, czy
   diagnostyka? A „przechodzę w tryb awaryjny, bo parametr `state` ma
   nieznaną wartość"?
4. Dlaczego `info()` w callbacku timera 50 Hz jest droższe, niż wygląda —
   wymień trzy miejsca, w które trafia jedno takie wywołanie.
5. Dlaczego zachowanie `RuntimeError` z `_get_state_value()` zależy od
   tego, którego executora użyjesz, i który z dwóch wariantów jest gorszy
   dla kogoś, kto to potem diagnozuje?
6. Węzeł cyklu życia jest w stanie `inactive`. Czy jego subskrypcja
   odbiera wiadomości? Czy jego publisher cyklu życia je wypuszcza?
7. Co daje `deactivate`, czego nie daje `kill -TERM` na tym samym procesie?
8. Dlaczego nagranie zawierające `/rosout` obok `/vacuum_pressure` jest
   warte więcej niż te same dwa strumienie w dwóch osobnych plikach?

## Co przeczytać

- `https://docs.ros.org/en/jazzy/` — sekcje o logowaniu i o argumentach
  `--ros-args`; po to, żeby mieć pełną listę flag i zmiennych
  `RCUTILS_*`, których tutaj świadomie nie wypisałem w całości.
- `https://design.ros2.org/` — artykuł o węzłach zarządzanych; po to, żeby
  zobaczyć, dlaczego maszyna stanów ma dokładnie te stany i kto według
  autorów miał nią sterować.
- `https://github.com/ros/diagnostics` — źródła `diagnostic_updater`
  i `diagnostic_aggregator`; po to, żeby przeczytać sygnatury klas
  częstotliwościowych zamiast zgadywać i przekonać się, jak mało tam kodu.
- `https://github.com/ros2/rclpy` — katalog `rclpy/lifecycle/`; po to, żeby
  zobaczyć, co naprawdę robi `on_activate` i dlaczego brak `super()` kosztuje
  wieczór.
- `ros2 interface show diagnostic_msgs/msg/DiagnosticStatus` — dwie minuty,
  po to, żeby zobaczyć, że cała diagnostyka to cztery pola i lista par
  klucz-wartość, a reszta jest konwencją.
- `https://www.ros.org/reps/` — REP-2004 (kategorie jakości pakietów); po to,
  żeby umieć zapytać, czy pakiet, na którym opierasz monitoring, ma
  deklarowany poziom jakości.

## Dziennik

    Co mnie zaskoczyło:

    Ile czasu minęło w wariancie A (przed) od zabicia czujnika do momentu,
    w którym cokolwiek mi o tym powiedziało — i ile po zmianach:

    Co zjadło najwięcej czasu (nazwy w YAML-u? super() w on_activate?
    coś zupełnie innego?):

    Które z moich dotychczasowych logów w tym repo okazały się danymi
    albo diagnostyką w przebraniu:

    Zdanie, którego tydzień temu nie umiałbym napisać:

Dalej → [Etap 07 — Gazebo jako stanowisko testowe](./07-gazebo-stanowisko.md)
