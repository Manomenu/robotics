# Etap 10 — Ewaluacja detektora na danych

> Umiesz powiedzieć, ile twój detektor pomija i o ile się spóźnia — z liczbą,
> mianownikiem i nazwą nagrania, na którym to policzyłeś. Przedtem umiałeś
> powiedzieć „u mnie działa".

| | |
|---|---|
| wejście | etap 03 (nagranie jest danymi) i etap 04 (logika detektora jest klasą bez ROS-a); `projects/grab-fail-detection/bags/chwyt-3-stany/` leży na dysku |
| czas | 3–4 wieczory: jeden na etykiety, jeden na stanowisko, jeden na siatkę, jeden na pogodzenie się z tym, że pierwsze liczby były za ładne |
| kończy się | w `projects/grab-fail-detection/NOTES.md` stoi wybrany punkt pracy — trzy liczby parametrów, osiągnięte metryki i zdanie, dlaczego akurat ten punkt |

## Po ludzku: co to jest w twoim świecie

| tutaj | u ciebie w backendzie | gdzie analogia pęka |
|---|---|---|
| etykiety (prawda o nagraniu) | oczekiwany wynik w fixture | fixture **piszesz**, etykietę musisz **zaobserwować** — i możesz się pomylić; etykieta ma własny błąd pomiaru |
| macierz pomyłek | tabela wyników zestawu testów | test ma dwa wyniki, detektor ma cztery klasy i jedna z nich to „nic nie powiedział" |
| metryka per-zdarzenie | precyzja i czułość alertu w monitoringu | zdarzenie w robocie **trwa**, ma początek, koniec i nie da się go powtórzyć — a spóźniony alert to inny wynik niż brak alertu |
| przemiatanie progów | strojenie cache'a, GC, rozmiaru puli | tam stroisz wydajność; tutaj stroisz to, co system **twierdzi, że widzi** — strojenie zmienia semantykę, nie tylko koszt |
| zbiór kontrolny | staging | staging postawisz drugi raz; drugiego popołudnia z tym samym przedmiotem i tą samą uszczelką już nie postawisz |
| złote nagranie z progiem | snapshot test | snapshot przypina bajty; tutaj przypinasz **metrykę z marginesem**, bo bajty i tak się zmienią |

## Po co to — czego bez tego nie da się zrobić

Otwórz `ws/src/grip_monitor/grip_monitor/grasp_monitor.py`. Są tam cztery
liczby, które decydują o wszystkim:

```python
self.frame = deque(maxlen=25)          # 25 próbek, czyli 0,5 s przy 50 Hz
...
if is_at_level(mean, 0):               # -1 < mean < 1   -> open
if mean < -1 and mean > -58:           # -58 < mean < -1 -> leak
if is_at_level(mean, -59):             # -60 < mean < -58 -> sealed
```

Żadna z nich nie ma uzasadnienia poza tym, że przy `gauss(0, 0.5)`
z `vacuum_sensor.py` wygląda rozsądnie. To jest w porządku jako pierwszy
strzał. Przestaje być w porządku w momencie, w którym ktoś zapyta „skąd
wiesz" — a zapyta, bo od tego zależy, czy cela zatrzymuje linię.

Najgorsze jest to, że te liczby mają konsekwencje, których **na wykresie nie
widać**, a da się je policzyć na kartce. Średnia z 25 próbek po skoku
prawdziwej wartości z `u` na `v` w `k`-tej próbce wynosi `((25-k)*u + k*v)/25`.
Podstaw poziomy z `vacuum_sensor.py` (0, −20, −59):

| przejście prawdziwe | średnia zmienia się o | pierwszy poprawny werdykt | co leci po drodze |
|---|---|---|---|
| `open` → `sealed` (0 → −59) | −2,36 na próbkę | po 25 próbkach = **500 ms** | 24 próbki werdyktu `leak`, czyli **480 ms fałszywego alarmu** |
| `open` → `leak` (0 → −20) | −0,8 na próbkę | po 2 próbkach = **40 ms** | nic |
| `sealed` → `open` (−59 → 0) | +2,36 na próbkę | po 25 próbkach = **500 ms** | znowu 24 próbki `leak` |
| `sealed` → `leak` (−59 → −20) | +1,56 na próbkę | po 1 próbce = **20 ms** | nic |
| `leak` → `sealed` (−20 → −59) | −1,56 na próbkę | po 25 próbkach = **500 ms** | nic, cała droga leży w paśmie `leak` |

Szum tego nie rozmywa: odchylenie średniej z 25 próbek to `0,5/√25 = 0,1`,
a średnia przy przejściu do `sealed` przesuwa się o 2,36 na próbkę — czyli
granicę przekracza z dokładnością do ułamka próbki.

Czytaj to jeszcze raz. **Wejście w `sealed` trwa 500 ms, a wyjście z `sealed`
20 ms.** Detektor jest o rząd i pół wielkości wolniejszy w jedną stronę niż
w drugą, każdy chwyt zaczyna się od pół sekundy fałszywego `leak`, a nikt
w tym repo tego nie zapisał. To jest dokładnie ten rodzaj wiedzy, który
bez ewaluacji zostaje w głowie autora i umiera razem z jego pamięcią.

Bez tego etapu nie umiesz odpowiedzieć na żadne z tych pytań:

- Ile chwytów na sto ten detektor pomija?
- Ile razy na minutę krzyczy bez powodu?
- Czy po zmianie okna z 25 na 15 będzie lepiej — i **w czym** lepiej?
- Czy zmiana, którą właśnie wprowadziłeś, czegoś nie zepsuła?

## Dlaczego to ciekawe

