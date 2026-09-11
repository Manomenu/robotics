# Etap 09 — Pomiar: latencja, jitter, tracing

> Umiesz podać, ile milisekund trwa droga od ciśnienia w przyssawce do werdyktu — p50, p95, p99 i najgorszy przypadek — i pokazać, w którym odcinku toru te milisekundy siedzą.

| | |
|---|---|
| wejście | etapy 01–03: werdykt jest własnym typem z polem na stempel źródłowy, pomiar ma `header.stamp`, umiesz czytać nagranie z `rosbag2_py`. Bez stempla ten etap nie ma czego odjąć. |
| czas | 3–4 wieczory |
| kończy się | skrypt, który z nagrania wypisuje p50/p95/p99/max drogi pomiar→werdykt i histogram odstępów między pomiarami — oraz tabela budżetu opóźnienia celi, w której suma zgadza się z tym, co wypisał skrypt |

## Po ludzku: co to jest w twoim świecie

| pojęcie robotyczne | odpowiednik z backendu | gdzie analogia pęka |
|---|---|---|
| okno uśredniania (`deque(maxlen=25)`) | okno agregacji w streamie | w streamie okno kosztuje pamięć; tutaj kosztuje **opóźnienie**, a opóźnienie przelicza się na milimetry drogi chwytaka |
| executor | event loop / pula wątków | pulę konfigurujesz ty, nie framework; nie ma autoskalowania, a GIL sprawia, że „więcej wątków" nie znaczy „więcej rdzeni" |
| grupa callbacków | poziom izolacji / semafor | niczego nie blokuje w twoich danych — mówi wyłącznie executorowi, co **wolno** mu puścić jednocześnie |
| stempel przeniesiony do wyniku | correlation ID / trace context | nikt go nie propaguje za ciebie: nie ma kontekstu żądania, nie ma middleware'u, jest pole w twojej wiadomości i twoja ręka |
| tick timera 50 Hz | cron / scheduled job | opóźnienie kwantyzacji jest **pozycją w budżecie**: zdarzenie fizyczne czeka średnio pół okresu, zanim w ogóle zostanie zauważone |
| profilowanie na produkcji | APM z samplingiem | pomiar wchodzi w tor sterowania i sam go zmienia; bezpieczny pomiar robi się **offline z nagrania**, nie na żywym robocie |

## Po co to — czego bez tego nie da się zrobić

W backendzie ogon rozkładu opóźnień to wolniejsza strona i gorszy wykres.
Tutaj to przedmiot, który zdążył spaść. Przelicz to na swojej celi: chwytak
jedzie 0,5 m/s, więc werdykt spóźniony o 20 ms to 10 mm drogi, których nie
dało się zatrzymać:

| prędkość chwytaka | 1 ms | 5 ms | 20 ms | 100 ms | 500 ms |
|---|---|---|---|---|---|
| 0,1 m/s | 0,1 mm | 0,5 mm | 2 mm | 10 mm | 50 mm |
| **0,5 m/s** | 0,5 mm | 2,5 mm | **10 mm** | 50 mm | 250 mm |
| 1,0 m/s | 1 mm | 5 mm | 20 mm | 100 mm | 500 mm |
| 2,0 m/s | 2 mm | 10 mm | 40 mm | 200 mm | 1000 mm |

Druga tabela dotyczy przedmiotu, który już się odczepił. Spadek swobodny,
`s = ½gt²`, `v = gt`:

| od zerwania podciśnienia minęło | przedmiot spadł o | i leci z prędkością |
|---|---|---|
| 20 ms | 2 mm | 0,2 m/s |
| 50 ms | 12 mm | 0,5 m/s |
| 100 ms | 49 mm | 1,0 m/s |
| 200 ms | 196 mm | 2,0 m/s |
| 500 ms | 1,23 m | 4,9 m/s |

**Milisekundy przelicza się na milimetry, i dopiero wtedy liczba znaczy coś
dla inżyniera mechanika po drugiej stronie stołu.** On nie kupi „p99 wynosi
480 ms". Kupi „zanim się dowiemy, przedmiot jest 1,2 metra niżej, czyli na
podłodze — albo podnosimy częstotliwość, albo dokładamy osłonę".

Bez tego etapu nie umiesz w tym repo odpowiedzieć na żadne z tych pytań:

- Ile trwa droga z `/vacuum_pressure` do `/grasp_verdict`? Nie wiesz —
  `std_msgs/String` nie niesie żadnego czasu, a `/vacuum_pressure` jako
  `Float32` też nie. To nie jest brak narzędzia, to brak danych.
- Czy `ros2 topic hz /vacuum_pressure` pokazujący 50,0 Hz cokolwiek dowodzi?
  Nie. Pokazuje, że **proces mierzący** odebrał wiadomości w takim tempie.
- Czy werdykt jest spóźniony o 10 ms czy o pół sekundy? Pół sekundy —
  i zaraz policzymy, dlaczego to wynika wprost z `deque(maxlen=25)`
  w `ws/src/grip_monitor/grip_monitor/grasp_monitor.py`, a nie z sieci.

## Dlaczego to ciekawe

Policz, co robi okno w twoim monitorze. Czujnik daje 50 Hz, okno ma
25 próbek, czyli 0,5 s. Ale ciekawa nie jest długość okna, tylko to, kiedy
**średnia przekroczy próg**.

Weź przejście „otwarte → uszczelnione": sygnał skacze z 0 do −59.
Po `k` nowych próbkach średnia z 25 wynosi `−59·k/25`. Próg `sealed` to
`is_at_level(mean, -59)`, czyli przedział `(−60, −58)`. Żeby średnia weszła
poniżej −58, potrzeba `k > 58·25/59 = 24,58`, czyli **wszystkich 25 próbek**.
Werdykt „sealed" pojawia się dokładnie 500 ms po zdarzeniu fizycznym.
Nie 240 ms. Nie „mniej więcej pół okna". Całe okno, co do próbki.

I drugi wniosek z tego samego rachunku: przez `k` od 1 do 24 średnia leży
w przedziale `(−58, −1)`, czyli w paśmie `leak`. **Każde przejście w tym
repo — w obie strony — poprzedza 480 ms werdyktów „leak".** To nie jest
błąd progów (tym zajmuje się [etap 10](./10-ewaluacja-na-danych.md)), to
czysta własność czasowa okna, którą umiesz policzyć z kodu, zanim
cokolwiek uruchomisz.

