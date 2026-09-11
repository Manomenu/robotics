# Etap 02 — Czas, zdarzenia i stan

> Po tym etapie umiesz powiedzieć, **kiedy** powstał pomiar i **czy stan się
> zmienił** — czyli policzyć opóźnienie czujnik → werdykt i przestać nadawać
> 50 razy na sekundę informację, która nie zmienia się przez minutę.

| | |
|---|---|
| wejście | etap 01 zamknięty: własny typ wiadomości z polem `std_msgs/Header`, workspace się buduje, oba węzły chodzą |
| czas | 2–3 wieczory |
| kończy się | `/grasp_verdict` milczy, dopóki stan się nie zmieni; `/grasp_state` odpowiada natychmiast temu, kto podłączył się minutę później; monitor wypisuje opóźnienie odbioru w milisekundach |

W przykładach wiadomość z etapu 01 nazywam `VacuumReading` (pola: `header`,
`pressure_kpa`). Nazwałeś inaczej albo zrobiłeś stany stałymi `uint8` —
podmień nazwy, logika jest ta sama.

## Po ludzku: co to jest w twoim świecie

| w robocie | twój odpowiednik | gdzie analogia pęka |
|---|---|---|
| ROS time i topic `/clock` | podmieniony zegar w testach (`freezegun`, fake clock) | podmieniasz go **całemu systemowi naraz, po sieci** — węzeł, który nie dostał notatki, liczy w innej epoce i nie rzuca wyjątku |
| parametr `use_sim_time` | feature flag | to nie flaga funkcji, tylko zmiana znaczenia `now()`: dotyczy timerów, stempli i wszystkiego, co liczy różnice czasu |
| stan na `transient_local` | retained message w MQTT, ostatnia wartość w Redisie | retencję trzyma **nadawca**, nie broker; brokera nie ma, więc gdy jego proces padnie, ostatniej wartości nie ma skąd wziąć |
| zdarzenie zmiany stanu | webhook, event na kolejce | nie ma retry na poziomie aplikacji ani potwierdzenia; jak nie dowiozło, nikt się o tym nie dowie, bo nie ma kogo zapytać |
| histereza i debounce | debounce w UI, tłumienie flappingu w alertingu | próg dotyczy wielkości fizycznej z szumem, a każde drgnięcie to komunikat, że robot upuścił przedmiot i złapał go z powrotem |
| `now - stamp` | czas od nagłówka `X-Request-Start` | zegary są trzy i tylko dwa wolno od siebie odejmować; runtime nie powie ci, że pomieszałeś |

## Po co to — czego bez tego nie da się zrobić

`ws/src/grip_monitor/grip_monitor/vacuum_sensor.py` publikuje gołą liczbę:
`msg = Float32(); msg.data = state_value + noise`. **Moment pomiaru ginie
bezpowrotnie w chwili publikacji.** Odbiorcy zostaje tylko moment, w którym
wiadomość do niego doszła — liczba o innym znaczeniu, zależna od obciążenia
maszyny, kolejki executora i tego, czy akurat budujesz workspace w drugim
terminalu.

| chcesz | dlaczego się nie da |
|---|---|
| policzyć opóźnienie czujnik → werdykt | masz tylko czas odbioru; odejmiesz go od czasu odbioru i wyjdzie zero |
| dołożyć prąd silnika albo obraz po chwycie i połączyć w jedną decyzję | bez stempli nie wiesz, które próbki dotyczą tej samej chwili; 500 Hz i 5 Hz nie sparujesz po kolejności |
| odtworzyć kolejność zdarzeń z nagrania | rosbag2 zapisuje czas odbioru przez nagrywarkę, nie czas powstania pomiaru ([etap 03](./03-bagi-jako-dane.md)) |
| użyć `ros2 topic delay` | to polecenie czyta `header.stamp`; na `Float32` odpowie, że nagłówka nie ma |

Drugi problem jest w `grasp_monitor.py`, linie 31–44 — detekcja zbocza jest
zakomentowana:

```python
# if self.last_state != 'empty':
if is_at_level(mean, 0):
    self.publish_state_change('open')
# self.last_state = 'empty'
```

`publish_state_change` nie publikuje więc żadnej zmiany, tylko **aktualny
odczyt progu, 50 razy na sekundę**. W nagraniu
`projects/grab-fail-detection/bags/chwyt-3-stany/` leży przez to 1062
wiadomości na `/grasp_verdict` przy najwyżej kilku realnych zmianach stanu.

Trzeci problem widać dopiero po wypisaniu progów. `mean` dokładnie `-1.0`
albo `-58.0` nie pasuje do **żadnego** warunku (`-1 < -1` jest fałszem po
obu stronach), tak samo `mean` poniżej `-60` i powyżej `1`. Nie leci wtedy
nic — a stanu `unknown` w tym kodzie nie ma. Cisza na topicu znaczy
jednocześnie „nic się nie zmieniło" i „nie wiem, co się dzieje".