**Etykiety masz za darmo i jeszcze o tym nie wiesz.** Nagrywając
`chwyt-3-stany`, sam ustawiałeś parametr `state` przez
`scripts/dev/ros2/set-param.sh`. Byłeś generatorem prawdy. Wystarczyło ją
zapisać w drugim pliku i masz oznaczone nagranie za jedno przekierowanie
strumienia. W prawdziwym projekcie etykietowanie kosztuje więcej niż model —
ludzie siedzą i klikają ramki na wideo, po 30 sekund na sekundę nagrania.
To jest najtańsza prawda, jaką w życiu dostaniesz; szkoda ją zmarnować.

**Okno nie jest opóźnieniem, tylko filtrem.** Zdarzenie krótsze niż 25 próbek
jest dla tego detektora niewidzialne — nie „wykryte z opóźnieniem", tylko
nieobecne. Jeśli przedmiot ześlizguje się na 0,2 s, żadne strojenie progów
tego nie naprawi, bo średnia nigdy nie dojdzie do docelowego pasma. Progi
i okno to nie są dwa pokrętła tej samej rzeczy.

**Dokładność potrafi rosnąć, gdy detektor staje się gorszy.** Pokażesz to
sobie w zadaniu 10.5 na liczbach, nie na słowo honoru.

**Nie ma najlepszego progu.** Jest powierzchnia kompromisu, na której
przesuwasz się między fałszywymi alarmami a przeoczeniami, płacąc jednym
za drugie. Wybór punktu na niej to decyzja ekonomiczna, nie techniczna —
i to jest jedyna rzecz w tym etapie, której nie policzysz sam.

**Milczenie detektora jest klasą.** W `grasp_monitor.py` dla `mean >= 1`
i `mean <= -60` nie trafia żaden `if`, więc nie leci żaden werdykt.
Nikt tego nie zauważy, bo brak wiadomości wygląda tak samo jak wiadomość,
której nie czytasz.

## Dlaczego to trudne

1. **Etykiety też mają błąd pomiaru.** `ros2 param set` robi discovery, zanim
   parametr dojdzie do węzła. Zmierz to u siebie:
   `time scripts/dev/ros2/set-param.sh /vacuum_sensor state sealed`. Jeśli
   wyjdzie rząd setek milisekund, twoja etykieta jest niepewna w tej samej
   skali, w której mierzysz 500 ms opóźnienia detekcji. Prawda jest mniej
   dokładna niż rzecz, którą nią oceniasz — i to jest normalna sytuacja
   w ewaluacji, którą trzeba nazwać, a nie zamieść.
2. **Definicja zdarzenia jest hiperparametrem.** Czy 480 ms werdyktu `leak`
   w środku przejścia to fałszywy alarm, czy szum przejścia? Zależy od tego,
   jak długo stan musi się utrzymać, żeby liczyć się jako zdarzenie. Zmiana
   tej jednej liczby zmienia precyzję o kilkadziesiąt punktów, a to nie jest
   zmiana w detektorze — tylko w mierniku.
3. **Klasy są niezbalansowane i będą coraz bardziej.** W `chwyt-3-stany`
   trzy stany trwają mniej więcej po tyle samo, bo tak je nagrałeś. W hali
   cela trzyma przedmiot przez większość czasu, a gubi go raz na kilkaset
   chwytów. Każda metryka liczona „na próbkę" pójdzie wtedy w stronę klasy
   większościowej i przestanie cokolwiek znaczyć.
4. **Twoja ocena offline nie jest tym samym przebiegiem co live.** Metadane
   `chwyt-3-stany` pokazują 1062 wiadomości na `/vacuum_pressure` i dokładnie
   1062 na `/grasp_verdict`. Skoro `grasp_monitor.py` milczy, dopóki nie
   uzbiera 25 próbek, to znaczy, że w chwili startu nagrania jego `deque`
   było **już pełne** — monitor chodził wcześniej. Twoja klasa w teście
   startuje z pustym oknem, więc pierwsze 24 próbki dadzą `None` i macierz
   pomyłek dostanie 24 sztuczne wpisy, których w rzeczywistości nie było.
5. **Trzy nagrania z jednego popołudnia to jedno nagranie w trzech
   egzemplarzach.** Ten sam przedmiot, ta sama uszczelka, ta sama temperatura,
   ten sam `gauss(0, 0.5)` wpisany na sztywno w `vacuum_sensor.py`. Strojenie
   na tym daje liczby, które nie przeżyją pierwszego kontaktu z halą.
6. **Wiedza plemienna.** Nigdzie w dokumentacji ROS-a nie ma zdania „okno
   uśredniające wprowadza opóźnienie asymetryczne względem progów". Jest za to
   w głowie każdego, kto raz to przeżył. Ten etap polega głównie na tym, żeby
   przenieść takie zdania z głowy do pliku z liczbami.

## Model pojęciowy

### Dwie osie czasu

