# Etap 04 — Piramida testów w ROS 2

> Sprawdzasz logikę detektora w milisekundach bez uruchamiania ROS-a, osobno
> dowodzisz, że dwa prawdziwe procesy się widzą — i wiesz z góry, który test
> zapali się przy którym rodzaju awarii.

| | |
|---|---|
| wejście | etapy 01–03; `ws/` się buduje, `projects/grab-fail-detection/bags/chwyt-3-stany/` leży na dysku |
| czas | 2–3 wieczory (trzeci zwykle idzie na `launch_testing`) |
| kończy się | `colcon test --packages-select grip_monitor` uruchamia trzy poziomy testów, a ty umiesz przewidzieć, który z nich zapalisz, psując konkretną rzecz |

Jeśli zrobiłeś etap 01, twój werdykt jest własnym typem, nie `std_msgs/String` —
podmień typ i pole w przykładach. Nic poza tym się nie zmienia.

## Po ludzku: co to jest w twoim świecie

| pojęcie | odpowiednik z backendu | gdzie analogia pęka |
|---|---|---|
| `colcon test` | `pytest` / `mvn test` w monorepo | **nie zwraca błędu, gdy testy padły** — zielony wydruk nie znaczy zielone testy |
| `rclpy.Context` | kontener DI aplikacji | jest jeden, globalny i domyślny; dwa testy w jednym procesie wchodzą sobie w drogę, dopóki go nie rozdzielisz ręcznie |
| executor | pętla zdarzeń (`asyncio`) | nie kręci się sam w tle; bez `spin_once` twój węzeł jest martwy, a test wisi do timeoutu |
| `ROS_DOMAIN_ID` | osobna baza na testy | to nie izolacja procesu, tylko filtr rozgłoszeń — węzeł sąsiada z tą samą liczbą jest w twoim teście |
| `ament_flake8`, `ament_pep257` | linter w pre-commicie | to są **testy**: padają w `colcon test` i w raporcie wyglądają identycznie jak regresja logiki |
| `launch_testing` | docker-compose + testcontainers | nie ma healthchecka z definicji; „gotowe do testu" deklarujesz sam (`ReadyToTest()`) |

## Po co to — czego bez tego nie da się zrobić

Otwórz `ws/src/grip_monitor/grip_monitor/grasp_monitor.py`. Cała detekcja siedzi
w `on_measurement` — w callbacku metody klasy dziedziczącej po `Node`. Żeby wywołać
tę funkcję, potrzebujesz obiektu `GraspMonitor`, do tego zainicjalizowanego
kontekstu rclpy, do tego działającego ROS-a. Dlatego tej logiki **nikt nigdy nie
sprawdził**, ciebie włącznie.

To nie jest lenistwo, tylko własność projektu. Testowalność nie jest techniką
dokładaną na końcu; jest konsekwencją tego, gdzie postawiłeś granicę między „co ten
kod liczy" a „skąd bierze dane".

Zobacz cenę. Wypisz dzisiejsze progi jako przedziały:

| wyrażenie w `grasp_monitor.py` | pasmo średniej | werdykt |
|---|---|---|
| `is_at_level(mean, 0)` | `(-1, 1)` | `open` |
| `mean < -1 and mean > -58` | `(-58, -1)` | `leak` |
| `is_at_level(mean, -59)` | `(-60, -58)` | `sealed` |
| — | `mean ≥ 1`, `mean ≤ -60`, `mean == -1`, `mean == -58` | **cisza** |

Cztery dziury, w których detektor nie mówi nic — nie „nie wiem", tylko nic.
Przyssawka odklejona od czujnika da wartości dodatnie i monitor zamilknie, a
`list-topics.sh` dalej pokaże, że topik istnieje. Żaden dotychczasowy sposób
patrzenia tego nie widzi. Test jednostkowy widzi w pierwszej minucie.

Drugi koszt jest gorszy, bo już wystąpił i leży u ciebie na dysku. Policz, co robi
okno 25 próbek, gdy ciśnienie skacze z `0.0` na `-59.0`: średnia po `i` próbkach
nowego poziomu to `-59 * i / 25`, czyli `-2,36 * i`. Dla `i = 1` masz `-2,36` —
pasmo `leak`. Dla `i = 24` masz `-56,6` — nadal `leak`. Dopiero `i = 25` daje `-59`
i `sealed`. Każde szczelne złapanie przedmiotu produkuje **dokładnie 24 fałszywe
werdykty „nieszczelność", przez 0,48 sekundy.**

To nie jest hipoteza. Twoje nagranie z etapu 03 zawiera dokładnie taki ciąg
(350 × `empty`, **24 × `leak`**, 283 × `sealed`, 405 × `leak`), a dowiesz się o tym
dopiero w zadaniu 04.5, bo do dziś nikt tego nagrania nie przepuścił przez asercję.

## Dlaczego to ciekawe

**Piramida w robotyce jest stroma z powodów fizycznych, nie z mody.** W backendzie
test integracyjny jest wolniejszy, bo wstaje baza; tutaj — bo **odkrywanie węzłów
w DDS zajmuje realny czas** i nikt ci nie powie ile. Nie ma brokera, do którego się
rejestrujesz; są rozgłoszenia i uzgadnianie, a tej różnicy nie da się zoptymalizować.

**Za to poziom 3 łapie klasę błędów, której w backendzie nie ma.** Literówka
w nazwie topiku nie jest błędem — jest poprawnym programem nadającym w pustkę.
Niedopasowane QoS nie jest błędem — to dwa poprawne węzły, które się nie widzą
(mechanizm w [etapie 05](./05-introspekcja-qos-narzedzia.md)). Brakująca zależność
w `package.xml` nie jest błędem u ciebie, bo u ciebie pakiet jest zainstalowany.
W każdym z tych przypadków interpreter milczy, test jednostkowy jest zielony,
a system nie działa.