## Dlaczego to ciekawe

Ładny pomysł inżynierski jest tu jeden: **w ROS 2 czas jest danymi na topicu,
a nie usługą systemu operacyjnego.** Nie ma API „ustaw czas symulacji". Jest
zwykły topic `/clock` z wiadomościami `rosgraph_msgs/msg/Clock` i parametr
`use_sim_time`, który mówi węzłowi: przestań pytać jądro, słuchaj tego kanału.

Twój kod nie wie, że jest w symulacji — to samo `self.get_clock().now()`
działa na żywo, w Gazebo i przy odtwarzaniu nagrania. Czas można puścić
szybciej niż rzeczywistość (noc testów regresyjnych na dwudziestokrotnym
przyspieszeniu to technicznie jeden przejazd), wolniej, albo **zatrzymać** —
debugger na breakpoincie nie powoduje, że reszta świata ucieka do przodu. Ale
skoro czas jest topikiem, podlega prawom danych: można go zgubić, nagrać,
odtworzyć z opóźnieniem i **wysłać tylko do części węzłów** — najczęstsza
awaria tego etapu, w zadaniu 02.5 na własne oczy.

Druga ciekawa rzecz jest starsza niż komputery: drganie progu przy szumie
rozwiązuje się **przerzutnikiem Schmitta**, czyli progiem włączenia innym niż
próg wyłączenia. Pomysł z elektroniki z lat trzydziestych, u ciebie dosłownie
cztery linijki Pythona — i lepszy niż cokolwiek, co wymyślisz przy tablicy.

## Dlaczego to trudne

Bo **nic tu nie rzuca wyjątku.** Zły stempel to nie błąd, tylko liczba —
z innego świata. System działa, wykresy wyglądają normalnie, `list-topics.sh`
pokazuje wszystko, co ma pokazywać, a pomiar opóźnienia mówi minus
pięćdziesiąt sześć lat i to jest pierwszy moment, w którym cokolwiek zauważysz.

1. **`use_sim_time` jest parametrem węzła, nie systemu.** Nie ma przełącznika
   globalnego; w plikach startowych podaje się go każdemu węzłowi z osobna.
   Ten jeden, odpalony ręcznie z drugiego terminala „żeby szybko zobaczyć",
   go nie ma — i nikt nie protestuje.
2. **Pomieszanie zegarów wychodzi dopiero w runtime.** `Time.from_msg()` daje
   domyślnie `ROS_TIME`; odjęcie od niego czasu z zegara `STEADY_TIME` poleci
   wyjątkiem. Nie ma typu „czas z zegara X" w sygnaturze funkcji, a
   kompilatora, który by to złapał, nie ma w ogóle.
3. **Późny subskrybent nie dostaje nic.** Intuicja z Kafki mówi „dociągnę
   offset". Tu nie ma czego dociągać: domyślne `volatile` znaczy, że
   wiadomość sprzed twojego podłączenia nie istnieje.
4. **Histerezy i debounce nie ma w tutorialach ROS-a**, bo to nie temat
   ROS-a, tylko przetwarzania sygnałów. Bez nich detektor działa idealnie na
   wartościach `0`, `-20`, `-59` i sypie się dokładnie tam, gdzie pojawia się
   prawdziwy, graniczny przypadek.

## Wycinek prawdziwej roboty

Zgłoszenie brzmi: „robot reaguje z opóźnieniem, ale tylko czasami".
Integrator mówi, że to sieć; dostawca chwytaka, że to software; liczby nie ma
nikt. Po dwóch godzinach w systemie okazuje się, że połowa węzłów ma
`use_sim_time:=true` — ktoś testował na odtwarzaniu i zostawił parametr
w pliku uruchomieniowym, więc część celi liczy czas nagrania sprzed tygodnia,
a na różnicach między tymi światami ktoś zdążył oprzeć wykres. Do tego
zdarzenie „zgubiono przedmiot" leci w każdym cyklu, 50 razy na sekundę
zamiast raz, więc z nagrania nie da się policzyć, ile razy naprawdę wypadł.

Robisz wtedy to, co w zadaniach niżej: `ros2 param get <węzeł> use_sim_time`
na każdym węźle z listy i sprawdzenie, czy `/clock` ma nadawcę; pomiar
`now - header.stamp` obok odstępu między callbackami z zegara monotonicznego;
potem projekt topików — co jest zdarzeniem (publikacja przy zmianie), a co
stanem (`transient_local`, `depth=1`) — i histereza z policzonym `T_hold`.

Zostaje po tobie tabela „węzeł → `use_sim_time` → czym stempluje", poprawiony
plik uruchomieniowy i pierwsza liczba opóźnienia, która nie jest niczyim
wrażeniem. I zdanie, którego większość kandydatów nie mówi: zanim powiem, ile
trwa ta droga, muszę wiedzieć, w którym zegarze zmierzono oba jej końce — i czy
ten topic niesie zdarzenia, czy stan.