Cała ewaluacja to porównanie dwóch osi czasu o wspólnym zegarze:

    prawda      |---- open ----|-------- sealed --------|---- leak ----|
    przewidywanie |--open--|?|-leak-|------ sealed ------|--- leak ----|
                           ^  ^                          ^
                           |  |                          `- 20 ms spóźnienia
                           |  `- 480 ms fałszywego alarmu
                           `- rozgrzewka okna, brak werdyktu

Wszystko inne — macierz, precyzja, opóźnienie — jest tylko innym sposobem
patrzenia na te dwie linijki. Jeśli umiesz je narysować dla swojego nagrania,
resztę policzysz w dwudziestu linijkach numpy.

### Stanowisko: dlaczego to ma działać w sekundach

    bag (mcap)  --[raz]-->  dane/*.csv  -->  czysta klasa detektora  -->  oś przewidywań
                                                                              |
                                          etykiety/*.csv --> porównanie <-----'

Wyciąg z baga robisz **raz** i zapisujesz jako zwykły CSV. Od tego momentu
ewaluacja nie dotyka ROS-a: 1062 próbki razy 120 kombinacji parametrów to
sto kilkadziesiąt tysięcy operacji, czyli ułamek sekundy. Cała pętla
„zmień próg → zobacz metryki" chodzi bez uruchamiania jednego węzła.

To jest moment, w którym spłaca się etap 04. Gdyby logika nadal siedziała
w `on_measurement`, każda kombinacja parametrów wymagałaby postawienia
dwóch węzłów, odczekania 21 sekund i zebrania wyników z topiku — 120 kombinacji
to 42 minuty zamiast pół sekundy, i to przy założeniu, że nic nie przegubi
wiadomości po drodze.

### Miara per-próbka

Dla każdej z 1062 próbek porównujesz stan przewidziany ze stanem prawdziwym.
Wynik: jedna liczba od 0 do 1. Łatwa, kusząca i myląca z trzech powodów:
klasy są niezbalansowane, stany trwają sekundami (więc jedna pomyłka liczy
się 25 razy, bo obejmuje 25 próbek), a pytanie biznesowe brzmi zupełnie
inaczej.

### Miara per-zdarzenie

Zdarzenie to **przejście** na osi: „w chwili t stan zmienił się z X na Y".
Prawdziwych zdarzeń w `chwyt-3-stany` są dwa. Dla każdego pytasz:

- czy detektor je zauważył w oknie tolerancji (np. do 1,0 s po fakcie)?
- ile razy zgłosił przejście, którego nie było?
- z jakim opóźnieniem zgłosił te, które były?

| | per-próbka | per-zdarzenie |
|---|---|---|
| co liczy | zgodność stanu w każdej chwili | wykrycie zmian stanu |
| mianownik | 1062 próbki | 2 zdarzenia (w twoim nagraniu) |
| wrażliwość na niezbalansowanie | bardzo duża | żadna |
| jak karze 0,5 s zwłoki | 25 błędnych próbek z 1062, czyli 2,4 % | jedna liczba: opóźnienie = 0,5 s |
| jak karze migotanie | prawie wcale, jeśli migocze krótko | brutalnie — każde mignięcie to fałszywy alarm |
| odpowiada na pytanie | „jak często stan się zgadzał" | „czy dowiem się, że przedmiot spadł, i kiedy" |
| kiedy używać | do diagnozy: gdzie na osi czasu jest źle | do decyzji: czy to wdrażać |

**Mylenie tych dwóch to główny błąd początkujących** i rozpoznaje się go po
jednym objawie: ktoś podaje jedną liczbę w procentach bez mianownika.

### Liczbowy przykład, w którym 97 % nic nie znaczy

Nagraj `chwyt-realistyczny`: cela trzyma przedmiot przez całe 21 sekund
i trzy razy gubi go na 0,2 s (10 próbek). To jest 1032 próbki `sealed`
i 30 próbek `open`.

| detektor | trafność per-próbka | wykryte zdarzenia | fałszywe alarmy | koszt |
|---|---|---|---|---|
| „zawsze `sealed`" (10 znaków kodu) | **97,2 %** (1032/1062) | **0 / 3** | 0 | 1800 s |
| twój, okno 25 próbek | 90,4 % (960/1062) | **0 / 3** | 3 × `leak` | 1890 s |

Stała odpowiedź `sealed` wypada **lepiej** niż detektor, nad którym siedziałeś
wieczór. Nie dlatego, że jest lepsza — dlatego, że miara jest zła. A twój
detektor gubi te zdarzenia z powodu, którego żaden próg nie naprawi: 0,2 s
to 10 próbek, okno ma 25, więc średnia dochodzi najwyżej do −35,4 i nigdy
nie wpada w pasmo `open`. Zamiast tego przez 34 próbki (680 ms) melduje `leak`.

Kolumna „koszt" pochodzi z następnej sekcji.

### Macierz pomyłek: trzy klasy plus milczenie

Wiersze to prawda, kolumny to werdykt. Kolumna `unknown` istnieje, bo
`grasp_monitor.py` naprawdę potrafi nic nie powiedzieć: przy rozgrzewce okna
i w martwych strefach progów. Wiersza `unknown` nie ma — prawda zawsze jakaś
jest.

Poniższa macierz jest **wyliczona z arytmetyki okna** dla nagrania
podzielonego na `open` (0–7 s), `sealed` (7–14 s), `leak` (14–21,2 s),
z detektorem startującym z pustym oknem. Twoje liczby będą inne, bo twoje
etykiety są inne — ale kształt będzie ten sam:

|  | `open` | `leak` | `sealed` | `unknown` | suma |
|---|---|---|---|---|---|
| **prawda `open`** | 326 | 0 | 0 | 24 | 350 |
| **prawda `sealed`** | 0 | 24 | 326 | 0 | 350 |
| **prawda `leak`** | 0 | 361 | 1 | 0 | 362 |

Trafność per-próbka: `(326+326+361)/1062 = 95,4 %`. Ładnie. A teraz przeczytaj
tę samą tabelę per-zdarzenie: dwa prawdziwe przejścia, oba wykryte (po 500 ms
i po 20 ms), plus jeden fałszywy alarm `leak` trwający 480 ms. Precyzja
zdarzeń: 2/3. Ta sama macierz, dwie zupełnie inne opinie o tym samym kodzie.

### Precyzja, czułość, F1 — i dlaczego F1 tu kłamie

Dla klasy „zgubiony przedmiot" (przejście `sealed` → `open`):

| metryka | wzór | co znaczy **tutaj** |
|---|---|---|
| precyzja | `TP / (TP + FP)` | z alarmów, które podniosłeś, ile było prawdziwych — czyli jak często zatrzymujesz celę bez powodu |
| czułość | `TP / (TP + FN)` | ze zgubień, które się zdarzyły, ile złapałeś — czyli jak często przedmiot ląduje na podłodze, a system tego nie wie |
| F1 | `2PR / (P + R)` | średnia harmoniczna obu, **przy założeniu, że oba błędy kosztują tyle samo** |

To ostatnie założenie jest w tej celi fałszywe:

- **fałszywy alarm** o zgubieniu → cela staje na 30 sekund, operator patrzy,
  wznawia;
- **przeoczone zgubienie** → przedmiot na podłodze, przestój 10 minut,
  a w złym wariancie uszkodzony przedmiot albo człowiek schylający się
  po niego pod pracującą maszyną.

Stosunek kosztów to 20:1. Metryka, która traktuje te błędy jednakowo, jest
metryką dla kogoś innego. Zamiast F1 licz **koszt w sekundach przestoju**:

```python
KOSZT_FP_S = 30.0    # fałszywy alarm: przestój celi
KOSZT_FN_S = 600.0   # przeoczenie: przedmiot na podłodze