**I najładniejszy pomysł tego etapu:** gdy wyjmiesz detektor do czystej klasy,
nagranie z prawdziwego przebiegu staje się testem jednostkowym. Dane z fizycznego
świata, prędkość `pytest`, zero ROS-a, wynik deterministyczny. Nagranie przestaje
być pamiątką, a zaczyna być asercją.

## Dlaczego to trudne

Testy w ROS-ie są **domyślnie migotliwe** i nie dlatego, że ktoś je źle napisał.

1. Publikujesz zaraz po stworzeniu wydawcy, a odkrywanie węzłów trwa i nie ma
   górnego ograniczenia — pierwsze wiadomości idą do nikogo.
2. Kolejność startu procesów w `launch` jest nieokreślona.
3. `vacuum_pressure` jedzie z `BEST_EFFORT` i `volatile` — spóźniony subskrybent
   nie dostanie nic wstecz.
4. Pierwszy odruch — `time.sleep(2)` — działa u ciebie i pada w CI. Potem ktoś
   zmienia na `sleep(5)` i zestaw trwa dziesięć minut, nadal migocząc.

Do tego trzy fakty, które kosztują po wieczorze każdy: `colcon test` kończy się
**kodem 0, gdy testy padły**; domyślny kontekst rclpy jest globalny na proces;
`--network=host` w `devcontainer.json` wciąga do twojego testu węzeł zostawiony
w drugim terminalu. Mechanizm i lekarstwo na każdy — w „Modelu pojęciowym".

## Wycinek prawdziwej roboty

W piątek jest pokaz dla klienta, a w detektorze siedzi warunek
`mean < -1 and mean > -58`, o którym cały zespół wie, że jest zły. Nikt go nie
rusza od pół roku, bo jedynym testem jest zapuszczenie całej celi, położenie
przedmiotu w chwytaku i popatrzenie na wydruk — pół dnia i jedno okno na hali.
„Możemy przesunąć ten próg o jeden?" nie ma tu taniej odpowiedzi, więc odpowiedź
brzmi „nie teraz": zespół przestał rozwijać produkt i zaczął go tylko obsługiwać.

Twoja robota to wtedy zadania 04.1–04.5 na większym pliku. Najpierw szew: logika
wychodzi z callbacka do klasy bez `rclpy`, żeby próg sprawdzać w milisekundach,
nie w cyklu celi. Potem progi idą na papier jako przedziały, a każda dziura
w nich — w asercję, łącznie z przypadkami, których nikt nie umiał odtworzyć
ręcznie (odklejona przyssawka, nadciśnienie). Potem przez tę klasę przechodzi
nagranie ostatniej awarii, a na końcu jeden test pary procesów — żeby zmiana
nazwy topiku w konfiguracji nie przeszła cicho.

Zostaje po tobie zestaw zapalający się na konkretnej zmianie, złoty przebieg
w repo i wpis w `NOTES.md` z powodem każdej decyzji. Pytanie o próg ma odtąd
odpowiedź w sekundach, nie w piątek — a ty umiesz powiedzieć to, czego większość
kandydatów nie umie: który poziom piramidy złapie literówkę w nazwie topiku,
który przesunięty próg i czemu zamiana ich miejscami daje zestaw wolny i ślepy.

## Model pojęciowy

### Pierwszy ruch: szew

Zanim napiszesz jakikolwiek test, przesuń granicę. Logika detekcji nie potrzebuje
ROS-a — potrzebuje ciągu liczb. Niech to będzie klasa bez importu `rclpy`:

```python
# ws/src/grip_monitor/grip_monitor/detector.py
from collections import deque


class GraspDetector:
    """Orzeka o stanie chwytu na podstawie ciągu pomiarów podciśnienia."""

    def __init__(self, window=25, open_at=0.0, sealed_at=-59.0,
                 tolerance=1.0, confirm=1):
        self._frame = deque(maxlen=window)
        self._open_at, self._sealed_at = open_at, sealed_at
        self._tolerance, self._confirm = tolerance, confirm
        self.state = 'unknown'
        self._candidate, self._count = None, 0

    def update(self, measurement):
        """Dokłada próbkę. Zwraca NOWY stan, gdy się zmienił, inaczej None."""
        self._frame.append(measurement)
        if len(self._frame) < self._frame.maxlen:
            return None
        candidate = self._classify(sum(self._frame) / len(self._frame))
        self._count = self._count + 1 if candidate == self._candidate else 1
        self._candidate = candidate
        if candidate != self.state and self._count >= self._confirm:
            self.state = candidate
            return candidate
        return None

    def _classify(self, mean):
        if abs(mean - self._open_at) < self._tolerance:
            return 'open'
        if abs(mean - self._sealed_at) < self._tolerance:
            return 'sealed'
        if self._sealed_at < mean < self._open_at:
            return 'leak'
        return 'unknown'
```

Trzy decyzje projektowe, każda warta uzasadnienia:

- **`unknown` jest stanem.** Dziury z tabeli znikają nie dlatego, że poprawiłeś
  progi, tylko dlatego, że „poza zakresem" ma nazwę i da się na nią zareagować.
- **`update` zwraca zmianę, nie stan.** To jest wykrywanie zbocza z
  [etapu 02](./02-czas-zdarzenia-stan.md), przeniesione tam, gdzie da się je
  przetestować — i bez zakomentowanych linijek.