## Model pojęciowy

### Trzy zegary i po co są trzy

| zegar | `ClockType` | co pokazuje | do czego |
|---|---|---|---|
| ROS | `ROS_TIME` | zegar systemowy **albo** `/clock`, zależnie od `use_sim_time` | stemplowanie danych; wszystko, co ma mieć sens w nagraniu i w symulacji |
| systemowy | `SYSTEM_TIME` | zegar ścienny jądra (`CLOCK_REALTIME`) | korelacja z logami spoza ROS-a, znacznik „kiedy to było" dla człowieka |
| monotoniczny | `STEADY_TIME` | monotoniczny zegar jądra, od nieokreślonego punktu | **pomiar interwałów**: timeouty, „ile trwał ten callback", watchdog |

Zegar ścienny wolno **przestawić** — robi to NTP, administrator i
wirtualizacja po uśpieniu hosta. Mierząc nim czas trwania operacji, w momencie
skoku dostaniesz wynik ujemny albo o sekundę za duży i nie poznasz, że tak
się stało. Zegar monotoniczny nigdy się nie cofa, ale jego wartość
bezwzględna nic nie znaczy: nie odczytasz z niej daty ani nie porównasz jej
z odczytem z innej maszyny. Stąd podział bez wyjątków: **interwały mierzysz
zegarem monotonicznym, dane stemplujesz zegarem ROS-a.**

```python
from rclpy.clock import Clock, ClockType
from rclpy.duration import Duration
from rclpy.time import Time

self.get_clock().now()               # rclpy.time.Time, ROS_TIME
self.get_clock().now().to_msg()      # builtin_interfaces/Time -> header.stamp
Time.from_msg(msg.header.stamp)      # z powrotem, domyślnie ROS_TIME

steady = Clock(clock_type=ClockType.STEADY_TIME)
t0 = steady.now()
elapsed: Duration = steady.now() - t0     # Time - Time = Duration
elapsed.nanoseconds / 1e6                 # w milisekundach
Duration(seconds=0.5).to_msg()            # builtin_interfaces/Duration
```

`Time - Duration` daje `Time`, a odjęcie czasów o różnych `ClockType` kończy
się wyjątkiem — i dobrze, bo to jedyne miejsce, w którym runtime w ogóle
broni cię przed pomieszaniem zegarów.

### `use_sim_time` i `/clock`

Każdy węzeł ma parametr `use_sim_time` zadeklarowany automatycznie, domyślnie
`false`. Mechanizm jest prosty:

    false  ->  zegar ROS węzła czyta zegar systemowy
    true   ->  zegar ROS węzła przestaje pytać system, czeka na /clock
               i pokazuje to, co stamtąd przyszło; przed pierwszą
               wiadomością stoi na ZERZE

Na `/clock` nadaje ten, kto steruje czasem: `ros2 bag play --clock` przy
odtwarzaniu albo symulator ([etap 07](./07-gazebo-stanowisko.md) — Gazebo
przez `ros_gz_bridge`).

Zwróć uwagę na słowo **zero**. Węzeł z `use_sim_time:=true`, do którego
`/clock` nie dociera, nie zgłasza błędu — stoi w roku 1970. A ponieważ timery
`create_timer()` chodzą na zegarze węzła, węzeł o stojącym czasie **nie
tyka**: `vacuum_sensor` z tym parametrem i bez `/clock` nie opublikuje ani
jednej wiadomości, choć `list-running-nodes.sh` pokaże go jako żywego. To
pierwsza rzecz do sprawdzenia, gdy „węzeł działa, a nic nie leci".

Ta awaria wygląda tak: jeden węzeł ma `use_sim_time`, drugi nie. Oba
publikują, oba widzą się w grafie, wszystko wygląda, jakby działało. Ale
stemple pochodzą z dwóch światów — jeden liczy od epoki, drugi od zera
symulacji — więc każda różnica między nimi jest śmieciem rzędu 1,79 miliarda
sekund, czyli **56 lat**. Nagranie w tym repo zaczyna się o `1788702196.873`
s od epoki (6 września 2026); po stronie symulacyjnej ten sam moment ma numer
bliski zera.

### Stempel to dane, nie metadane

`header.stamp` nie jest ozdobnikiem ani polem administracyjnym. Jest
**wynikiem pomiaru czasu wykonanego przez źródło danych**: ktoś go zmierzył,
mógł go zmierzyć źle i odpowiada za jego jakość — dokładnie jak za wartość
ciśnienia. W ROS 2 **nikt tego pola nie wypełnia za ciebie**; jeśli go nie
ustawisz, w wiadomości leżą zera i wygląda to jak poprawny stempel
z 1 stycznia 1970.

```python
msg = VacuumReading()
msg.header.stamp = self.get_clock().now().to_msg()
msg.pressure_kpa = state_value + noise
self.pub.publish(msg)
```