koszt = KOSZT_FP_S * fp + KOSZT_FN_S * fn
```

Dwie liczby na górze tego bloku są jedyną rzeczą w całym etapie, której nie
wolno ci wymyślić samemu — przychodzą od kogoś, kto zna halę. Zapisz je
w `NOTES.md` razem z nazwiskiem źródła i datą, bo za pół roku nikt nie będzie
pamiętał, skąd się wzięły, a cała twoja optymalizacja na nich stoi.
(Ta sama myśl w wersji akademickiej nazywa się `F-beta` z `beta > 1`;
koszt w sekundach jest uczciwszy, bo nikt nie udaje, że rozumie `beta`.)

### Opóźnienie jako metryka jakości

Werdykt spóźniony o sekundę nie jest wolniejszy — jest **inny**, bo przedmiot
zdążył już spaść. Dlatego opóźnienie detekcji raportujesz razem z czułością,
nigdy osobno, i zawsze z ogonem:

| co raportować | dlaczego |
|---|---|
| mediana | typowy przypadek, odporna na pojedyncze dziwactwa |
| p95 i maksimum | bo to ogon decyduje, czy coś spadnie; średnia zaokrągli ci go do zera |
| liczba zdarzeń, na których to policzono | „mediana 0,3 s" z dwóch zdarzeń to nie jest mediana, tylko anegdota |

W [etapie 09](./09-latencja-i-tracing.md) mierzyłeś drogę wiadomości przez
system — callback, executor, DDS — i chodziło o milisekundy; tutaj mierzysz,
ile trwało samo **rozpoznanie**, wychodzi 500 ms, i widać gołym okiem, że
okno 25 próbek jest w tej sumie składnikiem dominującym o dwa rzędy wielkości.

### Cztery pokrętła

| hiperparametr | dziś w kodzie | co robi | czym płacisz |
|---|---|---|---|
| szerokość okna `N` | 25 (`deque(maxlen=25)`) | uśrednia szum | opóźnieniem i ślepotą na krótkie zdarzenia |
| margines progu | ±1 (`is_at_level`) | jak blisko poziomu trzeba być | wąski → milczenie w martwej strefie; szeroki → mylenie klas |
| histereza | **brak** | inny próg na wejściu w stan i na wyjściu | opóźnieniem wyjścia ze stanu |
| minimalny czas trwania | **brak** | ile próbek stan musi się utrzymać, zanim zostanie ogłoszony | opóźnieniem, ale zabija migotanie i fałszywe `leak` przy przejściach |

Dwa ostatnie nie istnieją w `grasp_monitor.py` i to jest największa
pojedyncza dziura w tym detektorze — bez nich nie da się odróżnić przejścia
od stanu.

### Nie ma najlepszego progu

Gdy policzysz metryki dla całej siatki, zobaczysz, że kombinacje układają się
we **front Pareto**: dla każdej liczby fałszywych alarmów istnieje najlepsza
osiągalna czułość i odwrotnie. Nie da się poprawić jednego, nie psując
drugiego — to nie jest wada twojego kodu, tylko właściwość problemu.

Mało tego, to nie jest krzywa, tylko powierzchnia: okno handluje opóźnieniem
przeciwko obu pozostałym osiom. Do krzywej sprowadza się dopiero wtedy, gdy
zadeklarujesz, ile opóźnienia akceptujesz. Wtedy — i tylko wtedy — wybór
punktu jest jednoznaczny, bo minimalizujesz koszt w sekundach.

**Wniosek, którego się nie spodziewasz: strojenie progu nie jest zadaniem
technicznym.** Techniczna jest siatka. Wybór punktu na froncie to pytanie
„ile kosztuje minuta przestoju kontra przedmiot na podłodze", i odpowiada
na nie kierownik produkcji, nie ty. Twoja robota polega na tym, żeby postawić
przed nim front i nie udawać, że jest tam jeden punkt.

### Przetrenowanie na własnym popołudniu

Masz trzy nagrania, jeden przedmiot, jedną temperaturę i szum wpisany
na sztywno jako `gauss(0, 0.5)`. Dostrojenie do tego da liczby, które
w hali się nie powtórzą. Trzy rzeczy, które to ograniczają:

1. **Podział na zbiór strojenia i kontrolny.** Siatkę przemiatasz na
   `strojenie/`, a wybrany punkt sprawdzasz na `kontrola/` — raz. Jeśli po
   zobaczeniu wyniku wracasz i poprawiasz, `kontrola/` właśnie stała się
   drugim zbiorem strojenia i potrzebujesz trzeciego. Ta zasada jest
   nieprzyjemna dokładnie dlatego, że działa.
2. **Świadome dokręcanie różnorodności.** Nagrywaj rzeczy, które ci się nie
   podobają: inny przedmiot, wolniejszy i szybszy ruch, nieszczelność
   narastającą zamiast skokowej, przeciek na krawędzi (podciśnienie spada
   powoli), przedmiot ześlizgujący się na 0,2 s, słabszą pompę.
3. **Rejestr tego, czego w danych NIE MA.** Osobna sekcja w `NOTES.md`.
   To jest najtańszy dokument w projekcie i jedyny, który chroni cię przed
   zdaniem „przecież testowaliśmy".

### Złote nagrania i próg regresji

Wybierasz 3–5 nagrań, które reprezentują to, co ma działać. Zapisujesz dla
nich osiągnięte metryki jako **progi z marginesem** i od tej chwili każda
zmiana detektora, która pogarsza czułość poniżej progu, zapala się na czerwono
u ciebie, zamiast wyjść w hali. Progi, nie dokładne wartości — dokładne
wartości trzymasz obok, w `NOTES.md`, żeby widzieć dryf.

```yaml
# projects/grab-fail-detection/zlote/progi.yaml
punkt_pracy:
  okno: 15
  margines: 2.0
  min_probek: 5