Teraz sprawdź, po co to okno w ogóle jest. Szum to `gauss(0, 0.5)`, czyli
σ = 0,5. Średnia z N niezależnych próbek ma σ = 0,5/√N. Przy N = 25 to 0,1 —
pasmo progu ±1 jest **dziesięć sigm** szerokie. Cztery sigmy (aż nadto)
dostajesz już przy N = 4, czyli przy oknie 80 ms. Ktoś wpisał 25, bo
25 wygląda rozsądnie. Ta jedna liczba kosztuje 400 ms opóźnienia, czyli
200 mm drogi chwytaka przy 0,5 m/s.

Ładny pomysł inżynierski jest tu taki: **największy składnik opóźnienia
w tym systemie nie jest w sieci, w DDS-ie ani w Pythonie — jest w jednej
liczbie w konstruktorze, której nikt nigdy nie policzył.** I dokładnie tak
to zwykle wygląda. Optymalizowanie `np.mean` (dziesiątki mikrosekund) przy
oknie 500 ms to poprawianie czwartej cyfry po przecinku.

`maxlen=25` to stała czasowa **przebrana za licznik**. Jeśli monitor zacznie
gubić wiadomości, okno nie skróci się — rozciągnie się w czasie, bo dalej
czeka na 25 próbek, tylko przychodzą rzadziej. Zobaczysz to w zadaniu 09.4.

## Dlaczego to trudne

**Średnia kłamie, a narzędzie ją podaje jako pierwszą.** Weź 1000 odstępów:
999 po 19,1 ms i jeden 1000 ms. Suma to 20,081 s, średnia 20,08 ms, czyli
49,8 Hz. Wygląda idealnie. W środku jest sekundowa dziura, w której cela
była ślepa. `ros2 topic hz` **wypisuje** `min`, `max` i `std dev` w tej samej
linijce — odchylenie wyjdzie 0,031 s przy średniej 0,020 s, czyli większe niż
sama średnia. Tylko że ludzie czytają pierwszą liczbę i idą dalej.

**Narzędzia mierzą co innego, niż się wydaje.** `ros2 topic hz` mierzy odstępy
między **odbiorami w procesie mierzącym**, nie częstotliwość nadawania.
`ros2 topic delay /grasp_verdict` pokaże ci ułamek milisekundy i będzie miał
rację — bo mierzy wiek werdyktu, a werdykt stemplujesz w chwili publikacji.
Droga pomiar→werdykt jest tam niewidoczna.

**Pomiar zmienia to, co mierzysz.** Każdy obserwator dokłada subskrybenta
i zabiera CPU, a logowanie w callbacku wydłuża callback. To jest ten sam
problem co profilowanie na produkcji, tylko dotkliwszy, bo tor jest krótszy.

**Wiedza plemienna.** Że okno w próbkach rozciąga się w czasie przy gubieniu
danych. Że sesję śledzenia trzeba wystartować **przed** węzłami, bo zdarzenia
inicjalizacyjne padają raz, przy starcie, i bez nich nie zmapujesz uchwytów
na nazwy. Że instrumentacja `ros2_tracing` jest najbogatsza dla warstw
`rcl` i `rclcpp`, a węzeł w `rclpy` pokaże mniej. Że w rootless podmanie nie
dostaniesz zdarzeń jądra. Żadnej z tych rzeczy nie ma w tutorialu na stronie.

## Wycinek prawdziwej roboty

Spotkanie u klienta. Cela zrzuca co dwudziesty detal, mechanik utrzymania
mówi: „wasz software jest za wolny, chwytak zaciska się za późno". Dostawca
chwytaka odsyła do karty katalogowej, integrator twierdzi, że to sieć. Nikt
nie ma liczby, więc wygrywa ten, kto mówi pewniej, a postój leci dalej.
„U mnie działa" tego nie wygrywa.

Robisz wtedy to, czego uczą zadania tego etapu, tylko na cudzym systemie:
budżet opóźnienia na kartce (09.1), stempel źródłowy w wiadomości, żeby było co
od czego odjąć (09.2), trzydzieści sekund nagrania i rachunek offline — p50,
p95, p99, max, histogram odstępów (09.3). Gdy liczby nie zgadzają się
z budżetem, psujesz jedną rzecz naraz i patrzysz, które narzędzie to widzi
(09.4); gdy podejrzenie pada na kolejkę, a nie na logikę — sesja śledzenia
(09.6). Kończy się zwykle tak samo: dominującą pozycją nie jest ani sieć, ani
Python, tylko czyjaś decyzja sprzed pół roku — okno uśredniania albo bufor.

Rozstrzyga jednak ostatni krok, komunikacyjny: p99 podajesz przeliczone na
milimetry drogi chwytaka, bo człowiek po drugiej stronie stołu myśli prędkością
i drogą hamowania. Zostaje po tobie jedna strona — budżet z właścicielem każdej
pozycji, dwie kolumny liczb przed i po, skrypt i nagranie, na których to
policzono. I zdanie, którego większość kandydatów nie umie powiedzieć: w którym
odcinku toru siedzą milisekundy i ile z nich da się urwać, czyim kosztem.

## Model pojęciowy

### Budżet opóźnienia jako dokument

Budżet opóźnienia to tabela, którą piszesz **zanim** zaczniesz mierzyć,
i poprawiasz po pomiarze. Ma jeden cel: powiedzieć, którego odcinka nie
warto ruszać. Dla twojej celi, tak jak stoi w repo dziś:

| odcinek | gdzie to siedzi w kodzie | typowo | najgorzej | czym zmierzyć |
|---|---|---|---|---|
| zjawisko fizyczne → wartość w czujniku | — (czujnik jest udawany) | 0 | 0 | karta katalogowa realnego przetwornika + jego filtr wejściowy |
| kwantyzacja timera 50 Hz | `self.create_timer(1.0 / 50, self._tick)` | 10 ms | 20 ms | wprost z okresu: średnio pół okresu |
| serializacja + transport DDS | domyślne RMW, `BEST_EFFORT` | <1 ms | ? | stempel nadania kontra czas odbioru |
| kolejka subskrypcji + executor | `spin()` jednowątkowy | ~0 | długość najdłuższego callbacka | zadanie 09.4, tracing |
| **okno uśredniania 25 próbek** | `self.frame = deque(maxlen=25)` | **500 ms** | **500 ms** | rachunek wyżej + potwierdzenie z nagrania |
| sam rachunek | `np.mean(self.frame)` | dziesiątki µs | ? | `time.perf_counter()` wokół ciała callbacka |
| publikacja werdyktu | `self.pub.publish(str_msg)` | <1 ms | ? | stempel w werdykcie kontra czas odbioru |
| **razem** | | **~510 ms** | **~520 ms** | |