W `vacuum_sensor.py` moment pomiaru i moment publikacji to ta sama chwila, bo
czujnik jest zmyślony. W prawdziwym czujniku to dwa różne momenty, a różnica
bywa większa niż całe opóźnienie transportowe:

| źródło opóźnienia | rząd wielkości |
|---|---|
| przetwornik: konwersja, uśrednianie wewnętrzne | dziesiątki µs – ms |
| bufor USB, odpytywanie w sterowniku | 1–10 ms, nierówno |
| cykl EtherCAT / magistrali polowej | równy cyklowi, np. 1–4 ms |
| kolejka w węźle sterownika i w executorze | zmienne, rośnie pod obciążeniem |

Reguła: **stempluj moment powstania danych, najbliżej fizyki, jak potrafisz.**
Jeśli sterownik podaje znacznik sprzętowy (kamery z wyzwalaniem, EtherCAT
z Distributed Clocks) — użyj go i przelicz na czas ROS-a. Jeśli nie podaje,
stempluj przy odczycie ze sterownika i **zapisz w NOTES.md, że tak robisz**
oraz jakie to daje systematyczne przesunięcie. Stempel z momentu publikacji
jest lepszy niż żaden, ale kłamie zawsze w tę samą stronę: o całe opóźnienie
akwizycji.

Odbiorca liczy opóźnienie jednym odejmowaniem. Statystyka tej liczby — p95,
ogon, skąd się bierze — to [etap 09](./09-latencja-i-tracing.md); tu wystarczy
surowa różnica i zdziwienie, gdy urośnie.

```python
delay = self.get_clock().now() - Time.from_msg(msg.header.stamp)
delay_ms = delay.nanoseconds / 1e6
```

### Porównywanie stempli między węzłami

Na jednej maszynie problemu nie ma, i to dosłownie: kontener podmana dzieli
jądro z Fedorą, więc węzeł w kontenerze i skrypt na hoście czytają **ten sam
zegar**. Na dwóch maszynach zaczyna się osobna dziedzina: NTP daje
milisekundy (za mało, gdy mierzysz pętlę sterowania), PTP (**IEEE 1588**,
w Linuksie `linuxptp`) schodzi do mikrosekund, ale wymaga wsparcia w kartach
sieciowych i przełącznikach. W celi przemysłowej — kontroler, kilka
sterowników napędów, komputer percepcji — **synchronizacja zegarów jest
realnym, osobno projektowanym elementem systemu**: ma nazwę, budżet i własne
awarie.

### Zdarzenie kontra stan

To najważniejsze rozróżnienie tego etapu i nie jest ono o ROS-ie, tylko
o projektowaniu systemów.

| | zdarzenie (zmiana) | stan (poziom) |
|---|---|---|
| odpowiada na pytanie | „co się właśnie stało?" | „co jest teraz?" |
| częstotliwość | rzadko, nieregularnie | zawsze aktualne |
| kto ma dostać | ci, którzy słuchali **w tej chwili** | także ten, kto podłączył się minutę później |
| koszt zgubienia | duży, informacja przepadła na zawsze | mały, zaraz przyjdzie następna albo odczytasz ostatnią |
| w ROS 2 | topic `reliable`, publikacja tylko przy zmianie | topic `transient_local`, `depth=1` |

Z jednego nie da się odtworzyć drugiego. Ze strumienia zdarzeń zbudujesz stan
tylko wtedy, gdy masz **cały** strumień od początku — a nie masz, bo
podłączyłeś się przed chwilą i nie ma brokera z retencją. Ze stanu nie
odtworzysz zdarzeń, bo nie wiesz, ile zmian przegapiłeś między odczytami.
Dlatego robi się **oba topiki** i to nie jest duplikacja:

    /grasp_verdict   zdarzenia: reliable, publikacja przy zmianie stanu
    /grasp_state     stan:      reliable + transient_local, depth=1

```python
from rclpy.qos import DurabilityPolicy, QoSProfile, ReliabilityPolicy

state_qos = QoSProfile(
    depth=1,
    reliability=ReliabilityPolicy.RELIABLE,
    durability=DurabilityPolicy.TRANSIENT_LOCAL,
)
self.state_pub = self.create_publisher(GraspState, 'grasp_state', state_qos)
```

`TRANSIENT_LOCAL` to odpowiednik „latched" z ROS 1: nadawca trzyma ostatnie
`depth` próbek i **dostarcza je nowemu subskrybentowi zaraz po podłączeniu**.
Historię trzyma **nadawca**, we własnym procesie — po jego restarcie nie ma
żadnej ostatniej wartości, dlatego stan początkowy `UNKNOWN` nie jest ozdobą,
tylko jedyną uczciwą odpowiedzią. I odbiorca musi **poprosić**
o `transient_local`, żeby dostać próbkę z historii: `ros2 topic echo` wchodzi
domyślnie jako `volatile`, połączy się i będzie milczał do następnej zmiany.
Cała reszta QoS — `reliable` kontra `best_effort`, deadline, liveness,
niezgodności, przez które „węzły są, a się nie widzą" — to
[etap 05](./05-introspekcja-qos-narzedzia.md).