- **`confirm` to tłumienie drgań** (odpowiednik histerezy: trudniej wyjść ze stanu
  niż do niego wejść). Przy `confirm=1` masz dzisiejsze zachowanie; przy
  `confirm=window` widmowy `leak` znika kosztem drugiego pół sekundy opóźnienia.
  Który wariant jest lepszy, rozstrzygasz danymi w
  [etapie 10](./10-ewaluacja-na-danych.md), nie gustem.

Węzeł zostaje cienką skorupą — subskrypcja, klasa, publikacja:

```python
class GraspMonitor(Node):
    def __init__(self, **kwargs):
        super().__init__('grasp_monitor', **kwargs)
        self.declare_parameter('window', 25)
        self.declare_parameter('confirm', 1)
        self.detector = GraspDetector(
            window=self.get_parameter('window').value,
            confirm=self.get_parameter('confirm').value,
        )
        qos = QoSProfile(depth=10, reliability=ReliabilityPolicy.BEST_EFFORT)
        self.create_subscription(Float32, 'vacuum_pressure', self.on_measurement, qos)
        self.pub = self.create_publisher(String, 'grasp_verdict', 10)

    def on_measurement(self, msg: Float32):
        state = self.detector.update(msg.data)
        if state is not None:
            self.pub.publish(String(data='[state] ' + state))
```

`**kwargs` przekazane do `Node.__init__` decydują o testowalności całego węzła: bez
nich nie wstrzykniesz własnego kontekstu, a poziom 2 piramidy jest zamknięty.

### Trzy poziomy

| poziom | co łapie | czego NIE łapie | koszt |
|---|---|---|---|
| **1. czysta logika** (`pytest`) | progi i ich granice, histereza, okno, maszyna stanów, sekwencja na prawdziwych danych | wszystko, co jest ROS-em: nazwy topików, typy, QoS, parametry, wpisy w `setup.py` | milisekundy, bez builda; **tu ma być 90% asercji** |
| **2. węzeł** (`rclpy` w procesie testu) | czy węzeł subskrybuje to, co trzeba, publikuje właściwy typ, reaguje na parametry, czy callback jest podpięty | niezgodność między dwoma procesami, transport, `package.xml`, `entry_points`, sposób umierania węzła | ~sekunda na test, wymaga builda i `source` |
| **3. system** (`launch_testing_ros`) | czy dwa prawdziwe procesy się widzą: nazwy topików, niedopasowane QoS, brakujące zależności, zepsuty `entry_point`, kod wyjścia procesu | poprawność werdyktu — cokolwiek o treści danych; granice progów; regresje logiki | sekundy do dziesiątek sekund, kruche, uruchamiane rzadziej |

Reguła, która z tego wynika: **jeśli test poziomu 3 sprawdza wartość liczby,
napisałeś go na złym poziomie.** Poziom 3 odpowiada na jedno pytanie — „czy to
w ogóle jest połączone".

### `colcon test` w praktyce

Wszystko poniżej odpalasz z `ws/`, w kontenerze (`scripts/dev/enter-devcontainer.sh`).

```bash
colcon build --symlink-install --packages-select grip_monitor
source install/setup.bash
colcon test --packages-select grip_monitor
colcon test-result --verbose
```

**Drugie polecenie jest obowiązkowe.** `colcon test` kończy się kodem 0 nawet wtedy,
gdy połowa asercji padła — zwraca błąd dopiero, gdy nie udało mu się *uruchomić*
testów. Dopiero `colcon test-result --verbose` wypisuje, co padło i dlaczego.
W skrypcie i w CI używasz zamiast tego
`colcon test --packages-select grip_monitor --return-code-on-test-failure`.

| chcesz | polecenie |
|---|---|
| jeden plik / jeden test | `colcon test --packages-select grip_monitor --pytest-args -k detector -v` |
| wydruk testu na żywo | `colcon test --packages-select grip_monitor --event-handlers console_direct+` |
| pełny raport, także udanych | `colcon test-result --all --verbose` |
| pominąć colcona przy pisaniu | `cd ws/src/grip_monitor && python3 -m pytest test/ -v` |

Wyniki lądują w dwóch miejscach: raport JUnit w `ws/build/grip_monitor/pytest.xml`,
surowe wyjście w `ws/log/latest_test/grip_monitor/`. Oba są w `.gitignore` i tak
ma być. W pętli pisania używaj `python3 -m pytest` — różnica jest dziesięciokrotna,
a `-m` nie jest ozdobnikiem: bez niego `import grip_monitor.detector` się wywala.

### Izolacja, czyli dlaczego twój test bywa zielony bez powodu

Domyślny kontekst rclpy jest **globalny na proces**, a `pytest` uruchamia wszystkie
testy w jednym procesie. `rclpy.init()` w drugim teście trafia na kontekst
zostawiony przez pierwszy, a węzeł niezniszczony w pierwszym nadal nasłuchuje
w drugim. Objawia się to testami, które przechodzą pojedynczo i padają w zestawie —
albo, co gorsze, odwrotnie. Lekarstwo jest mechaniczne: `rclpy.Context()`,
`rclpy.init(context=ctx)`, własny `SingleThreadedExecutor(context=ctx)`,
`destroy_node()` w `finally` — gotowy fixture masz w zadaniu 04.3.