Przy 0,5 m/s to 255 mm w typowym przypadku. Cztery piąte tej liczby pochodzi
z jednej linijki, która nie wygląda na czas — wygląda na rozmiar bufora.

Sieć jest podejrzanym numer jeden, bo jest obca. W tym repo sieć to promil
budżetu, a czas siedzi w twojej własnej decyzji projektowej.

Kolumny ze znakiem zapytania to nie jest lenistwo, tylko uczciwość: nie znasz
ich, dopóki nie zmierzysz. Zadanie 09.3 je wypełnia.

### Co dokładnie mierzą narzędzia z linii poleceń

| polecenie | mierzy | NIE mierzy | warunek |
|---|---|---|---|
| `ros2 topic hz TOPIC` | odstępy między **odbiorami w tym procesie**: średnia, min, max, odchylenie | częstotliwości nadawania; nie powie, ile wiadomości przepadło | żaden |
| `ros2 topic bw TOPIC` | bajty na sekundę i rozmiar wiadomości po stronie odbiorcy | narzutu DDS-a poniżej warstwy; nie rozbije tego na topiki fizycznego łącza | żaden |
| `ros2 topic delay TOPIC` | różnicę `teraz − header.stamp`, czyli **wiek wiadomości w chwili odbioru** | drogi przez system, jeśli stempel założono tuż przed publikacją | wiadomość **musi** mieć pole `header` typu `std_msgs/msg/Header` |

`ros2 topic delay` działa w tym repo **tylko dzięki [etapowi 02](./02-czas-zdarzenia-stan.md)** — na gołym `Float32` nie ma czego odjąć.

Dla obu pierwszych komend przydaje się `--window N` — im mniejsze N, tym
szybciej widać zmianę tempa. Resztę flag (dobór QoS, praca na czasie ściennym)
masz w `ros2 topic hz --help`.

**Czego nie mierzy `scripts/dev/ros2/measure-topic-rate.sh`.** To opakowanie na
`ros2 topic hz`: dziedziczy wszystkie jego ograniczenia i dokłada jedno swoje.

| nie mierzy | dlaczego to boli |
|---|---|
| nadawania — tylko odbiór w procesie `ros2 topic hz` | wolny odbiorca wygląda identycznie jak wolny nadawca |
| opóźnienia | nie wie, kiedy dana powstała; zna tylko chwilę, gdy ją dostał |
| strat | brak numeru sekwencji w `Float32` — nie da się powiedzieć, **które** wiadomości zginęły |
| percentyli i kształtu rozkładu | dostajesz min/max/odchylenie, nie p95, p99 ani histogram |
| korelacji dwóch kanałów | nie powie, ile trwa droga `/vacuum_pressure` → `/grasp_verdict` |
| własnego narzutu | to proces Pythona w kontenerze, konkurujący o CPU z tym, co mierzy |
| dziury krótszej niż okno | domyślne `--window 10000` rozmywa sekundową przerwę do niewidoczności |

Skrypt jest dobry do tego, do czego został napisany: „czy to w ogóle leci
i mniej więcej jak szybko". Do budżetu opóźnienia nie nadaje się wcale.

### Dlaczego patrzy się na rozkład, a nie na średnią

Średnia najskuteczniej ze wszystkich statystyk ukrywa ogon. Patrz na komplet:

| statystyka | co mówi | kiedy jest twoją odpowiedzią |
|---|---|---|
| minimum | ile ten tor **potrafi**, gdy nic nie przeszkadza | przy szacowaniu, ile da się urwać |
| mediana (p50) | typowe zachowanie | prawie nigdy — to liczba do prezentacji, nie do decyzji |
| p95 / p99 | kiedy zaczyna boleć | przy ustalaniu, co obiecujesz mechanikowi |
| maksimum | czy cela działa, czy nie | **zawsze** — jeden spóźniony werdykt to jeden przedmiot na podłodze |
| odchylenie | czy w ogóle masz do czynienia z jednym zjawiskiem | gdy σ ≳ średniej, rozkład jest wielomodalny i liczby tracą sens |
| histogram | ile jest trybów pracy | gdy podejrzewasz, że coś czasem wchodzi na inną ścieżkę |

Rozkład bimodalny — dwa garby zamiast jednego — to prawie zawsze dwie różne
drogi przez kod, a nie jedna droga z szumem. Średnia leży wtedy w dolinie
między garbami, czyli w miejscu, którego system nigdy nie osiąga.

### Pomiar end-to-end, tanio i solidnie

Recepta ma trzy kroki i żaden z nich nie wymaga nowego narzędzia:

1. **Przenieś stempel źródłowego pomiaru do wiadomości werdyktu.** Pole na to
   zaprojektowałeś w [etapie 01](./01-kontrakty-wiadomosci.md).
2. **Nagraj przebieg** — oba topiki, jak w [etapie 03](./03-bagi-jako-dane.md).
3. **Policz opóźnienia offline z nagrania**, czytnikiem `rosbag2_py`.

Dlaczego offline bije liczenie na żywo, choć wygląda na okrężną drogę:

| liczenie na żywo | liczenie offline z nagrania |
|---|---|
| twój kod liczący konkuruje o CPU z torem, który mierzy | robot już nie istnieje, rachunek niczego nie zaburza |
| jeden przebieg, jeden wynik; powtórka to nowy przebieg | sto rachunków na **tych samych** danych, do porównania co do próbki |
| zmiana definicji metryki wymaga restartu systemu | zmiana definicji to zmiana w skrypcie i `Enter` |
| trudne do powtórzenia po pół roku | nagranie leży i czeka; wynik jest odtwarzalny |
| pomiar jest kodem produkcyjnym | pomiar jest kodem analitycznym i wolno mu być wolnym |