### Drganie progu: histereza i debounce

Szum w `vacuum_sensor.py` to `gauss(0, 0.5)`, więc średnia z 25 próbek ma
odchylenie `0.5/√25 = 0.1`. Gdy prawdziwa wartość leży **na progu**, średnia
przechodzi przez próg tam i z powrotem kilka razy na sekundę — a każde
przejście, przy poprawnej detekcji zbocza, jest osobnym werdyktem. Odbiorca
czyta z tego, że przedmiot został złapany i upuszczony cztery razy w sekundę.

Lekarstwo pierwsze, **histereza**: próg wejścia w stan inny niż próg wyjścia.
Zamiast przedziałów stykających się krawędziami robisz przedziały
**wejściowe** — wąskie, rozłączne — i strefę martwą między nimi, w której nie
zmieniasz nic:

```python
def classify(mean: float, previous: str) -> str:
    if mean > OPEN_ENTER:                        # np. -0.5
        return OPEN
    if mean < SEALED_ENTER:                      # np. -58.0
        return SEALED
    if LEAK_ENTER_HI > mean > LEAK_ENTER_LO:     # np. -5.0 .. -40.0
        return LEAK
    return previous          # strefa martwa: zostajemy tam, gdzie byliśmy
```

Ten kod przy okazji zasypuje dziury z oryginalnych progów: każda wartość ma
odpowiedź, bo `return previous` jest odpowiedzią domyślną. I nie potrzebuje
osobnego przypadku na start — jeśli `previous` zaczyna jako `UNKNOWN`,
detektor startujący w strefie martwej **zostaje w `UNKNOWN`**, dopóki nie
zobaczy czegoś jednoznacznego.

Lekarstwo drugie, **minimalny czas trwania stanu (debounce)**: nowy stan
ogłaszasz, gdy utrzyma się przez `T_hold`. Kosztuje `T_hold` zwłoki przy
każdej prawdziwej zmianie, więc nie dawaj go „na zapas" — policz. Średnia
ruchoma po przejściu z `sealed` (-59) do `open` (0) przejeżdża **liniowo**
przez całą skalę w czasie okna, czyli 0,5 s. Po drodze mija strefę wejściową
`leak` (-40 … -5), czyli 35 z 59 kPa:

    35/59 × 0,5 s ≈ 0,30 s w strefie „leak" — przy każdym odłożeniu przedmiotu

Czyli detektor melduje wyciek za każdym razem, gdy chwyt kończy się
poprawnie. To nie szum, tylko artefakt okna, i widać go dopiero po
policzeniu. `T_hold` musi być dłuższy niż te 0,30 s — albo, taniej, okno musi
być krótsze: przy 5 próbkach przejazd trwa 0,1 s, artefakt 0,06 s
i `T_hold = 0,1 s` wystarcza bez dokładania zwłoki.

### Okno kontra zwłoka — decyzja, którą wypowiadasz na głos

`deque(maxlen=25)` przy 50 Hz to **0,5 sekundy**: tyle trwa, zanim średnia
w pełni odpowie na zmianę fizyczną. Dłuższe okno tłumi szum (odchylenie
średniej maleje jak `1/√N`), krótsze skraca zwłokę. Liczba, która robi z tego
decyzję inżynierską: chwytak w transferze jedzie 0,5–1 m/s, więc **0,5 s to
25–50 cm drogi**. Werdykt „zgubiony w drodze" przychodzący po pół sekundy
dotyczy przedmiotu leżącego już pół metra dalej, a robot zdążył zacząć
następny ruch.

Zestaw to z resztą budżetu: okres próbkowania 20 ms, transport DDS lokalnie
ułamki milisekundy, okno 500 ms. Okno jest dwudziestopięciokrotnie większe
niż wszystko inne razem — zanim zaczniesz walczyć o mikrosekundy
w konfiguracji DDS-a, zauważ, że pół sekundy siedzi w twoim `deque`.
`N = 25` jest w porządku pod warunkiem, że wpiszesz do
`projects/grab-fail-detection/NOTES.md`, ile to kosztuje w milimetrach
i dlaczego zgadzasz się zapłacić.

### Dwa czujniki o różnych częstotliwościach

Które próbki prądu silnika (500 Hz) i obrazu po chwycie (5 Hz) dotyczą tej
samej chwili — na to odpowiada `message_filters` (jest już w obrazie):
`TimeSynchronizer` paruje po **dokładnie równych** stemplach, więc nadaje się
tylko wtedy, gdy jedno źródło wyzwala drugie; `ApproximateTimeSynchronizer`
paruje z tolerancją `slop` w sekundach — i to jego użyjesz. Oba czytają
`header.stamp`, więc bez tego etapu nie mają z czym pracować.

## Zadania

### Zadanie 02.1 — Stempel w źródle (rdzeń)