`ROS_DOMAIN_ID` to druga połowa izolacji: `devcontainer.json` ma `--network=host`
i `--ipc=host`, więc kontener dzieli sieć i pamięć dzieloną z Fedorą, a węzeł
zostawiony w drugim terminalu **publikuje do twojego testu** — test jest zielony,
bo złapał wiadomość, tylko nie od tego węzła, który testujesz. Domena odcina to na
poziomie DDS; trzymaj się zakresu 0–101. Najpewniej ustawić ją dla całego biegu:
`ROS_DOMAIN_ID=42 colcon test --packages-select grip_monitor`. Niektóre wersje
rclpy przyjmują też `rclpy.init(context=ctx, domain_id=42)` — sprawdź u siebie
zamiast wierzyć:
`python3 -c "import inspect, rclpy; print(inspect.signature(rclpy.init))"`.

Cztery reguły przeciw migotaniu, w tej kolejności:

1. **Budżet czasu zamiast `sleep`.** Nigdy nie usypiaj „na tyle, żeby zdążyło" —
   pętl z krótkim `spin_once` aż do terminu.
2. **Czekaj na warunek, nie na czas.** Zanim cokolwiek opublikujesz przez
   `BEST_EFFORT`, poczekaj, aż `publisher.get_subscription_count() > 0`.
3. **Jeden test, jeden kontekst** — i własny executor, nie `rclpy.spin()`.
4. **Żadnych współdzielonych topików między testami.** Jeśli dwa testy nadają na
   `vacuum_pressure`, to nie są dwa testy.

### Dwa lintery w jednym pakiecie

W `ws/src/grip_monitor/test/` leżą trzy pliki, których nie napisałeś:
`test_copyright.py`, `test_flake8.py`, `test_pep257.py`. Wygenerował je
`ros2 pkg create` i odpowiadają im trzy wpisy `<test_depend>` w `package.xml`.
To nie są testy twojego kodu — to **lintery udające testy**.

Jednocześnie repo lintuje ruffem. `line-length = 99`, `quote-style = "single"`
i lista `ignore` w `ruff.toml` są **ręcznie przepisane** z
`/opt/ros/jazzy/lib/python3.12/site-packages/ament_flake8/configuration/ament_flake8.ini`,
bo konfiguracji amenta nie da się nadpisać z repo — a kopie się rozjeżdżają: po
aktualizacji `ament_lint` formatter przy Ctrl+S zacznie psuć to, co `colcon test`
zaraz sprawdzi, i nie powie ci dlaczego.

Osobno `test_copyright.py`. `ament_copyright` sprawdza nagłówki licencyjne w plikach
źródłowych i deklarację licencji w `package.xml` — a twoje ma
`<license>TODO: License declaration</license>`, czyli dokładnie to, co ten linter
miał złapać. Nie łapie, bo szablon opatrzył go dekoratorem
`@pytest.mark.skip(reason='No copyright header has been placed...')`. Test wiecznie
zielony, bo się nie wykonuje — gorszy niż brak testu, bo liczy się w statystykach.

| wariant | co zyskujesz | co tracisz |
|---|---|---|
| **usuwasz trzy pliki z `test/` i trzy `<test_depend>`** | jeden linter, jedna konfiguracja; `ruff.toml` przestaje być kopią cudzego pliku; `colcon test` pokazuje wyłącznie regresje logiki | wypadasz z konwencji świata ROS-a; tracisz `ament_copyright` (który i tak masz wyłączony) |
| zostawiasz ament, wyrzucasz ruffa | zgodność z każdym repo ROS-owym i z buildfarmem | tracisz formatOnSave i sortowanie importów; wracasz do ręcznego poprawiania spacji |
| zostawiasz oba | nic | dwa źródła prawdy o stylu, cicho się rozjeżdżające |

**Wybierz pierwszy.** Powód: masz jedną parę rąk, a mierzalna wartość `ament_flake8`
ponad ruffa wynosi zero. Koszt: **każde cudze repo ROS-owe, które otworzysz, ma te
trzy pliki.** Musisz umieć je przeczytać, wiedzieć, czemu `test_copyright` jest
zielony, i nie zdziwić się, gdy ktoś w PR zażąda zgodności z `ament_flake8`.

## Zadania

### Zadanie 04.1 — Wytnij detektor i obłóż go testami (rdzeń)

**Cel:** logika detekcji przestaje potrzebować ROS-a, a jej granice są zapisane
w asercjach.
**Ćwiczysz:** szew — dopóki sam nie przeniesiesz callbacka do klasy bez `rclpy`,
„tego się nie da przetestować" brzmi jak cecha ROS-a, a nie jak twoja decyzja.

Przenieś logikę z `on_measurement` do `grip_monitor/detector.py` (szkielet wyżej).
W `grasp_monitor.py` zostaw subskrypcję, wywołanie klasy i publikację; dodaj
`**kwargs`. Potem `ws/src/grip_monitor/test/test_detector.py`:

```python
import pytest

from grip_monitor.detector import GraspDetector


def feed(d, value, count):
    return [d.update(value) for _ in range(count)]


def test_milczy_dopoki_okno_sie_nie_zapelni():
    d = GraspDetector(window=25)
    assert feed(d, -59.0, 24) == [None] * 24
    assert d.update(-59.0) == 'sealed'


@pytest.mark.parametrize(('mean', 'expected'), [
    (0.0, 'open'), (-0.999, 'open'),
    (-1.0, 'leak'),        # w starym kodzie: cisza
    (-58.0, 'leak'),       # w starym kodzie: cisza
    (-58.001, 'sealed'), (-59.9, 'sealed'),
    (-60.0, 'unknown'),    # czujnik poza zakresem
    (5.0, 'unknown'),      # nadciśnienie
])
def test_granice_pasm(mean, expected):
    d = GraspDetector(window=1)
    d.update(mean)
    assert d.state == expected


def test_zwraca_tylko_zmiany():
    d = GraspDetector(window=1)
    assert [d.update(0.0) for _ in range(4)] == ['open', None, None, None]


def test_potwierdzenie_gasi_drgania_na_granicy():
    d = GraspDetector(window=1, confirm=3)
    assert [d.update(0.0) for _ in range(3)][-1] == 'open'
    assert [d.update(v) for v in (-1.5, 0.0, -1.5, 0.0)] == [None] * 4


def test_przejscie_open_sealed_produkuje_widmowy_leak():
    d = GraspDetector(window=25, confirm=1)
    feed(d, 0.0, 25)
    assert [z for z in feed(d, -59.0, 25) if z] == ['leak', 'sealed']
```