Uwaga o czasie z nagrania, bez której policzysz nie to, co myślisz: znacznik
zapisany przez `rosbag2` to chwila, w której **nagrywarka** odebrała wiadomość
— trzeci obserwator, z własną kolejką i opóźnieniem. Drogę pomiar→werdykt
liczysz więc **ze stempli w wiadomościach**, a czas z nagrania tylko tam, gdzie
i tak jest względny: w odstępach między odbiorami tego samego topiku.

Stare nagranie `projects/grab-fail-detection/bags/chwyt-3-stany/` ma
`std_msgs/Float32` i `std_msgs/String`, czyli **zero stempli**: histogram
odstępów tak, opóźnienia nie.

To jest identyfikator korelacji, którego **nikt nie propaguje za ciebie**
(tabela analogii na górze pliku). W dłuższym łańcuchu — kamera → chmura
punktów → propozycja chwytu → werdykt — decyzja „który stempel niosę dalej"
musi zapaść raz i być zapisana, bo inaczej każdy węzeł zrobi to inaczej i suma
przestanie się zgadzać.

Który stempel włożyć do werdyktu, skoro monitor czyta 25 próbek naraz:

| wybór | co ci zmierzy | kiedy |
|---|---|---|
| stempel **najnowszej** próbki w oknie | drogę danej przez system: transport, kolejkę, executor, rachunek | domyślnie — to jest odpowiednik ID korelacji zdarzenia wyzwalającego |
| stempel **najstarszej** próbki w oknie | wiek najstarszej danej, która wpłynęła na werdykt | gdy chcesz jedną liczbą pokryć cały budżet, z oknem włącznie |

Nie ma tu poprawnej odpowiedzi, jest decyzja do zapisania. Praktycznie: nieś
najnowszy, a wkład okna policz osobno — jest stały i nie potrzebuje pomiaru.
Jeśli wiadomość ma miejsce na dwa pola, nieś oba.

### Executor i skąd bierze się jitter w twoim kodzie

`spin()` w `rclpy` to domyślnie **jeden wątek**. Oba twoje pliki kończą się
tak samo — `spin(node)` — i dopóki `vacuum_sensor` oraz `grasp_monitor` są
osobnymi procesami, mają po jednym wątku każdy i nie wchodzą sobie w drogę.

Włóż je do jednego procesu i obraz się zmienia:

- timer czujnika i callback subskrypcji monitora **konkurują o ten sam wątek**;
- długi callback blokuje wszystko — nie ma wywłaszczenia, executor czeka;
- każdy węzeł ma własną domyślną grupę callbacków typu
  `MutuallyExclusiveCallbackGroup`, czyli callbacki jednego węzła nigdy nie
  pójdą równolegle, nawet pod executorem wielowątkowym;
- `ReentrantCallbackGroup` pozwala na równoległe wejścia w ten sam callback,
  co znaczy również: ten sam callback może wykonać się dwa razy naraz, na
  dwóch kopiach twojego stanu. `deque` nie jest od tego chroniony przez ROS-a.

I pułapka, po której poznaje się, że ktoś to robił: `MultiThreadedExecutor`
w Pythonie **nie daje równoległości obliczeń**. GIL przepuszcza jeden bajtkod
naraz, więc zyskujesz tylko nakładanie się operacji, które GIL zwalniają —
czekanie na wejście-wyjście i wnętrze wywołań C.

W `rclcpp` istnieje komunikacja wewnątrzprocesowa (`use_intra_process_comms`),
która przy dwóch węzłach w jednym procesie omija transport. W sygnaturze
`rclpy.node.Node` takiego przełącznika nie ma, więc **wrzucenie dwóch węzłów
`rclpy` do jednego procesu nie skróci transportu, a doda sprzężenie na
wątku.** Zmierzysz to w zadaniu 09.5.

**Gdzie kończy się Python.** Przy pętlach rzędu kilkuset Hz i przy twardych
terminach — takich, po przekroczeniu których wynik jest bezwartościowy, a nie
tylko spóźniony — przechodzi się na C++ i `rclcpp`: brak GIL-a, unikanie
alokacji w torze krytycznym, dojrzalsza instrumentacja. Dalej na tej samej
drodze leży jądro z PREEMPT_RT i prealokacja pamięci.
**To jest decyzja, nie porażka**, i podejmuje się ją per węzeł, nie per system:
pętla prądowa 1 kHz w C++ i logika werdyktu w Pythonie to normalny, zdrowy
układ. Twój monitor liczy średnią 25 liczb dwa razy na sekundę. Nie ma o czym
rozmawiać.

### Skąd jeszcze bierze się jitter

| źródło | objaw | jak sprawdzić bez specjalnych narzędzi |
|---|---|---|
| odśmiecanie pamięci w Pythonie | pojedyncze odstępy kilka–kilkanaście razy większe, wracające cyklicznie | podepnij `gc.callbacks` i stempluj `time.perf_counter()`; próbnie `gc.disable()` i porównaj ogon |
| alokacje w callbacku | czas callbacka rośnie z liczbą żywych obiektów | policz, ile obiektów tworzysz na wiadomość; `tracemalloc` na krótkim przebiegu |
| `numpy` na małych tablicach | `np.mean` z 25 elementów: narzut wywołania większy niż rachunek | `python3 -m timeit` w kontenerze, `np.mean` kontra `sum(x)/len(x)` |
| warstwa DDS i jej bufory | pierwsze wiadomości po starcie zachowują się inaczej niż reszta | policz statystyki osobno dla pierwszych 100 wiadomości i dla reszty |
| kontener | wszystko wolniejsze, ale **równomiernie** — jitter bez zmiany kształtu rozkładu | porównaj dwa przebiegi w kontenerze przy różnym obciążeniu hosta |
| indeksowanie w VS Code | jitter skorelowany z pracą w edytorze (cpptools indeksuje `/opt/ros`) | powtórz pomiar z zamkniętym VS Code i porównaj p99 |
| zarządzanie częstotliwością procesora | odstępy rosną, gdy maszyna jest **bezczynna** | `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor`, `grep MHz /proc/cpuinfo` w pętli |
| planista systemu | rzadkie, duże wyskoki przy obciążeniu | `yes > /dev/null` na każdym rdzeniu i powtórka pomiaru |

Wniosek praktyczny: **zanim sięgniesz po tracing, przejdź tę tabelę.** Sześć
z ośmiu wierszy sprawdzisz w kilka minut poleceniem, które już masz.