**Cel:** `vacuum_sensor` mówi, kiedy powstał pomiar.

**Ćwiczysz:** że stempel jest wynikiem pomiaru, który ktoś musi wykonać.
Dopóki sam nie wybierzesz linijki, w której wołasz `now()`, „moment powstania
danych" jest pojęciem, a nie twoją decyzją.

1. Publikuj wiadomość z etapu 01 zamiast `Float32` i wypełnij
   `msg.header.stamp = self.get_clock().now().to_msg()`.
2. `scripts/dev/build-colcon-workspace.sh`, potem
   `scripts/dev/ros2/run-node.sh grip_monitor vacuum_sensor`.
3. Z Ghostty: `print-topic-messages.sh /vacuum_pressure --field header`.

**Gotowe, gdy:** `sec` rośnie zgodnie z zegarkiem na ręce, `nanosec` zmienia
się co ~20 ms, a `ros2 topic delay /vacuum_pressure` przestaje mówić o braku
nagłówka. Jeśli chcesz mieć to pod ręką, dopisz
`scripts/dev/ros2/measure-topic-delay.sh` — prefiks `measure-` zgodnie
z `AGENTS.md`, trzyma terminal do Ctrl+C.

### Zadanie 02.2 — Opóźnienie odbioru (rdzeń)

**Cel:** jedna liczba w milisekundach, mówiąca, ile droga zajęła.

**Ćwiczysz:** podział pracy między trzy zegary z tabeli wyżej. Dopóki nie
zobaczysz obu liczb obok siebie na obciążonej maszynie, „opóźnienie danych"
i „odstęp między callbackami" brzmią jak to samo.

1. W `grasp_monitor.on_measurement` policz
   `self.get_clock().now() - Time.from_msg(msg.header.stamp)` i wypisuj co
   50. wiadomość przez `self.get_logger().info(...)`.
2. Osobno, na `Clock(ClockType.STEADY_TIME)`, zmierz odstęp między kolejnymi
   wywołaniami callbacku. Wypisuj obie liczby obok siebie.
3. Obciąż maszynę — odpal w drugim terminalu `build-colcon-workspace.sh` —
   i patrz, która z nich rośnie.

**Gotowe, gdy:** widzisz opóźnienie rzędu dziesiątych części milisekundy na
spokojnej maszynie, rosnące pod obciążeniem, i umiesz powiedzieć, dlaczego do
odstępów użyłeś innego zegara niż do opóźnienia.

### Zadanie 02.3 — Zdarzenie osobno od stanu (rdzeń)

**Cel:** `/grasp_verdict` milczy, gdy nic się nie dzieje; `/grasp_state`
odpowiada zawsze.

**Ćwiczysz:** rozróżnienie zdarzenie–stan w jedynej formie, w której da się je
sprawdzić: podłączasz podgląd **po** zmianie i widzisz, że z jednego topicu
nie dostajesz nic, a z drugiego aktualny stan natychmiast.

1. Dokończ detekcję zbocza: werdykt leci **tylko** wtedy, gdy nowy stan różni
   się od `self.last_state`.
2. Dołóż drugi publisher na `grasp_state` z `depth=1`
   i `DurabilityPolicy.TRANSIENT_LOCAL`, publikujący przy każdej zmianie.
3. Odpal oba węzły, przełącz czujnik:
   `scripts/dev/ros2/set-param.sh /vacuum_sensor state sealed`.
4. Dopiero **potem** podłącz podgląd stanu:
   `print-topic-messages.sh /grasp_state --qos-durability transient_local`.

**Gotowe, gdy:** `measure-topic-rate.sh /grasp_verdict` nie ma co mierzyć przy
spokojnym czujniku (zamiast 50 Hz), a podgląd `/grasp_state` podłączony minutę
po zmianie wypisuje aktualny stan **natychmiast**. Sprawdź też, co zobaczysz
bez `--qos-durability transient_local` — i dlaczego.

### Zadanie 02.4 — Histereza i stan `UNKNOWN` (rdzeń)

**Cel:** klasyfikacja, która nie ma dziur i nie drga.

**Ćwiczysz:** że próg to para liczb ze strefą martwą, a „nie wiem" to osobny
stan. Widać to dopiero, gdy postawisz średnią dokładnie na progu i zobaczysz,
że oryginalny kod nie odpowiada wtedy nic.

1. Wyjmij logikę progów z callbacku do czystej funkcji
   `classify(mean, previous)`, bez `self`. To zaliczka na
   [etap 04](./04-piramida-testow.md): taką funkcję da się przetestować bez
   ROS-a.
2. Zrób progi wejścia rozłączne, ze strefą martwą i `return previous`
   w strefie martwej. Stan początkowy: `UNKNOWN`.
3. Dołóż minimalny czas trwania stanu. Wartość uzasadnij rachunkiem z sekcji
   o oknie, nie zgadywaniem.