Ostatni test zapisuje widmowy `leak` jako **opis błędu**, nie kontraktu. Dopisz to
w komentarzu, bo za miesiąc nie odróżnisz jednego od drugiego.

**Gotowe, gdy:** `cd ws/src/grip_monitor && python3 -m pytest test/test_detector.py -v`
daje same `PASSED` poniżej sekundy, a `grep -c rclpy grip_monitor/detector.py`
zwraca `0`.

### Zadanie 04.2 — Jeden linter, nie dwa (rdzeń)

**Cel:** w pakiecie zostaje jedno źródło prawdy o stylu, a decyzja jest zapisana.
**Ćwiczysz:** czytanie `colcon test-result` jako źródła prawdy — dopiero gdy znikną
z listy trzy wyniki linterskie, widzisz, ile w zestawie było asercji o twoim kodzie.

Usuń `test/test_copyright.py`, `test/test_flake8.py`, `test/test_pep257.py`
i odpowiadające im `<test_depend>` z `package.xml`; zostaw `python3-pytest`.
Przy okazji napraw `<license>TODO: License declaration</license>` i to samo pole
w `setup.py` — jeśli nie masz zdania, wpisz `Apache-2.0`, jak reszta ROS-a.
Decyzję razem z kosztem („cudze repo ROS-owe będzie miało te pliki") dopisz do
`projects/grab-fail-detection/NOTES.md`, nie do głowy.

**Gotowe, gdy:** `colcon test` + `colcon test-result --verbose` pokazują wyłącznie
twoje testy — żadnego pominięcia, żadnego wyniku linterskiego — a liczba testów
w raporcie zgadza się z liczbą napisanych funkcji `test_*`.

### Zadanie 04.3 — Test węzła w izolowanym kontekście (rdzeń)

**Cel:** udowodnić, że węzeł faktycznie subskrybuje `vacuum_pressure` i publikuje
`String` na `grasp_verdict` — bez uruchamiania procesu poza `pytest`.
**Ćwiczysz:** izolację kontekstu i budżet czasu zamiast `sleep` — przeczytane brzmią
jak przesada, dopóki twój własny test nie zawiśnie, bo nikt nie kręci executorem.

```python
# ws/src/grip_monitor/test/test_grasp_monitor_node.py
import time

import pytest
import rclpy
from rclpy.executors import SingleThreadedExecutor
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy
from std_msgs.msg import Float32, String

from grip_monitor.grasp_monitor import GraspMonitor


@pytest.fixture
def ros(monkeypatch):
    monkeypatch.setenv('ROS_DOMAIN_ID', '42')
    ctx = rclpy.Context()
    rclpy.init(context=ctx)
    yield ctx
    rclpy.shutdown(context=ctx)


def spin_until(executor, predicate, budget_s=5.0):
    deadline = time.monotonic() + budget_s
    while time.monotonic() < deadline:
        if predicate():
            return True
        executor.spin_once(timeout_sec=0.05)
    return predicate()


def test_wezel_publikuje_werdykt_po_zapelnieniu_okna(ros):
    monitor = GraspMonitor(context=ros)
    probe = Node('probe', context=ros)
    qos = QoSProfile(depth=10, reliability=ReliabilityPolicy.BEST_EFFORT)
    pub = probe.create_publisher(Float32, 'vacuum_pressure', qos)
    odebrane = []
    probe.create_subscription(String, 'grasp_verdict',
                              lambda m: odebrane.append(m.data), 10)

    executor = SingleThreadedExecutor(context=ros)
    executor.add_node(monitor)
    executor.add_node(probe)
    try:
        assert spin_until(executor, lambda: pub.get_subscription_count() == 1), \
            'monitor nie podpiął się pod vacuum_pressure'
        for _ in range(25):
            pub.publish(Float32(data=-59.0))
            executor.spin_once(timeout_sec=0.01)
        assert spin_until(executor, lambda: odebrane), 'brak werdyktu w budżecie'
        assert odebrane[0] == '[state] sealed'
    finally:
        executor.shutdown()
        monitor.destroy_node()
        probe.destroy_node()
```

**Gotowe, gdy:** test przechodzi w mniej niż dwie sekundy, a po zakomentowaniu
`pub.publish(...)` pada z komunikatem „brak werdyktu w budżecie" **po pięciu
sekundach, nie po nieskończoności**. Drugi warunek jest ważniejszy.

### Zadanie 04.4 — Dwa procesy, prawdziwe DDS (rdzeń)

**Cel:** udowodnić, że `vacuum_sensor` i `grasp_monitor` uruchomione jako osobne
procesy naprawdę się widzą.
**Ćwiczysz:** klasę błędów, której poziomy 1 i 2 nie mają jak zobaczyć — to, jak twój
węzeł umiera. Tego nie da się wyczytać; to musi się u ciebie zapalić na czerwono.

```python
# ws/src/grip_monitor/test/test_para_launch.py
import unittest

import launch
import launch_ros.actions
import launch_testing
import launch_testing.actions
import pytest
from launch_testing_ros import WaitForTopics
from std_msgs.msg import Float32, String


@pytest.mark.launch_test
def generate_test_description():
    sensor = launch_ros.actions.Node(
        package='grip_monitor', executable='vacuum_sensor', name='vacuum_sensor',
        output='screen', parameters=[{'state': 'sealed'}])
    monitor = launch_ros.actions.Node(
        package='grip_monitor', executable='grasp_monitor', name='grasp_monitor',
        output='screen')
    return launch.LaunchDescription([
        sensor, monitor, launch_testing.actions.ReadyToTest()])


class TestParaZyje(unittest.TestCase):
    def test_oba_topiki_zyja(self):
        with WaitForTopics([('/vacuum_pressure', Float32),
                            ('/grasp_verdict', String)], timeout=15.0):
            pass


@launch_testing.post_shutdown_test()
class TestWyjscia(unittest.TestCase):
    def test_procesy_wyszly_czysto(self, proc_info):
        launch_testing.asserts.assertExitCodes(proc_info)
```

`ReadyToTest()` musi być ostatnią akcją — to twoja deklaracja „od teraz testy mają
prawo działać"; nikt jej za ciebie nie postawi. Klasy bez dekoratora to testy
**aktywne**: chodzą, gdy procesy żyją. Klasa z `@launch_testing.post_shutdown_test()`
rusza po ich wygaszeniu i tylko tam da się cokolwiek powiedzieć o kodzie wyjścia.

Bardzo prawdopodobne, że `test_procesy_wyszly_czysto` zapali się od razu na
czerwono: `main()` w obu węzłach nie łapie przerwania, a `launch` kończy procesy
sygnałem. To pierwsza rzecz, której nie zobaczył żaden wcześniejszy poziom —
**jak twój węzeł umiera**.

```python
from rclpy.executors import ExternalShutdownException

def main(args=None):
    try:
        init(args=args)
        spin(VacuumSensor())
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        try_shutdown()
```

Uruchamiasz to przez `colcon test` (pytest sam zbiera `@pytest.mark.launch_test`)
albo pojedynczo: `launch_test ws/src/grip_monitor/test/test_para_launch.py`.
Zajrzyj też do API `WaitForTopics` u siebie — to jedyne miejsce w tym etapie, gdzie
warto zobaczyć sygnatury na własne oczy:
`python3 -c "from launch_testing_ros import WaitForTopics; help(WaitForTopics)"`.
Dopisz `<test_depend>launch_testing</test_depend>` i
`<test_depend>launch_testing_ros</test_depend>` do `package.xml`.

**Gotowe, gdy:** test przechodzi po pełnym `colcon build --symlink-install` i
`source install/setup.bash`, trwa kilkanaście sekund i wiesz, że ta liczba jest
normalna, a nie objawem.

### Zadanie 04.5 — Złote nagranie jako test jednostkowy (rdzeń)

**Cel:** przepuścić prawdziwe dane z `chwyt-3-stany` przez czystą klasę i sprawdzić
sekwencję stanów — w czasie testu jednostkowego, bez ROS-a.
**Ćwiczysz:** zamianę nagrania w asercję. Uwierzysz w nią dopiero, gdy w oczekiwanej
sekwencji będziesz musiał wpisać `leak`, o którym wiesz, że jest błędem.

Najpierw rozstrzygnij, **co trafia do gita**, bo `.gitignore` blokuje dwie rzeczy
naraz: `**/bags/` (cały katalog) i `*.mcap` (rozszerzenie). Sprawdź sam:

```bash
git check-ignore -v projects/grab-fail-detection/bags/chwyt-3-stany/chwyt-3-stany_0.mcap
git check-ignore -v ws/src/grip_monitor/test/data/golden.csv
```

Pierwsze pokazuje `**/bags/`, drugie nie pokazuje nic. Ta różnica jest twoją
odpowiedzią: **git nie schodzi do wykluczonego katalogu, więc żadna negacja
wewnątrz `bags/` nie zadziała.**

| wariant | co commitujesz | koszt |
|---|---|---|
| **eksport próbek do CSV** w `ws/src/grip_monitor/test/data/golden-chwyt.csv` | kolumny `t_ns`, `pressure`; 1062 wiersze ≈ 25 kB | zero zmian w `.gitignore`, diffuje się w PR; tracisz QoS, typy i drugi topik |
| negacja dla jednej ścieżki: `!ws/src/grip_monitor/test/data/*.mcap` | oryginalny mcap (140 kB) | działa, bo blokuje go tylko `*.mcap`; binarka nie pokaże nic w diffie |
| `git add -f` | to samo, bez śladu decyzji | następna osoba nie wie, czy to było celowe |

Weź pierwszy. Wyciągnij próbki `/vacuum_pressure` narzędziami z
[etapu 03](./03-bagi-jako-dane.md), zapisz CSV, a decyzję wpisz do `NOTES.md` razem
z hashem commita, w którym powstał plik. Potem test:

```python
# ws/src/grip_monitor/test/test_zlote_nagranie.py
import csv
from pathlib import Path

from grip_monitor.detector import GraspDetector

GOLDEN = Path(__file__).resolve().parent / 'data' / 'golden-chwyt.csv'


def probki():
    with GOLDEN.open() as f:
        return [float(row['pressure']) for row in csv.DictReader(f)]


def test_sekwencja_stanow_na_prawdziwym_przebiegu():
    d = GraspDetector(window=25, confirm=1)
    assert [s for s in (d.update(v) for v in probki()) if s] == \
        ['open', 'leak', 'sealed', 'leak']


def test_potwierdzenie_usuwa_widmowy_leak():
    d = GraspDetector(window=25, confirm=25)
    assert [s for s in (d.update(v) for v in probki()) if s] == \
        ['open', 'sealed', 'leak']
```

`Path(__file__).resolve()` jest tu istotne: `colcon test` nie uruchamia pytesta
z katalogu, z którego się tego spodziewasz, a `--symlink-install` robi z drzewa
builda las dowiązań. Ścieżka względem pliku testu działa zawsze.

Nagranie nazywa się „chwyt-3-stany", a pierwszy test mówi o czterech. To nie błąd
w nazwie — to 24 wiadomości `leak` wstrzyknięte przez okno w moment uszczelnienia,
dokładnie te policzone w sekcji „Po co to". Drugi test pokazuje cenę ich usunięcia.
Wyjdzie też coś innego: werdykty **zapisane** w nagraniu mówią `[state] empty`,
a twój kod dziś mówi `open`. Słownik stanów rozjechał się z danymi i nikt nie
zauważył, bo `String` niczego nie waliduje — o czym był
[etap 01](./01-kontrakty-wiadomosci.md).

**Gotowe, gdy:** oba testy przechodzą poniżej sekundy, a `wc -c` na CSV daje mniej
niż 50 kB.

### Zadanie 04.6 — Zepsuj to (rdzeń, obowiązkowe)

**Cel:** zobaczyć, że poziomy piramidy łapią **rozłączne** klasy błędów — i
przestać traktować poziom 3 jako ceremoniał.
**Ćwiczysz:** przewidywanie zamiast sprawdzania — tabela trzech poziomów staje się
modelem dopiero wtedy, gdy pokaże ci twoją własną pomyłkę, a nie cudzą tezę.

Za każdym razem: zepsuj jedną rzecz, uruchom **cały** zestaw
(`colcon test --packages-select grip_monitor` + `colcon test-result --verbose`),
zapisz, który poziom się zapalił, cofnij zmianę.

- **Psucie 1 — odwrócony próg.** W `detector.py` zamień `sealed_at=-59.0` na
  `sealed_at=59.0` (albo odwróć nierówność w `_classify`).
- **Psucie 2 — zmieniona nazwa topiku.** W `vacuum_sensor.py` zmień
  `'vacuum_pressure'` na `'vaccum_pressure'`. Literówka jest celowo wiarygodna.

| | poziom 1 (detektor) | poziom 2 (węzeł) | poziom 3 (para procesów) |
|---|---|---|---|
| odwrócony próg | ? | ? | ? |
| zmieniona nazwa topiku | ? | ? | ? |

Wypełnij tabelkę **przed** uruchomieniem testów i porównaj. Jeśli przewidywania się
zgadzają, rozumiesz piramidę. Jeśli nie — masz w niej dziurę i wiesz gdzie.

Wariant dodatkowy: w `grasp_monitor.py` zmień `BEST_EFFORT` na `RELIABLE`
w subskrypcji i **nie ruszaj czujnika**. Oba węzły wstaną, oba będą żyły,
`list-running-nodes.sh` pokaże je oba, a werdyktu nie będzie. Mechanizm rozbierasz
w [etapie 05](./05-introspekcja-qos-narzedzia.md).

**Gotowe, gdy:** tabelka jest wypełniona, w dwóch komórkach masz „zielony mimo
błędu", i umiesz jednym zdaniem powiedzieć, dlaczego akurat tam.

### Zadanie 04.7 — Pokrycie i pytanie, czego ono dowodzi (rozszerzenie)

**Cel:** zmierzyć pokrycie i samodzielnie stwierdzić, że liczba nic nie mówi.
**Ćwiczysz:** różnicę między „linijka się wykonała" a „ktoś sprawdził wynik" — widać
ją tylko na 100% pokrycia pliku, w którym siedziały 24 fałszywe werdykty.

```bash
python3 -m pytest test/ --cov=grip_monitor --cov-report=term-missing
```

Jeśli `pytest-cov` nie ma w obrazie, dopisz `python3-pytest-cov` do
`.devcontainer/Containerfile` — nigdy `apt install` w działającym kontenerze
(`AGENTS.md`). `colcon` ma też własny przełącznik; sprawdź `colcon test --help`
zamiast wierzyć mi na słowo. Potem odpowiedz sobie na piśmie:

1. `detector.py` ma pewnie pokrycie bliskie 100%. Czy widmowy `leak` z zadania 04.5
   był w jakikolwiek sposób „niepokryty"? Nie był — ta linijka wykonywała się
   **za każdym razem**. Czego więc mierzy pokrycie?
2. `grasp_monitor.py` ma pokrycie niskie i to jest w porządku. Dlaczego?
3. Zadanie 04.6 jest ręcznym testem mutacyjnym. Która z liczb — pokrycie czy „ile
   mutacji złapał zestaw" — powiedziała ci coś, czego nie wiedziałeś?

**Gotowe, gdy:** masz w `NOTES.md` trzy zdania odpowiedzi i wiesz, dlaczego
w [etapie 11](./11-ci-i-awarie.md) progiem w CI nie będzie procent pokrycia.

## Pułapki

| objaw | przyczyna | co zrobić |
|---|---|---|
| `colcon test` zielone, a testy padły | colcon nie propaguje kodu wyjścia testów | zawsze `colcon test-result --verbose`; w skryptach `--return-code-on-test-failure` |
| `ModuleNotFoundError: grip_monitor` przy `pytest test/` | gołe `pytest` nie dokłada katalogu bieżącego do `sys.path` | `python3 -m pytest` z `ws/src/grip_monitor`, albo `source ws/install/setup.bash` |
| test węzła wisi do timeoutu, zero wiadomości | nikt nie kręci executorem albo publikujesz przed odkryciem subskrybenta | `spin_once` w pętli; czekaj na `get_subscription_count() > 0` |
| test zielony, choć usunąłeś testowany kod | wiadomość przyszła od węzła z drugiego terminala (`--network=host`, ta sama domena) | `ROS_DOMAIN_ID` dla testów; sprawdź `scripts/dev/ros2/list-running-nodes.sh` |
| testy przechodzą pojedynczo, padają w zestawie | wspólny domyślny kontekst rclpy i niezniszczone węzły | własny `rclpy.Context()` na test, `destroy_node()` w `finally` |
| `test_copyright` zawsze zielony | ma `@pytest.mark.skip` z szablonu `ros2 pkg create` | pominięty test to nie jest test, który przeszedł; usuń go (zadanie 04.2) |
| launch test: „package not found" albo brak pliku wykonywalnego | nie ma `ws/install/` albo terminal jest starszy niż build | `colcon build --symlink-install`, nowy terminal, `source install/setup.bash` |
| `post_shutdown_test` czerwony na kodzie wyjścia | `main()` nie łapie przerwania przy wygaszaniu przez launch | `except (KeyboardInterrupt, ExternalShutdownException)` + `try_shutdown()` |
| Ctrl+S przepisuje plik, a `colcon test` sypie `Q000`/`E501` | ruff i `ament_flake8` mają rozjechane konfiguracje | zadanie 04.2 — zostaje jeden linter |
| `import rclpy` nie działa przy odpalaniu testów z Ghostty | ROS jest wyłącznie w kontenerze | `scripts/dev/enter-devcontainer.sh`, potem `pytest` |
| test migocze raz na kilkanaście uruchomień | `time.sleep` użyty jako synchronizacja | budżet czasu + warunek; `sleep` nigdy nie jest synchronizacją |

## Sprawdź się

1. Dlaczego `colcon test` kończy się kodem 0, mimo że testy padły — i jakie są dwa
   różne sposoby, żeby to naprawić w skrypcie?
2. Masz literówkę w nazwie topiku w czujniku. Który poziom piramidy się zapali
   i dlaczego pozostałe dwa milczą?
3. Dlaczego test poziomu 2 z własnym `rclpy.Context()` nie wykryje niedopasowanego
   QoS między czujnikiem a monitorem, mimo że używa prawdziwego rclpy?
4. Po co czekać na `get_subscription_count() > 0` zamiast na `sleep(1)`, skoro
   sekunda „zawsze wystarcza"?
5. Dlaczego 100% pokrycia `detector.py` nie wykryło 24 fałszywych werdyktów `leak`?
6. Czym różni się test aktywny od `post_shutdown_test` i co da się sprawdzić
   wyłącznie w tym drugim?
7. Dlaczego usunięcie `test_flake8.py` jest decyzją do zapisania, a nie sprzątaniem?
8. Nagranie ma 1062 wiadomości na `/vacuum_pressure` i 1062 na `/grasp_verdict`.
   Co ta równość mówi o detekcji zbocza w kodzie, który to nagrał?

## Co przeczytać

- `https://docs.ros.org/en/jazzy/` — sekcja o testowaniu w „Tutorials"; oficjalna
  kolejność `colcon test` → `colcon test-result`, czyli ten krok, który wszyscy pomijają.
- `https://github.com/ros2/launch` i `https://github.com/ros2/launch_ros` — źródła
  `launch_testing` i `launch_testing_ros`; API czyta się z kodu szybciej niż
  z dokumentacji, a `WaitForTopics` to jeden krótki plik.
- `https://github.com/ament/ament_lint` — tu mieszka `ament_flake8.ini`, który
  `ruff.toml` ręcznie kopiuje; zajrzyj raz, żeby wiedzieć, co porzucasz w 04.2.
- `https://github.com/colcon/colcon-core` — verby `test` i `test-result`; po to,
  żeby zobaczyć, że „zielony colcon" nie jest błędem, tylko decyzją projektową.
- REP-2004 (`https://www.ros.org/reps/`) — kategorie jakości pakietów ROS-a; jakiego
  poziomu testów wymaga się od pakietu, który ma trafić do dystrybucji.
- Michael Feathers, *Working Effectively with Legacy Code* — rozdziały o szwach
  (*seams*); zadanie 04.1 to dokładnie ta operacja, tylko granicą jest callback,
  a nie konstruktor.

## Dziennik

    Data:

    1. Które psucie z zadania 04.6 dało wynik inny, niż przewidziałeś —
       i co to mówi o twoim modelu piramidy?

    2. Co zjadło najwięcej czasu: wyjęcie klasy, walka z migotaniem
       czy launch_testing? Dlaczego akurat to?

    3. Widmowy `leak` siedział w tym repo od pierwszego dnia i był widoczny
       w nagraniu. Dlaczego żadne narzędzie z etapów 01–03 go nie pokazało?

    4. Jedno zdanie, którego nie umiałbyś napisać tydzień temu, o różnicy
       między „kod działa" a „wiem, że kod działa".

    5. Co z tego etapu wziąłbyś do swojego backendowego projektu w pracy?

Dalej → [Etap 05 — Introspekcja i QoS](./05-introspekcja-qos-narzedzia.md)