### `ros2_tracing` i LTTng

`ros2 topic hz` i stemple mówią, **co** się stało. Nie powiedzą, co działo się
w środku warstwy `rcl` między odebraniem wiadomości przez DDS a wejściem
w twój callback. Do tego jest `ros2_tracing`: zestaw punktów śledzenia
wkompilowanych w ROS-a, zbieranych przez LTTng — tracer o narzucie rzędu
nanosekund na zdarzenie, działający w przestrzeni użytkownika.

Co to daje: zdarzenia inicjalizacji (węzeł, publikator, subskrypcja, timer),
publikacji, kolejkowania i — w warstwie `rclcpp` — początku i końca callbacka.
Z tego składa się odpowiedź na pytanie „ile czasu wiadomość przeleżała, zanim
executor po nią sięgnął", którego z zewnątrz nie da się zadać.

Uruchomienie, w skrócie:

```bash
# pakiety dokładasz w Containerfile (zadanie 09.6); tracetools jest już w obrazie

ros2 run tracetools status      # czy instrumentacja jest w ogóle wkompilowana
ros2 trace --help               # sprawdź tryby i flagi SWOJEJ wersji, nie zgaduj
lttng list --userspace          # jakie punkty śledzenia wystawiają DZIAŁAJĄCE procesy
```

Dane lądują domyślnie pod `~/.ros/tracing/<nazwa-sesji>/`, czyli poza repo
(patrz Pułapki). Format to CTF; czyta się go biblioteką babeltrace,
a `tracetools_analysis` przerabia go na ramki `pandas`, więc analiza wygląda
jak zwykła analiza danych w notatniku. Pakiet daje też polecenie
`ros2 trace-analysis` — zacznij od jego `--help`.

**Zasięg instrumentacji — uczciwie.** Węzeł napisany w `rclpy` woła `rcl` pod
spodem, więc część zdarzeń zobaczysz, ale zdarzenia początku i końca callbacka
pochodzą z `rclcpp` i dla węzła pythonowego ich tam nie będzie. **Nie znam
dokładnego zestawu zdarzeń, jaki wystawia `rclpy` w twojej wersji, i nie
zamierzam go zmyślać — wypisz go sam** przez `lttng list --userspace` przy
działającym węźle. To pięć sekund pracy i jedyna odpowiedź, na której możesz
polegać.

Sesję startujesz **przed** węzłami, a zdarzeń jądra w rootless podmanie nie
dostaniesz — jedno i drugie jest w Pułapkach. Zostaje przestrzeń użytkownika,
co dla pytań o executor wystarcza.

### Kiedy tracing, a kiedy stempel

Tutaj ludzie tracą dni, więc granica jest ostra: **90% problemów rozwiąże
stempel i nagranie.** Tracing wyjmujesz wtedy, gdy pytanie brzmi „dlaczego ten
callback wystartował 40 ms po tym, jak dane przyszły" — czyli gdy podejrzewasz
**executor**, a nie logikę.

| pytanie | czym odpowiadasz |
|---|---|
| ile trwa droga pomiar → werdykt | stempel + nagranie + rachunek offline |
| który procent werdyktów przekracza 300 ms | stempel + nagranie |
| czy gubimy wiadomości i ile | numer sekwencji w wiadomości + nagranie |
| czy werdykt jest spóźniony przez okno czy przez transport | stempel po obu stronach; rachunek z okna robisz na kartce |
| dlaczego callback wystartował 40 ms po przyjściu danych | **tracing** |
| czy callback A blokuje callback B | **tracing** (albo dwa stemple, jeśli umiesz je wstawić w oba) |
| ile zjada sama publikacja w `rcl` | **tracing** |
| czy inny RMW coś dał | stempel po obu stronach; tracing dopiero, gdy chcesz wiedzieć **gdzie** dał |

Reguła kciuka: jeśli umiesz wstawić stempel w miejsce, o które pytasz — wstaw
stempel. Tracing zostaje na miejsca w cudzym kodzie, gdzie nie masz gdzie go
wstawić.

## Zadania

### Zadanie 09.1 — Budżet opóźnienia celi jako tabela (rdzeń)

**Cel:** mieć na piśmie, gdzie siedzi czas, **zanim** zaczniesz mierzyć.
**Ćwiczysz:** budżet opóźnienia jako dokument — dopóki nie wpiszesz własnej
liczby w każdy wiersz, nie zobaczysz, że jeden wiersz zjada całą resztę tabeli.

Przepisz tabelę budżetu z sekcji „Model pojęciowy" do
`projects/grab-fail-detection/NOTES.md`, ale wypełnij ją **swoimi** liczbami
policzonymi z kodu, nie przeklejonymi stąd:

1. Dla każdego z trzech przejść (`open→sealed`, `sealed→open`, `open→leak`)
   policz na kartce, po ilu próbkach średnia z `deque(maxlen=25)` przekroczy
   próg. Wzór masz w sekcji „Dlaczego to ciekawe".
2. Policz, ile to milisekund przy 50 Hz i ile milimetrów przy 0,5 m/s.
3. Dopisz kolumnę „ile da się z tego urwać i jakim kosztem".
4. Osobno policz, jakie N wystarczy, żeby pasmo progu ±1 miało zapas czterech
   sigm przy σ = 0,5.

**Gotowe, gdy:** w `NOTES.md` jest tabela, w której jeden wiersz odpowiada za
ponad 90% sumy, i wiesz, który to wiersz, bez patrzenia.

### Zadanie 09.2 — Stempel źródłowy w werdykcie (rdzeń)

**Cel:** żeby werdykt niósł informację, z której chwili pochodzi dana, która
go wywołała.
**Ćwiczysz:** propagację stempla, której nie robi za ciebie żadne middleware —
dopiero przepisując go ręką, musisz wybrać, który stempel z okna niesie werdykt.

W `ws/src/grip_monitor/grip_monitor/grasp_monitor.py` trzymaj stemple
równolegle do wartości i przepisuj je do werdyktu (nazwy pól podstaw swoje,
z [etapu 01](./01-kontrakty-wiadomosci.md)):