nagrania:
  chwyt-3-stany:
    sha256: <suma pliku .mcap>
    czulosc_min: 1.00
    falszywe_na_minute_max: 0.5
    mediana_opoznienia_s_max: 0.35
```

Mechanizm uruchamiania tego przy każdym pushu jest w
[etapie 11](./11-ci-i-awarie.md); tutaj wystarczy, że test przechodzi lokalnie
i umie zaświecić na czerwono.

### Gdzie to mieszka w repo

`AGENTS.md` mówi wprost: `ws/src/` to pakiety ROS-a, `projects/<nazwa>/` to
„notatki, analiza offline, dane danego projektu". Ewaluacja jest analizą
offline i nie ma w niej ani jednego importu `rclpy` poza wyciągiem z baga,
więc **nie jest pakietem ROS-a**:

    projects/grab-fail-detection/
      NOTES.md            decyzje i ich uzasadnienie       -> git
      etykiety/*.csv      prawda o nagraniach              -> git
      zlote/progi.yaml    punkt pracy + progi regresji     -> git
      ewaluacja/*.py      stanowisko                       -> git
      wyniki/*.csv        tabele przemiatania              -> git
      wyniki/*.png        wykresy                          -> zwykle poza gitem
      dane/*.csv          wyciąg z bagów                   -> poza gitem
      bags/               nagrania                         -> poza gitem

Podział przebiega w jednym miejscu: **co da się odtworzyć, tego nie
commitujesz; czego nie da się odtworzyć, to commitujesz.** `dane/` odtworzysz
z baga jedną komendą. Etykiet nie odtworzysz nigdy, bo powstały w chwili,
gdy ty stałeś przy klawiaturze i wiedziałeś, co robisz — dlatego to jedyny
artefakt tego etapu, który naprawdę musi być w gicie. Dopisz `projects/*/dane/`
do `.gitignore`; `**/bags/` i `*.mcap` już tam są.

Cena tego podziału: nagranie i etykiety rozjeżdżają się przy pierwszym
`git clean`. Dlatego w pliku etykiet trzymasz sumę SHA-256 pliku `.mcap` —
żebyś wiedział, że te etykiety opisują **to** nagranie, a nie drugie
podejście z tego samego wieczora.

## Zadania

### Zadanie 10.1 — Etykiety obok nagrania (rdzeń)

**Cel:** zapisać prawdę o nagraniu w chwili, w której jeszcze ją znasz.

Dołóż do `.devcontainer/Containerfile` to, czego brakuje (nigdy `apt install`
w działającym kontenerze — `AGENTS.md` mówi o tym wprost):

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3-matplotlib python3-pandas \
 && rm -rf /var/lib/apt/lists/*
```

`numpy` jest już w obrazie, bo używa go `grasp_monitor.py`.

Nagraj nowy przebieg i zapisuj prawdę w locie. Kontener dzieli jądro
z Fedorą, więc `date` i stemple w bagu idą z tego samego `CLOCK_REALTIME` —
nie ma przesunięcia do skorygowania:

```bash
etykieta() {
  scripts/dev/ros2/set-param.sh /vacuum_sensor state "$1"
  printf '%s %s\n' "$(date +%s.%N)" "$1" >> /tmp/surowe-etykiety.txt
}

etykieta open    # i czekasz
etykieta sealed
etykieta leak
```

Potem zamień to na plik interwałów w `projects/grab-fail-detection/etykiety/`:

```csv
# bag=chwyt-3-stany sha256=...
t_start_ns,t_end_ns,stan,zrodlo
1788702196873060456,1788702203910000000,open,snap
1788702203910000000,1788702210950000000,sealed,snap
```

Kolumna `zrodlo` jest ważniejsza, niż wygląda. `set-param` oznacza „stempel
z `date`, niepewny o czas discovery". `snap` oznacza „dociągnięty do skoku
w surowym sygnale". Dociągnięcie jest półautomatyczne i uczciwe: skok
o 59 jednostek przy szumie `σ = 0,5` to 118 odchyleń, więc próbka, w której
nastąpił, jest jednoznaczna — a korzystasz przy tym z wiedzy o **generatorze**
(poziomy 0, −20, −59), nie o detektorze. Napisz skrypt, który bierze niepewne
stemple z `date` i przesuwa każdy do najbliższej próbki, w której surowy sygnał
zmienia poziom o więcej niż 10.

**Gotowe, gdy:** masz plik CSV, w którym suma długości interwałów pokrywa
całe nagranie bez dziur, a różnica między stemplem z `date` a stemplem po
dociągnięciu jest wypisana na ekranie — i wiesz, ile wynosi.

### Zadanie 10.2 — Stanowisko ewaluacyjne bez ROS-a (rdzeń)

**Cel:** z nagrania zrobić oś przewidywań w ułamku sekundy, bez uruchamiania
czegokolwiek.