**Gotowe, gdy:** przełączenie czujnika `sealed` → `open` daje **dokładnie
jedną** zmianę stanu, a nie parę „leak", potem „open"; i gdy monitor
wystartowany przed czujnikiem raportuje `UNKNOWN`, zamiast milczeć.

### Zadanie 02.5 — Zepsuj to: dwa światy czasu (rdzeń)

**Cel:** zobaczyć niezgodność `use_sim_time` na własne oczy, żeby rozpoznać
ją za pół roku po jednym wydruku.

**Ćwiczysz:** rozpoznawanie tej awarii po jej podpisie — po znaku liczby i po
węźle, który żyje, a nie tyka. Zdanie „stemple z dwóch światów" czyta się
i zapomina, wydruku z 56 latami się nie zapomina.

1. Puść nagranie jako źródło czasu:
   `ros2 bag play projects/grab-fail-detection/bags/chwyt-3-stany --clock`
   (rosbag2 na poważnie robimy w [etapie 03](./03-bagi-jako-dane.md)).
2. Odpal monitor **z** parametrem:
   `run-node.sh grip_monitor grasp_monitor --ros-args -p use_sim_time:=true`,
   a czujnik **bez**. Popatrz na opóźnienie z zadania 02.2.
3. Zamień strony: czujnik z `use_sim_time:=true`, monitor bez. Zanim
   uruchomisz, zgadnij znak wyniku.
4. Odpal czujnik z `use_sim_time:=true` i **bez** odtwarzania, czyli bez
   `/clock` na szynie. Sprawdź `list-running-nodes.sh`, potem
   `measure-topic-rate.sh /vacuum_pressure`.
5. Wariant drugi: wyłącz histerezę i debounce (zostaw samą detekcję zbocza),
   ustaw jeden z progów dokładnie na aktualną wartość średnią — najprościej
   parametrem z zadania 02.6 — i policz werdykty przez
   `measure-topic-rate.sh /grasp_verdict`.

**Gotowe, gdy:** umiesz pokazać opóźnienie rzędu ±1,79e9 sekund (56 lat)
i powiedzieć z samego znaku, **który** węzeł miał `use_sim_time`; widzisz
węzeł, który żyje i nie publikuje nic, bo jego timer stoi na zerze; i masz
zmierzoną liczbę werdyktów na sekundę na granicy progu (spodziewaj się kilku,
nie jednego) kontra zero po włączeniu histerezy. Sprawdź przy okazji, czy
stemple w `self.get_logger().info(...)` idą za `/clock`, czy nie — zapisz
odpowiedź, bo to nie jest oczywiste.

### Zadanie 02.6 — Progi i histereza jako parametry (rozszerzenie)

**Cel:** strojenie detektora bez restartu i bez edytowania kodu.

**Ćwiczysz:** dobieranie progów pokrętłem zamiast rekompilacji — strefę martwą
i `T_hold` czuje się dopiero wtedy, gdy przesuwasz próg pod chodzącym
detektorem i patrzysz, w którym miejscu zaczyna drgać.

1. Zadeklaruj parametry: `window`, `open_enter`, `sealed_enter`,
   `leak_enter_lo`, `leak_enter_hi`, `hold_seconds`.
2. Czytaj je w miejscu użycia, a walidację (kolejność progów, `window > 0`)
   wpisz w `add_on_set_parameters_callback`, zwracając
   `SetParametersResult(successful=False, reason=...)` przy bzdurze. Nie
   powtarzaj wzorca z `vacuum_sensor._get_state_value`, który rzuca
   `RuntimeError` **w callbacku timera** — to zabija węzeł w locie.
3. Strój na żywo: `set-param.sh /grasp_monitor open_enter -0.3`. Nazwy
   parametrów wypisze `set-param.sh /grasp_monitor` bez argumentów.

**Gotowe, gdy:** zmiana progu działa natychmiast na chodzącym węźle, próba
ustawienia `sealed_enter` powyżej `open_enter` jest **odrzucona
z komunikatem**, a węzeł nadal żyje. Wartości, przy których detektor
zachowuje się dobrze, wpisz do `projects/grab-fail-detection/NOTES.md` —
parametr znika przy restarcie, notatka nie.

## Pułapki