```python
self.frame = deque(maxlen=25)
self.stamps = deque(maxlen=25)

def on_measurement(self, msg):
    self.frame.append(msg.data)
    self.stamps.append(msg.header.stamp)
    ...

def publish_state_change(self, name: str) -> None:
    verdict = GraspVerdict()
    verdict.header.stamp = self.get_clock().now().to_msg()   # kiedy powstał werdykt
    verdict.source_stamp = self.stamps[-1]                   # kiedy powstał pomiar
    verdict.state = name
    self.pub.publish(verdict)
```

Dwie rzeczy, które łatwo pomylić: stempel bierzesz **z wiadomości**, nie
z zegara w callbacku (inaczej mierzysz sam siebie), i `header.stamp` werdyktu
to **inna** wielkość niż `source_stamp` — pierwsza mówi, ile werdykt leżał
w transporcie, druga ile trwała cała droga.

Potem zbuduj, uruchom oba węzły i nagraj nowy przebieg z przełączaniem
parametru `state` (`scripts/dev/ros2/set-param.sh`), przez co najmniej
30 sekund, z kilkoma przejściami w obie strony.

**Gotowe, gdy:** `ros2 topic delay /grasp_verdict` wypisuje ułamki milisekundy
(bo mierzy `header.stamp` werdyktu), `ros2 topic delay /vacuum_pressure`
wypisuje sensowną liczbę, a ty umiesz w jednym zdaniu powiedzieć, dlaczego
**żadna z nich** nie jest odpowiedzią na pytanie „ile trwa droga do werdyktu".

### Zadanie 09.3 — Rachunek offline z nagrania (rdzeń)

**Cel:** wypełnić znaki zapytania z tabeli budżetu liczbami z danych.
**Ćwiczysz:** rozkład zamiast średniej — p99 i histogram trzeba raz zobaczyć na
własnych danych, żeby przestać ufać jednej liczbie z `ros2 topic hz`.

Napisz `projects/grab-fail-detection/analysis/latency.py`. Idzie do
`projects/`, a nie do `scripts/dev/ros2/`, bo konwencja z `AGENTS.md` rezerwuje
`dev/ros2/` na oglądanie działającego ROS-a, a to jest analiza danych.

Szkielet czytnika (reszta to zwykły Python):

```python
import rosbag2_py
from rclpy.serialization import deserialize_message
from rosidl_runtime_py.utilities import get_message

reader = rosbag2_py.SequentialReader()
reader.open(
    rosbag2_py.StorageOptions(uri=BAG_DIR, storage_id='mcap'),
    rosbag2_py.ConverterOptions('cdr', 'cdr'),
)
types = {t.name: t.type for t in reader.get_all_topics_and_types()}

while reader.has_next():
    topic, data, bag_t = reader.read_next()
    msg = deserialize_message(data, get_message(types[topic]))
```

Skrypt ma policzyć i wypisać:

1. dla `/grasp_verdict`: `header.stamp − source_stamp` w milisekundach,
   a z tego p50, p95, p99, minimum, maksimum i odchylenie;
2. dla `/vacuum_pressure`: odstępy między kolejnymi wiadomościami (z czasu
   nagrania) i z nich **histogram tekstowy** — GUI w tym kontenerze nie ma, więc
   rysuj gwiazdkami w terminalu, to wystarczy i zawsze działa;
3. liczbę wiadomości na każdym topiku i długość przebiegu.

Puść to najpierw na starym nagraniu `bags/chwyt-3-stany/` (2124 wiadomości,
21,2 s) — punkt 1 się nie uda, bo tam nie ma stempli, i to jest poprawny
wynik, nie awaria skryptu. Przy okazji sprawdź, czy 1062 = 1062 na obu
topikach to przypadek, i co ta równość mówi o momencie startu nagrywania.
Potem puść na nagraniu z zadania 09.2.

**Gotowe, gdy:** widzisz na ekranie p99 drogi pomiar→werdykt i histogram
odstępów, a p50 zgadza się z tabelą budżetu w granicach kilkunastu procent.
Jeśli się nie zgadza — masz do wyjaśnienia albo błąd w rachunku, albo składnik,
o którym zapomniałeś. Jedno i drugie jest wartościowe.

### Zadanie 09.4 — Zepsuj to: 50 ms w callbacku (rdzeń)

**Cel:** sprawdzić, które z twoich narzędzi w ogóle zauważy blokadę, które
zauważy ją pierwsze, a które opisze ją najdokładniej.
**Ćwiczysz:** zasięg każdego narzędzia i to, czym naprawdę jest `maxlen=25` —
o oknie rozciągającym się w czasie da się przeczytać, uwierzysz z nagrania.

**Wariant A.** Wstaw `time.sleep(0.05)` na początku `on_measurement`
w `grasp_monitor.py`. Czujnik nadaje co 20 ms, callback trwa 50 ms. Uruchom
oba węzły i zmierz **wszystkim, czym umiesz**, wypełniając tabelę:

| narzędzie | co pokazało | po ilu sekundach było to widać |
|---|---|---|
| `measure-topic-rate.sh /vacuum_pressure` | | |
| `measure-topic-rate.sh /grasp_verdict` | | |
| `ros2 topic delay /vacuum_pressure` | | |
| `ros2 topic delay /grasp_verdict` | | |
| `latency.py` na nagraniu (p50/p99/max) | | |
| histogram odstępów | | |

Pytania, na które tabela ma odpowiedzieć:

- Dlaczego `hz` po stronie **wejścia** wygląda normalnie, mimo że system jest
  zepsuty? Co z tego wynika o mierzeniu tylko jednej strony?
- Werdykty przychodzą wolniej, ale opóźnienie pojedynczego werdyktu ustala
  się na jakimś poziomie zamiast rosnąć w nieskończoność. Kolejka subskrypcji
  ma `depth=10` i `BEST_EFFORT` — powiąż jedno z drugim (mechanizm rozbieramy
  w [etapie 05](./05-introspekcja-qos-narzedzia.md), tu wystarczy obserwacja).
- Ile czasu obejmuje teraz okno 25 próbek, skoro monitor przerabia około
  20 wiadomości na sekundę? Porównaj z 0,5 s i zapisz wniosek o tym, czym
  naprawdę jest `maxlen=25`.

**Wariant B.** Cofnij `sleep`, zmień timer czujnika na `1.0 / 1000` i znajdź,
co pęka pierwsze. Sprawdzaj w tej kolejności i notuj liczby:

| podejrzany | jak sprawdzić |
|---|---|
| timer `rclpy` nie utrzymuje 1000 Hz | `ros2 topic hz` i porównanie z żądaną wartością |
| proces mierzący nie nadąża (mierzysz narzędzie, nie system) | dwa `hz` naraz, na dwóch terminalach — czy dają to samo |
| CPU jednego rdzenia | `top` w kontenerze podczas przebiegu |
| straty na `BEST_EFFORT` | liczba wiadomości w nagraniu kontra `1000 × czas` |
| okno skróciło się do 25 ms, więc werdykt przyspieszył 20× | `latency.py` na nowym nagraniu |

Ostatni wiersz jest najciekawszy: podniesienie częstotliwości **skróciło**
opóźnienie przy tym samym tłumieniu szumu, bo okno liczy próbki, nie czas.
Ale uwaga na granicę uczciwości: w tym repo szum jest niezależny w każdym
ticku, więc √N działa. Prawdziwy czujnik ma filtr wejściowy, sąsiednie próbki
są skorelowane i wtedy √N kłamie — więcej próbek nie znaczy mniej szumu.

**Gotowe, gdy:** obie tabele są wypełnione, a ty masz zapisaną jedną linijkę:
które narzędzie pokazało problem **pierwsze** i które pokazało go
**najdokładniej** — i dlaczego to nie jest to samo narzędzie.

### Zadanie 09.5 — Jeden proces, jeden executor (rdzeń)

**Cel:** zobaczyć na liczbach, co się zmienia, gdy dwa węzły dzielą wątek.
**Ćwiczysz:** executor i grupy callbacków — sprzężenia na wspólnym wątku nie
widać w kodzie, widać je dopiero jako ogon w histogramie.

Dodaj `ws/src/grip_monitor/grip_monitor/grip_cell.py` i wpis w `entry_points`
w `setup.py` (potem przebuduj — nowa komenda pojawi się dopiero po buildzie):

```python
from rclpy import init, shutdown
from rclpy.executors import SingleThreadedExecutor

from grip_monitor.grasp_monitor import GraspMonitor
from grip_monitor.vacuum_sensor import VacuumSensor


def main(args=None):
    init(args=args)
    sensor, monitor = VacuumSensor(), GraspMonitor()
    executor = SingleThreadedExecutor()
    executor.add_node(sensor)
    executor.add_node(monitor)
    try:
        executor.spin()
    finally:
        executor.shutdown()
        sensor.destroy_node()
        monitor.destroy_node()
        shutdown()
```

Zmierz `latency.py` i histogram odstępów w trzech układach: (a) dwa procesy,
(b) jeden proces z `SingleThreadedExecutor`, (c) jeden proces
z `MultiThreadedExecutor`. Powtórz (b) i (c) z `time.sleep(0.05)` z zadania
09.4 — tam różnica jest dopiero widoczna.

Postaw hipotezę **przed** pomiarem i zapisz ją. Dwie rzeczy do wyjaśnienia po
fakcie: czy transport się skrócił (i dlaczego `rclpy` nie ma komunikacji
wewnątrzprocesowej), oraz co dokładnie zrobił `MultiThreadedExecutor`, skoro
GIL i tak przepuszcza jeden bajtkod naraz.

**Gotowe, gdy:** masz trzy histogramy obok siebie i umiesz wskazać, który
z nich ma ogon, którego nie było w układzie (a) — oraz powiedzieć, co go
zrobiło.

### Zadanie 09.6 — Sesja śledzenia i lista zdarzeń (rdzeń)

**Cel:** zobaczyć zdarzenia z wnętrza `rcl` i samodzielnie ustalić, ile z nich
dostajesz dla węzła w Pythonie.
**Ćwiczysz:** zasięg instrumentacji — listy zdarzeń `rclpy` nie ma w żadnej
dokumentacji, więc jedyny sposób, żeby ją poznać, to wypisać ją u siebie.

1. Dopisz do `.devcontainer/Containerfile`: `ros-jazzy-ros2trace`,
   `ros-jazzy-tracetools-analysis`, `lttng-tools`. Przebuduj kontener.
2. `ros2 run tracetools status` — czy instrumentacja jest wkompilowana.
3. `ros2 trace --help` — przeczytaj, zanim uruchomisz. Nie przepisuj flag
   z internetu.
4. Wystartuj sesję, **potem** węzły, przepuść kilka przejść stanu, zatrzymaj
   sesję. Kolejność jest istotna i to jest połowa tego zadania.
5. Przy działającym węźle: `lttng list --userspace` i wypisz, które punkty
   śledzenia w ogóle istnieją w twoim procesie.
6. Obejrzyj ślad w `~/.ros/tracing/<sesja>/` — przez `ros2 trace-analysis`
   albo wczytaj do `pandas` w notatniku.

**Gotowe, gdy:** masz na piśmie listę zdarzeń, które twój węzeł `rclpy`
faktycznie wystawia, i potrafisz powiedzieć, czy jest wśród nich początek
i koniec callbacka. Jeśli nie ma — to też jest wynik, i to ten, który
w realnej pracy oszczędza dzień.

### Zadanie 09.7 — Inny RMW (rozszerzenie)

**Cel:** sprawdzić empirycznie, czy zmiana warstwy transportowej rusza liczby,
które cię obchodzą.
**Ćwiczysz:** projektowanie eksperymentu — dwie identyczne kolumny liczb uczą
o utonięciu małego składnika w dużym więcej niż jakiekolwiek zdanie o tym.

Dopisz `ros-jazzy-rmw-cyclonedds-cpp` do `Containerfile`, przebuduj i powtórz
pomiar z `RMW_IMPLEMENTATION=rmw_cyclonedds_cpp` ustawionym dla **obu**
procesów (jeden ustawiony to nie eksperyment, tylko awaria — węzły przestaną
się widzieć).

Porównaj: p50/p95/p99/max drogi pomiar→werdykt, histogram odstępów, straty.

Spodziewaj się, że w całkowitym opóźnieniu **nie zobaczysz nic** — składnik
dominujący jest twój, nie transportowy. Żeby zobaczyć cokolwiek, wydziel sam
odcinek transportu: stempel nadania kontra czas odbioru, na jednym topiku, bez
okna. Nauka z tego zadania: **eksperyment trzeba zaprojektować tak, żeby
mierzona rzecz nie ginęła w większym składniku.**