Raz wyciągnij próbki do CSV (czytanie baga masz z
[etapu 03](./03-bagi-jako-dane.md), tutaj to cztery linijki):

```python
from rclpy.serialization import deserialize_message
from rosbag2_py import ConverterOptions, SequentialReader, StorageOptions
from rosidl_runtime_py.utilities import get_message


def wyciag(katalog_baga: str, topic: str) -> list[tuple[int, float]]:
    reader = SequentialReader()
    reader.open(
        StorageOptions(uri=katalog_baga, storage_id='mcap'),
        ConverterOptions('', ''),
    )
    typ = get_message('std_msgs/msg/Float32')
    probki = []
    while reader.has_next():
        nazwa, dane, stamp_ns = reader.read_next()
        if nazwa == topic:
            probki.append((stamp_ns, deserialize_message(dane, typ).data))
    return probki
```

Od tego momentu `dane/chwyt-3-stany.csv` jest jedynym wejściem i nic w tym
etapie nie importuje już ROS-a. Podepnij czystą klasę detektora z
[etapu 04](./04-piramida-testow.md) — zakładam interfejs
`detektor.push(wartosc) -> str | None`; jeśli nazwałeś to inaczej, podmień:

```python
def os_przewidywan(probki, detektor):
    """Jeden werdykt na próbkę; None = detektor milczy."""
    return [(t_ns, detektor.push(wartosc)) for t_ns, wartosc in probki]
```