| objaw | przyczyna | co zrobić |
|---|---|---|
| `now - stamp` wychodzi ±1,79e9 s (56 lat) | jeden węzeł ma `use_sim_time=true` i stoi na zerze, drugi czyta zegar systemowy | `ros2 param get <węzeł> use_sim_time` na **każdym** węźle; ustaw tak samo wszystkim |
| węzeł jest na liście, ale `measure-topic-rate.sh` nie ma co mierzyć | `use_sim_time=true` bez nadawcy na `/clock` — timer nie ma czym tykać | `list-topics.sh` i sprawdź, czy `/clock` w ogóle istnieje; dodaj `--clock` przy odtwarzaniu albo zdejmij parametr |
| wyjątek przy odejmowaniu czasów | różne `ClockType`: `Time.from_msg()` daje `ROS_TIME`, twój zegar do interwałów `STEADY_TIME` | stemple odejmuj od czasu ROS, interwały licz w obrębie jednego obiektu `Clock` |
| `print-topic-messages.sh /grasp_state` milczy, choć stan ustawiono minutę temu | podgląd wchodzi jako `volatile` i nie dostaje próbki z historii nadawcy | dopisz `--qos-durability transient_local` |
| subskrybent w ogóle nie łączy się ze stanem | subskrybent żąda `transient_local`, nadawca oferuje `volatile` — QoS niezgodne, cisza bez błędu | `show-topic-connections.sh /grasp_state`, porównaj obie strony; szerzej w [etapie 05](./05-introspekcja-qos-narzedzia.md) |
| `leak` melduje się przy każdym poprawnym odłożeniu przedmiotu | średnia z 25 próbek przejeżdża przez strefę „leak" w drodze z -59 do 0 przez ~0,30 s | `T_hold` dłuższy niż przejazd albo krótsze okno; policz, nie zgaduj |
| stan „znika" po restarcie węzła mimo `transient_local` | historię trzyma proces nadawcy, nie broker — brokera nie ma | `UNKNOWN` jako stan początkowy i jawna publikacja stanu przy starcie |
| stemple są, ale wszystko wygląda na opóźnione o pół roku | odtwarzasz nagranie bez `--clock`: stempel z września, `now()` z dziś | `--clock` plus `use_sim_time` u **wszystkich** węzłów, albo licz różnice wewnątrz nagrania |
| `ros2 topic delay` mówi, że nie ma nagłówka | na topicu leci `Float32`, typ bez `header` | to jest właśnie ten etap: typ z etapu 01 plus wypełniony `stamp` |
| próg nastrojony przez `set-param.sh` znika po restarcie | parametr żyje w procesie, nie w repo | zapisz do `NOTES.md`, docelowo do pliku YAML z parametrami |

## Sprawdź się

1. Dlaczego do zmierzenia „ile trwał ten callback" nie wolno użyć tego samego
   zegara, którym stemplujesz dane?
2. Węzeł ma `use_sim_time:=true`, a `/clock` nie nadaje nikt. Co pokazuje
   `self.get_clock().now()` i dlaczego węzeł przestaje publikować?
3. Dlaczego ze strumienia zdarzeń na `/grasp_verdict` nie da się odtworzyć
   aktualnego stanu, skoro zawiera on wszystkie zmiany?
4. Co dostanie subskrybent `/grasp_state`, który podłączy się po restarcie
   węzła publikującego — i dlaczego to nie ta sama sytuacja co retained
   message w MQTT?
5. Masz szum `gauss(0, 0.5)` i okno 25 próbek. Ile wynosi odchylenie średniej
   i jak szeroka musi być histereza, żeby nie drgała? Rachunek, nie intuicja.
6. Dlaczego sama histereza **nie wystarcza**, żeby detektor przestał meldować
   `leak` przy każdym odłożeniu przedmiotu?
7. Czujnik ma opóźnienie sterownika 5 ms, a ty stemplujesz w momencie
   publikacji. W którą stronę i o ile skłamie policzone opóźnienie
   czujnik → werdykt?
8. Dlaczego skracanie czasu transportu DDS-a nie ma sensu, dopóki
   `deque(maxlen=25)` zostaje bez zmian?

## Co przeczytać

- [docs.ros.org/en/jazzy](https://docs.ros.org/en/jazzy/) — szukaj „Clock and
  Time" oraz „Using time": kanoniczny opis `use_sim_time` i `/clock` dla
  twojej dystrybucji.
- [design.ros2.org](https://design.ros2.org/) — artykuł „Clock and Time". Tu
  jest **dlaczego** zaprojektowano to tak, a nie inaczej; czyta się raz
  i zostaje na lata.
- [github.com/ros2/rclpy](https://github.com/ros2/rclpy) — pliki
  `rclpy/clock.py`, `rclpy/time_source.py`, `rclpy/qos.py`. Kilkaset linii,
  po których przestaje być magią, co robi `use_sim_time`.
- [github.com/ros2/message_filters](https://github.com/ros2/message_filters)
  — źródło `ApproximateTimeSynchronizer`; zajrzyj, zanim zaczniesz pisać
  własne parowanie po stemplach.
- `ros2 topic delay --help` i `ros2 bag play --help` — dwa polecenia, które
  robią w tym etapie całą robotę diagnostyczną; przeczytaj listę flag,
  zamiast je zgadywać.

## Dziennik

    Co mnie zaskoczyło:

    Co zjadło najwięcej czasu i czy było tego warte:

    Które zdanie o czasie w ROS 2 uznałem za oczywiste, a okazało się fałszywe:

    Jaką liczbę (w ms albo mm) potrafię dziś podać o swoim detektorze,
    a tydzień temu nie potrafiłem:

Dalej → [Etap 03 — Bagi jako dane testowe](./03-bagi-jako-dane.md)