**Gotowe, gdy:** masz dwie kolumny liczb i zdanie o tym, czy różnica jest
większa od rozrzutu między dwoma przebiegami tego samego RMW. Jeśli nie
zrobiłeś dwóch przebiegów bazowych, nie masz z czym porównać.

## Pułapki

| objaw | przyczyna | co zrobić |
|---|---|---|
| `ros2 topic delay` odmawia na `/vacuum_pressure` | `std_msgs/Float32` nie ma pola `header` — nie ma czego odjąć | typ z [etapu 01](./01-kontrakty-wiadomosci.md) i stempel z [etapu 02](./02-czas-zdarzenia-stan.md); bez nich ta komenda nie działa z zasady |
| `ros2 topic delay /grasp_verdict` pokazuje 0,3 ms i wygląda świetnie | mierzy `header.stamp`, który zakładasz tuż przed publikacją | licz `header.stamp − source_stamp` offline; to jedyna liczba opisująca drogę |
| `hz` pokazuje 49,8 Hz, a system stoi sekundę | średnia zjada dziurę; `--window 10000` rozmywa ją do zera | czytaj `min`/`max`/`std dev` z tej samej linijki, zmniejsz `--window`, zrób histogram |
| `hz` pokazuje mniej, niż nadaje czujnik | proces `ros2 topic hz` nie nadąża albo gubi na `BEST_EFFORT` | odpal dwa `hz` naraz — jeśli dają różne liczby, mierzysz narzędzie |
| ślad LTTng nie zawiera nazw węzłów, tylko uchwyty | sesja wystartowała **po** węzłach, zdarzenia inicjalizacyjne przepadły | zatrzymaj wszystko, wystartuj sesję, dopiero potem węzły |
| sesja śledzenia nie wstaje, błąd o module jądra | rootless podman nie da ci zdarzeń jądra | zostań przy przestrzeni użytkownika; do pytań o executor wystarcza |
| śladu nie widać w repo | domyślna ścieżka to `~/.ros/tracing/`, a katalog domowy jest współdzielony z hostem | szukaj na Fedorze w `~/.ros/tracing/`; to dobrze, że nie leży w repo |
| dwa węzły w jednym procesie, a transport bez zmian | `rclpy` nie ma komunikacji wewnątrzprocesowej (`rclcpp` ma) | nie licz na to; jeden proces daj wtedy, gdy chcesz wspólnego executora, nie krótszego transportu |
| `MultiThreadedExecutor` nic nie przyspieszył | GIL — callbacki liczące w Pythonie i tak idą po kolei | rozdziel na procesy albo przenieś gorący węzeł do `rclcpp` |
| po zmianie RMW węzły przestały się widzieć | `RMW_IMPLEMENTATION` ustawione tylko w jednym terminalu | ustaw w obu; skrypty z `scripts/dev/ros2/` wchodzą do kontenera osobno, więc zmienna musi dojść do obu stron |
| liczby różnią się o 30% między przebiegami | kontener, indeksowanie w VS Code, skalowanie zegara CPU | zrób dwa przebiegi bazowe **zanim** zaczniesz porównywać cokolwiek innego |
| pomiar wstawiony do callbacka zmienił wynik | logowanie i formatowanie stringów w torze krytycznym kosztują | zbieraj do listy w pamięci, zapisuj po przebiegu, a najlepiej licz offline z nagrania |

## Sprawdź się

1. Dlaczego werdykt „sealed" pojawia się dokładnie 500 ms po zdarzeniu,
   a nie po połowie okna? Pokaż rachunek.
2. Dlaczego każde przejście stanu w tym repo poprzedza 480 ms werdyktów
   „leak" — i dlaczego to jest fakt o czasie, a nie o progach?
3. Dlaczego `ros2 topic hz` po stronie `/vacuum_pressure` nie pokaże
   zablokowanego monitora, choć system jest zepsuty?
4. Co dokładnie znaczy znacznik czasu przypisany wiadomości w nagraniu i dlaczego
   nie wolno liczyć z niego opóźnienia pomiar→werdykt?
5. Dlaczego liczenie offline z nagrania jest **dokładniejsze** niż liczenie
   na żywo, mimo że dane są te same?
6. Kiedy sięgasz po tracing zamiast po stempel? Podaj pytanie, na które
   stempel nie odpowie.
7. Co się dzieje z oknem `deque(maxlen=25)`, gdy monitor zaczyna gubić
   wiadomości — skraca się, wydłuża, czy zostaje?
8. Dlaczego „wielowątkowy executor" w `rclpy` nie znaczy „równoległy" i co
   z tego wynika dla decyzji Python kontra C++?

## Co przeczytać

- `https://docs.ros.org/en/jazzy/` — rozdziały o executorach i grupach
  callbacków; która grupa jest domyślna i czemu to ona robi sprzężenie z 09.5.
- `https://github.com/ros2/ros2_tracing` — źródło prawdy o tym, gdzie leżą
  punkty śledzenia i które warstwy są instrumentowane. Szybciej niż zgadywanie.
- Christophe Bédard, Ingo Lütkebohle, Michel Dagenais, *ros2_tracing:
  Multipurpose Low-Overhead Framework for Real-Time Tracing of ROS 2*
  (IEEE Robotics and Automation Letters, 2022) — po co to w ogóle powstało
  i jaki ma narzut; czyta się w godzinę.
- `https://design.ros2.org/` — artykuły o warstwach `rmw`/`rcl` i o modelu
  wykonania; dają słownik, bez którego nazwy zdarzeń w śladzie są bezużyteczne.
- `ros2 topic hz --help`, `ros2 topic delay --help`, `ros2 trace --help` — tak,
  to jest pozycja na liście lektur. Trzy minuty zamiast wieczoru zgadywania flag.

## Dziennik

    Co mnie zaskoczyło:

    Który składnik budżetu okazał się największy i czy zgadłem go
    przed pomiarem:

    Które narzędzie pokazało problem z zadania 09.4 jako pierwsze,
    a które najdokładniej — i dlaczego to nie to samo narzędzie:

    Co zjadło najwięcej czasu:

    Jedno zdanie, którego nie umiałbym napisać tydzień temu:

Dalej → [Etap 10 — Ewaluacja detektora na danych](./10-ewaluacja-na-danych.md)