**Gotowe, gdy:** `time python3 ewaluacja/os.py` kończy się poniżej sekundy,
a wydruk pierwszych 30 wierszy pokazuje 24 razy `None`, potem pierwszy
werdykt — czyli widzisz rozgrzewkę okna, której nie było w nagraniu
(patrz „Dlaczego to trudne", punkt 4).

### Zadanie 10.3 — Dwie miary, macierz pomyłek, opóźnienie (rdzeń)

**Cel:** policzyć obie miary na tych samych danych i zobaczyć, że mówią
co innego.

Per-próbka: dla każdej próbki znajdź stan prawdziwy z pliku etykiet i zbuduj
macierz 3×4 (wiersze — prawda, kolumny — werdykt plus `unknown`). Wypisz ją
jako tabelę z sumami wierszy; policz trafność.

Per-zdarzenie: zamień obie osie na listy przejść i dopasuj je do siebie.

```python
def zdarzenia(os, min_probek):
    """(t_ns, stan_do) dla stanów, które utrzymały się min_probek."""
    wynik, biezacy, licznik, t_od = [], None, 0, None
    for t_ns, stan in os:
        if stan == biezacy:
            licznik += 1
        else:
            biezacy, licznik, t_od = stan, 1, t_ns
        if licznik == min_probek and stan is not None:
            wynik.append((t_od, stan))
    return wynik


def dopasuj(prawdziwe, wykryte, tolerancja_ns):
    zajete, opoznienia = set(), []
    for t_p, stan_p in prawdziwe:
        for i, (t_w, stan_w) in enumerate(wykryte):
            if i in zajete or stan_w != stan_p:
                continue
            if t_p <= t_w <= t_p + tolerancja_ns:
                zajete.add(i)
                opoznienia.append((t_w - t_p) / 1e9)
                break
    tp = len(zajete)
    return tp, len(wykryte) - tp, len(prawdziwe) - tp, opoznienia
```

Trzy decyzje w tym kodzie są arbitralne i musisz je zapisać w `NOTES.md`:
dopasowanie tylko po stanie docelowym (bo stan źródłowy detektor często myli),
tolerancja liczona **tylko do przodu** (wykrycie przed faktem to nie wykrycie,
tylko fałszywy alarm) i przypisanie jeden-do-jednego (bez tego migoczący
detektor zbiera wiele trafień za jedno zdarzenie).

Opóźnienie: z listy `opoznienia` policz medianę, p95 i maksimum — i wypisz
obok liczbę zdarzeń, na których to policzyłeś.

**Gotowe, gdy:** masz na ekranie macierz pomyłek z niezerową kolumną
`unknown`, trafność per-próbka powyżej 90 %, a obok — precyzję zdarzeń
poniżej 100 %, bo złapałeś fałszywy `leak` w przejściu `open` → `sealed`.
Dwie liczby o tym samym kodzie, obie prawdziwe.

### Zadanie 10.4 — Przemiatanie siatki i wybór punktu pracy (rdzeń)

**Cel:** zobaczyć front kompromisu i świadomie wybrać na nim punkt.

```python
import itertools

siatka = itertools.product(
    [5, 10, 15, 25, 40, 60],    # szerokość okna
    [0.5, 1.0, 2.0, 3.0, 5.0],  # margines progu
    [0, 3, 5, 10],              # minimalny czas trwania stanu
)
```

120 kombinacji. Dla każdej policz: czułość zdarzeń, fałszywe alarmy na minutę,
medianę i p95 opóźnienia, trafność per-próbka i koszt w sekundach. Zapisz do
`wyniki/siatka.csv` (pandas wystarczy; unikaj `df.to_markdown()` — potrzebuje
pakietu `tabulate`, którego nie ma w obrazie).

Wykres: fałszywe alarmy na osi X, przeoczenia na osi Y, rozmiar punktu =
mediana opóźnienia. Kontener nie ma `DISPLAY`, więc rysujesz do pliku:

```bash
MPLBACKEND=Agg python3 ewaluacja/siatka.py
```

(Alternatywa `matplotlib.use('Agg')` przed `import matplotlib.pyplot` wywoła
`E402` u ruffa, bo `ruff.toml` ma włączone `E` — zmienna środowiskowa omija
ten spór.)

**Gotowe, gdy:** w `NOTES.md` stoi akapit w tej formie: „wybrałem okno 15,
margines 2,0, minimalny czas 5 próbek, bo daje czułość 1,00 przy 0,3 fałszywego
alarmu na minutę i medianie opóźnienia 0,30 s; okno 10 dawało o 0,08 s mniej
opóźnienia, ale 1,2 fałszywego alarmu na minutę, czyli 27 s przestoju więcej
na godzinę" — z **twoimi** liczbami. I obok zdanie o tym, których punktów
frontu nie wybrałeś i dlaczego.

### Zadanie 10.5 — Zepsuj to: detektor, który zawsze mówi „sealed" (rdzeń, obowiązkowe)

**Cel:** sprawdzić, która z twoich metryk daje się oszukać kodem bez logiki.

Wariant A. Napisz detektor i przepuść go przez całe stanowisko:

```python
class ZawszeSealed:
    def push(self, _wartosc):
        return 'sealed'
```

Nagraj `chwyt-realistyczny` z sekcji o 97 % — długie `sealed`, trzy krótkie
zgubienia po 0,2 s — bo na zbalansowanym `chwyt-3-stany` ten detektor wyjdzie
na 33 % i pułapka się nie pokaże. **Ta pułapka wymaga realistycznego rozkładu
klas i dlatego musisz go sobie sam nagrać.**

Przejrzyj wyniki i wypisz, które metryki wyglądają przyzwoicie. Zwróć uwagę
na trzy:

- trafność per-próbka: ~97 %;
- fałszywe alarmy: **zero** — detektor nigdy nie zgłasza przejścia, więc
  nie ma czego zgłosić fałszywie;
- precyzja: `0/0`, czyli `nan` albo wyjątek — a naiwny raport wydrukuje
  „precyzja: —", co ktoś przeczyta jako „bez zastrzeżeń".

Wariant B. Przemieć siatkę z 10.4 na jednym nagraniu, weź najlepszy punkt
i policz go na drugim, nietykanym. Zapisz obie liczby obok siebie.

**Gotowe, gdy:** masz w `NOTES.md` zdanie, której metryce wolno ci ufać
samodzielnie (podpowiedź: żadnej — ufasz **parze** czułość zdarzeń
i fałszywe alarmy na minutę, zawsze z mianownikami), oraz różnicę między
wynikiem na zbiorze strojenia a wynikiem na kontrolnym wyrażoną w punktach
procentowych. Jeśli ta różnica wynosi zero, sprawdź, czy naprawdę użyłeś
dwóch różnych nagrań.

### Zadanie 10.6 — Złote nagrania i próg regresji (rdzeń)

**Cel:** zamienić dzisiejszy wynik w barierę, której jutrzejsza zmiana nie
przejdzie po cichu.

Wybierz 3–5 nagrań pokrywających różne przypadki, zapisz `zlote/progi.yaml`
z osiągniętymi metrykami minus margines, i napisz test (styl masz z
[etapu 04](./04-piramida-testow.md)), który wczytuje progi, przemiela złote
nagrania i porównuje. Potem — zgodnie z zasadą 3 z roadmapy — **zepsuj
detektor i zobacz, że test padnie**: zmień okno z 15 na 60 i sprawdź, czy
zapala się na opóźnieniu, a nie tylko na czułości.

**Gotowe, gdy:** test świeci na czerwono po zmianie okna i na zielono po jej
cofnięciu, a komunikat błędu podaje, która metryka i o ile przekroczyła próg
— nie samo `assert False`.

### Zadanie 10.7 — Drugi sygnał: czy dwa biją jeden (rozszerzenie)

**Cel:** sprawdzić, czy dołożenie sygnału poprawia detekcję i ile to kosztuje
w opóźnieniu.

Weź prąd chwytaka z symulacji z [etapu 08](./08-tf2-urdf-ros2-control.md),
nagraj go razem z ciśnieniem i doklej do stanowiska. Uwaga na dwie rzeczy:
sygnały mają różne częstotliwości i różne stemple, więc najpierw sprowadź
je na wspólną siatkę czasu (`np.interp` wystarczy — offline nie potrzebujesz
`message_filters`). Potem porównaj trzy reguły:

| reguła | efekt |
|---|---|
| samo ciśnienie | punkt odniesienia z 10.4 |
| ciśnienie **i** prąd (AND) | mniej fałszywych alarmów, więcej przeoczeń |
| ciśnienie **lub** prąd (OR) | odwrotnie |

**Gotowe, gdy:** masz na jednym wykresie trzy fronty Pareto i potrafisz
powiedzieć, czy wolniejszy sygnał podniósł dolną granicę opóźnienia — bo
fuzja nie może być szybsza od najwolniejszego składnika, a ten, który
przychodzi z 10 Hz, dokłada do mediany co najmniej 50 ms.

## Pułapki

| objaw | przyczyna | co zrobić |
|---|---|---|
| `plt.show()` nic nie pokazuje, w logu „FigureCanvasAgg is non-interactive" | kontener nie ma `DISPLAY` ani montowania `/tmp/.X11-unix` — sprawdzone w `podman inspect` | `MPLBACKEND=Agg` i `plt.savefig()` do `wyniki/`; GUI to osobny temat z etapu 05 |
| offline dostajesz inne liczby niż `/grasp_verdict` z baga | w nagraniu monitor miał już pełne okno (1062 = 1062), twoja klasa startuje z pustym `deque` | odrzuć pierwsze 24 próbki albo dolej 24 próbki rozgrzewkowe — i zapisz, który wariant wybrałeś |
| precyzja wychodzi `nan`, a raport wygląda dobrze | `TP + FP = 0`, czyli detektor nie zgłosił ani jednego alarmu | zawsze drukuj mianowniki; `nan` przy precyzji to alarm, nie brak danych |
| etykiety przesunięte o ułamek sekundy względem sygnału | `ros2 param set` robi discovery, zanim parametr dojdzie do węzła | dociągnij etykietę do skoku w surowym sygnale (zadanie 10.1) i zapisz `zrodlo=snap` |
| czułość 1,00, a w hali gubi przedmioty | strojenie i sprawdzanie na tym samym nagraniu | podział `strojenie/` i `kontrola/`, kontrola oglądana raz na zmianę |
| werdykt „miga" między `leak` a `sealed` | poziom prawdziwy leży blisko progu, szum przechodzi tam i z powrotem; w kodzie nie ma ani histerezy, ani minimalnego czasu trwania | dołóż oba pokrętła i wstaw je do siatki z 10.4 |
| zmniejszenie okna z 25 na 10 poprawiło wszystko | przy `gauss(0, 0.5)` z `vacuum_sensor.py` szumu prawie nie ma, więc uśrednianie nic nie kosztuje i nic nie daje | podnieś szum w symulatorze przed strojeniem, inaczej wybierzesz okno na podstawie danych, które nie istnieją |
| detektor milczy i nikt tego nie zauważył | martwa strefa w `grasp_monitor.py`: dla `mean >= 1` i `mean <= -60` żaden `if` nie trafia | dodaj jawną gałąź `unknown` i licz ją jako klasę w macierzy |
| etykiety zostały, nagranie zniknęło | `**/bags/` i `*.mcap` są w `.gitignore`, etykiety nie | trzymaj sumę SHA-256 `.mcap` w nagłówku pliku etykiet; kopiuj nagrania poza repo |
| `df.to_markdown()` rzuca `ImportError` | to wymaga pakietu `tabulate`, którego nie ma w obrazie | `to_csv()` albo `to_string()`; jeśli naprawdę chcesz — `python3-tabulate` do `Containerfile` |

## Sprawdź się

1. Dlaczego trafność per-próbka może **wzrosnąć**, gdy detektor staje się
   gorszy? Podaj konkretną parę detektorów z tego etapu.
2. Dlaczego okno 25 próbek nie zobaczy zgubienia trwającego 0,2 s i dlaczego
   żadna zmiana progu tego nie naprawi?
3. Skąd się bierze asymetria: wejście w `sealed` trwa 500 ms, a wyjście z niego
   20 ms? Która linijka kodu za to odpowiada?
4. Detektor ma zero fałszywych alarmów. Dlaczego to nie jest dobra wiadomość
   i jakiej drugiej liczby musisz zażądać, zanim się ucieszysz?
5. Dlaczego F1 jest tutaj złą metryką i czym ją zastępujesz? Skąd biorą się
   liczby, których potrzebuje zamiennik?
6. Dlaczego definicja „zdarzenia" jest hiperparametrem, a nie faktem? Podaj
   dwie decyzje z zadania 10.3, które zmieniają wynik, nie zmieniając detektora.
7. Które składniki drogi „fizyka → werdykt" mierzyłeś w etapie 09, a który
   dokłada ten etap? Który z nich jest większy i o ile rzędów wielkości?
8. Dlaczego plik etykiet idzie do gita, a `dane/*.csv` nie — mimo że oba są
   małymi CSV-kami?

## Co przeczytać

- `https://docs.ros.org/en/jazzy/` — `rosbag2_py`, ale tylko tyle, żeby wyjąć
  próbki; reszta tego etapu ROS-a nie potrzebuje i to jest jego zaleta.
- `https://scikit-learn.org/stable/`, rozdział „Metrics and scoring" —
  definicje precyzji, czułości i `F-beta` oraz akapit o tym, kiedy `accuracy`
  kłamie. Czytasz definicje, biblioteki nie instalujesz: dwadzieścia linijek
  numpy wystarczy i lepiej rozumiesz, co liczysz.
- Davis, Goadrich, *The Relationship Between Precision-Recall and ROC Curves*
  (ICML 2006) — dlaczego przy niezbalansowanych klasach krzywa ROC wygląda
  ładnie, a krzywa precyzja-czułość mówi prawdę. Sześć stron, twoja sytuacja.
- Google SRE Workbook, rozdział o alertowaniu na SLO (`https://sre.google/books/`)
  — precyzja i czułość alertu to dokładnie ta sama matematyka co tutaj, tylko
  z twojego poprzedniego życia; dobre do przetarcia intuicji.
- `https://matplotlib.org/stable/` — backend Agg i rysowanie bez ekranu,
  czyli jedyna rzecz z matplotliba, której naprawdę potrzebujesz w kontenerze.
- `projects/grab-fail-detection/NOTES.md` — własne wpisy z dnia 1. Po tym
  etapie przeczytasz je inaczej i to jest najlepszy miernik tego, czy coś
  z niego wyniosłeś.

Jedno zdanie na zapas, żeby wiedzieć, gdzie kończy się ten etap: próg na jednej
liczbie wystarcza dokładnie tak długo, jak długo klasy są w tej jednej liczbie
rozdzielone — gdy porowaty przedmiot trzymany dobrze zacznie dawać to samo
ciśnienie co szczelny trzymany źle, żadne strojenie nie pomoże, zacznie się
osobna historia o cechach i modelu, a wszystko, co zbudowałeś tutaj, stanie się
narzędziem do jej oceniania.

## Dziennik

    Data:

    1. Która metryka najbardziej mnie zaskoczyła i dlaczego akurat ta?

    2. Ile czasu zjadło liczenie metryk, a ile kłótnia z samym sobą o to,
       co w ogóle liczy się jako zdarzenie?

    3. Jaki punkt pracy wybrałem i czyją decyzją to naprawdę powinno być?

    4. Czego w moich danych NIE MA — wypisz trzy rzeczy, których nie nagrałeś,
       a które zdarzą się w hali.

    5. Jedno zdanie o tym detektorze, którego nie umiałbym napisać tydzień temu.

Dalej → [Etap 11 — CI i wstrzykiwanie awarii](./11-ci-i-awarie.md)
