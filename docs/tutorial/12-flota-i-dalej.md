# Etap 12 — Flota, produkcja i dalsza droga

> Po tym etapie umiesz zaprojektować obserwowalność robota, którego nie masz
> pod ręką — i powiedzieć na głos, gdzie kończy się twoja warstwa, a zaczyna
> sterownik bezpieczeństwa.

| | |
|---|---|
| wejście | etapy 01–11 zamknięte: własne interfejsy ze stemplem, testy, które umieją zawieść, nagrania jako fixture'y, zmierzone opóźnienie i katalog awarii odpalany w CI |
| czas | 2–3 wieczory przy kartce; zadanie rozszerzające dokłada czwarty |
| kończy się | masz sześć dokumentów w `projects/grab-fail-detection/`: architekturę, pięć SLI, politykę retencji, procedurę diagnozy zdalnej, jedną awarię przejętą na piśmie i plan na 90 dni |

**Ten etap jest inny od jedenastu poprzednich: zadania są projektowe
i pisemne, nie kodowe.** Jedno rozszerzające zadanie dotyka klawiatury,
reszta to kartka, tabela i decyzja, którą umiesz obronić. Nie dlatego, że
zabrakło materiału na kod — dlatego, że problemy tego etapu są problemami
decyzji, a nie implementacji. Kod, który tu napiszesz bez podjętej decyzji,
i tak wyrzucisz.

---

## Po ludzku: co to jest w twoim świecie

| pojęcie robotyczne | odpowiednik z backendu | gdzie analogia pęka |
|---|---|---|
| telemetria floty | metryki, logi i trace'y z klastra | pasmo jest kupowane na gigabajty i dzielone z ruchem produkcyjnym hali; „po prostu wyślij wszystko" jest tu pozycją na fakturze |
| SLO celi | SLO usługi | część wskaźników dotyczy fizyki, a fizyka nie mieści się w budżecie błędu — o tym niżej, to jest najważniejsze zdanie etapu |
| wdrożenie nowej wersji | rolling update, kanarek | pod ubijesz w dowolnej chwili; ramię w połowie cyklu — nie, bo trzyma przedmiot |
| wycofanie zmiany | `git revert` + poprzedni obraz | obraz wraca w minutę, przedmiot zostaje tam, gdzie go upuściła zła wersja; świat nie ma revertu |
| `ROS_DOMAIN_ID` | namespace, VLAN | to nie jest izolacja bezpieczeństwa, tylko inny zestaw portów UDP — kto jest w tej samej sieci, ten wejdzie |
| sterownik bezpieczeństwa | nie ma odpowiednika | jedyna warstwa systemu, której twój kod nie może naprawić, obejść ani zastąpić — i nie wolno mu udawać, że może |

---

## Po co to — czego bez tego nie da się zrobić

Weź nagranie, które masz w repo, i policz — plik leży na dysku:

    projects/grab-fail-detection/bags/chwyt-3-stany/chwyt-3-stany_0.mcap
    139 974 bajty, 2124 wiadomości, 21,2 s

| liczba | wynik |
|---|---|
| na wiadomość | ~66 B na dysku (przy 4 B ładunku w `Float32`) |
| na sekundę | ~6,6 kB/s |
| na dobę, jeden robot | ~570 MB |
| na miesiąc, dziesięć robotów | ~171 GB |

Sto siedemdziesiąt gigabajtów miesięcznie za dwa skalary. Bez kamery, bez
prądów, bez pozycji przegubów. W metadanych masz `compression_format: ""`,
czyli to jeszcze nawet nie jest skompresowane. Gdybyś te same dane pchał
przez MQTT jako JSON z własnym stemplem i nazwą topiku, koperta zjadłaby
30–40× więcej niż ładunek i wyszłoby podobnie albo gorzej.

I teraz najlepsze: **połowa tych wiadomości nie powinna istnieć.** Nagranie ma
1062 wiadomości na `/vacuum_pressure` i 1062 na `/grasp_verdict` — dokładnie
tyle samo, bo w `ws/src/grip_monitor/grip_monitor/grasp_monitor.py` detekcja
zbocza jest zakomentowana (`# self.last_state = ...`) i werdykt leci 50 Hz.
W 21 sekundach zmiany stanu były trzy. Ta jedna linijka kodu to jest
rachunek za łącze pomnożony przez liczbę robotów i przez liczbę miesięcy.

Drugi problem tego samego kodu widać dopiero przy drugim robocie.
`vacuum_sensor.py` publikuje na `vacuum_pressure` — nazwa względna, bez
przestrzeni nazw. Postaw dziesięć takich węzłów w jednej domenie DDS,
a dostaniesz dziesięć węzłów `/vacuum_sensor` publikujących w ten sam kanał.
To nie jest flota. To jest jeden kanał, w którym dziesięć robotów mówi
naraz i nikt nie wie, które ciśnienie jest czyje.

Bez tego etapu masz więc system, który działa idealnie dokładnie tak długo,
jak stoisz przy nim z otwartym terminalem.

---

## Dlaczego to ciekawe

Gdy robot przestaje stać obok ciebie, tracisz trzy rzeczy naraz i wszystkie
trzy w tej samej sekundzie:

1. **Terminal.** Nie ma `scripts/dev/ros2/print-topic-messages.sh`. Nie ma
   dopięcia się do żywego grafu. Nie ma `set-param.sh`, żeby sprawdzić
   hipotezę. Zostają ci artefakty, które robot zostawił sam.
2. **Ekran.** Nikt nie patrzy. Rzecz, która nie zapaliła się w alercie,
   nie wydarzyła się — nawet jeśli wydarzyła się dwieście razy.
3. **Możliwość powtórzenia sytuacji.** Przedmiot już upadł. Paleta pojechała
   dalej. Operator posprzątał. Ten konkretny układ świata nie wróci.

I tu jest rama całego etapu, i całej roadmapy wstecz: **warstwa, którą
budowałeś przez jedenaście etapów, istnieje po to, żeby te trzy straty nie
zatrzymały diagnozy.** Stempel z etapu 02 zastępuje terminal, bo pozwala
ustawić zdarzenia w kolejności bez patrzenia na nie. Diagnostyka z etapu 06
zastępuje ekran, bo system mówi sam. Nagranie z etapu 03 zastępuje
powtarzalność, bo jest jedynym artefaktem, który przeżywa wszystkie trzy
straty jednocześnie.

Ładny pomysł inżynierski jest tu taki: robot przestaje być klientem, który
melduje, a staje się **świadkiem, który zabezpiecza dowody**. Pętla decyzyjna
zostaje na robocie, na zewnątrz leci konkluzja, a materiał dowodowy czeka
lokalnie, aż ktoś o niego poprosi. To jest dokładna odwrotność odruchu
z backendu, gdzie wysyłasz wszystko do centralnego zbiornika i pytasz
później, bo pasmo do zbiornika jest darmowe. Tutaj nie jest.

Nazwa własna tego pomysłu jest starsza od ROS-a i nosi ją czarna skrzynka
w samolocie: ciągle nadpisywany bufor, który zamraża się w momencie
zdarzenia. Migawkę nagrania robiłeś w [etapie 03](./03-bagi-jako-dane.md) —
tam był to trik na oszczędność dysku. Tu jest to cała architektura.

---

## Dlaczego to trudne

- **Nikt nie publikuje swojej polityki retencji.** Ile wysyłać, co trzymać,
  jak długo — to jest wiedza plemienna każdej firmy z osobna, wypracowana
  po pierwszym rachunku za transfer i po pierwszym audycie. W dokumentacji
  ROS-a tego nie ma, bo to nie jest problem ROS-a.
- **Objaw rozjechanego czasu wygląda jak błąd w twoim kodzie.** Dostajesz
  ujemne opóźnienia i szukasz ich w węźle, w kolejce, w QoS — a leżą
  w zegarze drugiej maszyny. Ludzie tracą na to dni, bo w backendzie NTP
  jest zawsze i zawsze działa, więc nie ma na to odruchu.
- **Kanarek z backendu nie przenosi się wprost i wygląda, jakby się
  przenosił.** Dopóki testujesz na pustej celi, wszystko działa. Pierwsze
  wdrożenie w trakcie cyklu produkcyjnego uczy cię, dlaczego nie.
- **Granica bezpieczeństwa nie jest trudna technicznie — jest trudna
  charakterologicznie.** Kusi, żeby powiedzieć „mój detektor to wykryje
  i zatrzyma robota". Zdanie brzmi profesjonalnie i jest najkosztowniejszym
  zdaniem, jakie software dev może w robotyce wypowiedzieć.
- **Dashboard, który nigdy nie pokazał ci czegoś, czego nie wiedziałeś, jest
  dekoracją** — a przy flocie dekoracji przybywa szybciej niż wiedzy, bo
  każdy nowy robot to nowy wiersz w tabeli i złudzenie postępu.

---

## Wycinek prawdziwej roboty

3:10 w nocy, telefon. Robot 400 km stąd przestał pracować, SSH do niego nie
masz i mieć nie będziesz — siedzi w sieci klienta za NAT-em. Zostaje ci to,
co zdążył o sobie wysłać, zanim zamilkł; ustalił to ktoś pół roku temu. Ty.

Reszta nocy jest listą momentów, w których zwraca się jedna dawna decyzja.
Zdarzenie z 3:05 mówi, co się stało i kiedy stało się to na robocie, a nie
kiedy dotarło do brokera, bo werdykt ma typ z
[etapu 01](./01-kontrakty-wiadomosci.md) i stempel z
[etapu 02](./02-czas-zdarzenia-stan.md). Wiesz, czy węzeł umarł, czy tylko
zamilkł, bo diagnostyka z [etapu 06](./06-logi-diagnostyka-lifecycle.md)
leci osobnym kanałem. „Detektor kłamie" odrzucasz w dwie minuty, bo
z [etapu 10](./10-ewaluacja-na-danych.md) wiesz, ile on kłamie normalnie,
a podpis awarii rozpoznajesz z katalogu z [etapu 11](./11-ci-i-awarie.md).
Migawkę ostatnich trzydziestu sekund masz, bo robot zamraża bufor.

Dobre decyzje kończą tę noc przed śniadaniem i zostawiają dwa artefakty:
pisemną przyczynę ze wskazaniem miejsca w nagraniu i listę tego, czego ci
zabrakło — to jest twój przyszły kwartał. Złe każą czekać do rana, aż ktoś
na miejscu wyjmie dysk. Ta robota ma właściciela: warstwę obserwowalności
floty, a rola pojawia się w firmie dokładnie wtedy, gdy robotów jest więcej
niż inżynierów. Po tym etapie umiesz powiedzieć na rozmowie zdanie, którego
kandydat z samą umiejętnością pisania węzłów nie powie: „mam system, który
sam mówi, kiedy mu źle, i nagranie każdej awarii, którą umiem odtworzyć".

---

## Model pojęciowy

### Piramida telemetrii

Reguła jest jedna: **im wyżej w piramidzie, tym rzadziej i tym mniej; im
niżej, tym więcej — i tym bardziej zostaje na robocie.**

| warstwa | co to | kiedy leci | kanałem | ile tego jest |
|---|---|---|---|---|
| zdarzenia | zmiana werdyktu, początek i koniec cyklu, awaria, restart węzła | zawsze, natychmiast | MQTT albo kolejka; małe, przetrwa zerwanie łącza | jednostki na cykl |
| agregaty | liczniki i histogramy: cykle, sukcesy, p50/p95 opóźnienia, temperatura | zawsze, co 10–60 s | metryki liczbowe (Prometheus/`remote_write`) | dziesiątki próbek na minutę |
| migawki | fragment surowego nagrania wokół zdarzenia, ±10 s | przy awarii albo na żądanie | wgranie pliku, gdy łącze wolne | megabajty na zdarzenie |
| surowe | pełny `/vacuum_pressure` 50 Hz, obraz, prądy | nigdy samo z siebie | tylko na wyraźne żądanie człowieka | gigabajty na dobę |

Progi myślenia, które warto mieć w głowie, zanim zaczniesz się targować:

| pytanie | odpowiedź |
|---|---|
| co wolno wysyłać ciągle | to, co zmieściłoby się w SMS-ie na cykl: werdykt, czas cyklu, kod błędu |
| co wysyłać przy zdarzeniu | to, co odpowiada na pytanie „co się właśnie stało", nie „jak działa robot" |
| co zostaje na robocie i czeka | wszystko, co ma częstotliwość — każdy sygnał 50 Hz i wyżej |
| co decyduje, że jednak wyślesz surowe | człowiek, który już zobaczył zdarzenie i chce dowodu |

Zdrowy test: **jeśli nie umiesz nazwać pytania, na które dana ma odpowiedzieć,
nie wysyłaj jej.** To ta sama zasada, co z roadmapy o dekoracji, tylko
z ceną w gigabajtach.

### Narzędzia i ich role, bez marketingu

| narzędzie | do czego naprawdę | model | koszt wejścia |
|---|---|---|---|
| Foxglove + `foxglove_bridge` | podgląd na żywo przez most WebSocket i praca z nagraniami mcap | robot wystawia most, przeglądarka się łączy | najmniejszy — most jest w apt jako `ros-jazzy-foxglove-bridge`, a mcap już nagrywasz |
| MQTT | lekkie zdarzenia przez zawodne łącze; broker, retencja, QoS 0/1/2, LWT | robot publikuje do brokera, broker rozsyła | średni — broker plus most ROS↔MQTT, którego nie ma w dystrybucji |
| Prometheus | metryki liczbowe: liczniki, gauge'e, histogramy | **odpytywanie** (pull): serwer sam puka do `/metrics` | średni, z jednym haczykiem, patrz niżej |
| Grafana | wykresy i alerty nad metrykami | czyta z Prometheusa albo innej bazy | mały |
| baza szeregów czasowych | długie przechowywanie metryk poza Prometheusem | zapis strumieniowy z Prometheusa | pojawia się dopiero przy miesiącach historii |

**Foxglove jest dla ciebie drogą najkrótszą** i to nie jest przypadek: robi
dokładnie to, co już umiesz — pokazuje topiki i otwiera nagrania — tylko przez
przeglądarkę zamiast przez terminal. W tym repo ma jeszcze jedną zaletę:
kontener nie ma przekazanego ekranu (ani `DISPLAY`, ani `/tmp/.X11-unix`),
więc most WebSocket jest jedyną drogą do obrazka, która nie wymaga
rozwiązywania Waylanda z SELinuksem. Z `--network=host` port mostu widać
z Fedory wprost.

**Haczyk Prometheusa jest architektoniczny, nie konfiguracyjny.** Prometheus
domyślnie *odpytuje*: to serwer inicjuje połączenie do celu. Twój robot stoi
za NAT-em w sieci klienta, ma adres prywatny i żaden port wystawiony na
zewnątrz. Serwer nie ma do czego zapukać. Wyjścia są trzy i każde coś kosztuje:
VPN (robot staje się osiągalny, ale ktoś musi tym zarządzać), Prometheus
w trybie agenta na robocie, który sam *wypycha* metryki na zewnątrz, albo
lokalny Prometheus na robocie i wyciąganie tylko agregatów. Pushgateway
bywa tu proponowany i jest złą odpowiedzią: został zaprojektowany dla
krótkich zadań wsadowych, nie dla ciągłej telemetrii z nieosiągalnego celu.

### Czego żadne z tych narzędzi nie zrobi

Żadne z nich nie zastąpi nagrania. Wykres pokazuje, że ciśnienie spadło
o 3 w nocy. Nie pokazuje, jaki układ danych wszedł do twojego detektora,
w jakiej kolejności, z jakim opóźnieniem, przy jakim QoS i jaka była
zawartość okna `deque(maxlen=25)` w chwili werdyktu. **Wykres pozwala
zobaczyć decyzję, nie pozwala jej odtworzyć.**

Metryki i nagrania nie są więc alternatywami do wyboru: metryki mówią ci,
*że* i *kiedy*, a wejścia, z których odtworzysz *dlaczego* i zrobisz test
regresji ([etap 04](./04-piramida-testow.md)), są tylko w nagraniu.

### Retencja i prywatność

Rotacja nagrań to trzy decyzje, nie jedna: **jak długo trzymać**, **jak
dzielić pliki** i **co robić, gdy dysk się kończy**. Trzecia jest ważniejsza,
niż wygląda: robot, który przestaje nagrywać przy pełnym dysku, traci
dokładnie tę awarię, przez którą dysk się zapełnił.

Budżet dysku liczy się z liczb, które już masz: 570 MB na dobę z dwóch
skalarów bez kompresji. Dźwignie są trzy — nagrywać rzadziej (decymacja),
nagrywać mniej kanałów, albo kompresować; `rosbag2` ma podział plików po
rozmiarze i po czasie oraz kompresję, sprawdź `ros2 bag record --help`,
bo zestaw flag zmienia się między wydaniami.

Prywatność dokłada warstwę, której nie ma w żadnym budżecie. Kamera w hali,
po której chodzą ludzie, nagrywa twarze, plakietki z nazwiskami, sylwetki
rozpoznawalne po chodzie i to, kto o której wszedł na zmianę. To są dane
osobowe niezależnie od tego, czy twój pipeline je przetwarza, czy tylko
zapisuje. Konsekwencje są konkretne: nagranie z kamery ma inny okres
retencji niż nagranie z czujnika ciśnienia, ma inne prawo dostępu, i nie
wolno go wysłać do chmury — zwłaszcza poza organizację i poza kraj — bez
podstawy prawnej i zgody właściciela obiektu.

**To jest pytanie prawne, nie techniczne.** Nie rozstrzygniesz go czytaniem
dokumentacji, bo odpowiedź zależy od umowy z klientem, od regulaminu hali
i od jurysdykcji, a nie od formatu pliku. Zdanie „muszę to skonsultować
z prawnikiem, zanim włączymy wysyłkę" nie jest w tej robocie unikiem — jest
oznaką, że wiesz, gdzie stoisz. Ludzie, którzy tego nie mówią, kosztują
swoje firmy więcej niż ci, którzy mówią to za często.

### Czas we flocie

Dopóki wszystko chodziło na jednej maszynie, stemple z
[etapu 02](./02-czas-zdarzenia-stan.md) były porównywalne za darmo, bo kontener dzieli
zegar z jądrem hosta, a węzeł i skrypt na Fedorze czytają ten sam zegar. Nie było problemu,
bo nie było dwóch zegarów.

Przy dwóch komputerach i przy chmurze są dwa zegary i zaczynają dryfować.
Zwykły dryf krystaliczny to rząd dziesiątek ppm, czyli **sekundy na dobę**
— a ty mierzysz opóźnienia w milisekundach.

| poziom | czym | dokładność, o którą walczysz | kiedy wystarczy |
|---|---|---|---|
| minimum | NTP (`chrony`, `systemd-timesyncd`) | jednostki–dziesiątki ms | korelacja zdarzeń, logi, metryki |
| gdy liczą się milisekundy | PTP (IEEE 1588, `linuxptp`) | mikrosekundy, ale wymaga wsparcia sieci | pomiar opóźnień między maszynami, fuzja czujników |

**Objaw, po którym poznasz, że masz ten problem: ujemne opóźnienia.**
Wiadomość dociera, zanim została nadana. Twoja analiza z
[etapu 09](./09-latencja-i-tracing.md) zaczyna produkować p95 mniejsze od
zera albo histogram z nogą po lewej stronie zera. Nie szukaj wtedy w kodzie.
Porównaj zegary.

Druga, subtelniejsza wersja: opóźnienia nie są ujemne, tylko systematycznie
przesunięte o stałą wartość. To wygląda jak realne opóźnienie i przez to
jest gorsze.

### SLI, SLO i miejsce, w którym budżet błędu pęka

SLI to wskaźnik, który mierzysz. SLO to próg, na który się umawiasz. Przy
celi chwytającej sensowne wskaźniki wyglądają tak:

| wskaźnik | co naprawdę mierzy | skąd go weźmiesz w tym repo |
|---|---|---|
| skuteczność chwytu | odsetek cykli zakończonych werdyktem `sealed` | licznik werdyktów ze zboczem, nie z 50 Hz |
| czas cyklu | ile trwa jeden przedmiot, p50 i p95 | stemple z etapu 02, para zdarzeń start/koniec |
| odsetek fałszywych werdyktów | jak często system kłamie w obie strony | macierz pomyłek z [etapu 10](./10-ewaluacja-na-danych.md), na etykietowanych nagraniach |
| czas między awariami | jak często cela staje | zdarzenia awarii, licznik plus stempel |
| czas do naprawy | ile trwa powrót do pracy, z twoim udziałem albo bez | para zdarzeń: awaria → pierwszy udany cykl |

Dwa ostatnie są tymi, które w rozmowie o twojej pracy padają najczęściej,
bo to one przekładają się na pieniądze. Ale to trzeci jest twoim wskaźnikiem
osobistym: fałszywy werdykt to jedyna pozycja na liście, za którą odpowiada
bezpośrednio kod, który napisałeś.

Analogia do budżetu błędu działa i jest przydatna: skoro umawiasz się na
99% skutecznych chwytów, to 1% upuszczeń jest **zaplanowany**, a nie jest
porażką — i wolno ci ten procent wydać na szybsze cykle albo na wdrożenie
nowej wersji.

**Bezpieczeństwa nie da się wydać z budżetu.** Dopuszczalny odsetek
upuszczonych przedmiotów istnieje, bo upuszczony przedmiot kosztuje pieniądze
i da się je policzyć. Dopuszczalny odsetek przygnieceń ręki nie istnieje.
Nie ma tam procenta do wydania, nie ma kompromisu z czasem cyklu i nie ma
rozmowy o tym, czy w tym kwartale możemy sobie pozwolić na trochę więcej.
Wskaźniki związane z bezpieczeństwem nie są SLI. Są warunkiem brzegowym
i leżą poza twoją tabelą.

### Wdrożenie: dlaczego kanarek nie przenosi się wprost

Na robocie wdrażasz obraz kontenera — to akurat przenosi się jeden do
jednego i to jest dobra wiadomość: wersjonowanie obrazów, jawne tagi (nigdy
`latest` na robocie), poprzedni obraz zostawiony na dysku jako droga
powrotu, wdrożenie etapami — najpierw jeden robot, potem jedna linia, potem
zakład.

**Ramię w połowie cyklu nie może przełączyć wersji.** Kanarek w backendzie
działa, bo żądania są krótkie i bezstanowe: nowa wersja bierze 5% ruchu,
stara dokańcza swoje, nikt niczego nie trzyma. Robot trzyma przedmiot.
Przerwanie procesu w połowie ruchu to nie jest przerwane żądanie, tylko
przedmiot na podłodze albo ramię zatrzymane w pozycji, z której nikt nie
wie, jak wyjechać.

**Stan fizyczny świata nie wraca sam do punktu wyjścia.** Rollback
w backendzie przywraca kod i bazę. Tutaj przywraca kod. Przedmiot leży tam,
gdzie upadł; pojemnik jest w innym stanie niż był; ktoś musi wejść i posprzątać.

Z tych dwóch rzeczy wynika jeden wymóg, który masz zapamiętać z tego etapu:

> **Aktualizacja musi mieć jasno zdefiniowany moment bezpieczny** — punkt
> w cyklu, w którym robot niczego nie trzyma, nic nie jest w ruchu,
> a przerwanie procesu nie zostawia świata w stanie pośrednim.

I ten moment ktoś musi wskazać palcem w twoim konkretnym cyklu. To nie jest
własność infrastruktury wdrożeniowej. To jest własność procesu, który
automatyzujesz — i zwykle nikt tego nie ma spisanego, dopóki nie zapytasz.

### Skala sieciowa ROS-a

| mechanizm | co daje | czego nie daje |
|---|---|---|
| `ROS_DOMAIN_ID` | rozdzielenie ruchu: węzły w różnych domenach nie widzą się wzajemnie | żadnego bezpieczeństwa; to wybór portów UDP, nie ściana |
| ograniczenie zakresu odkrywania | powstrzymanie multicastu od zalewania sieci zakładu | automatycznego sklejenia tego, co rozdzieliłeś |
| `domain_bridge` | świadome przepuszczenie **wybranych** topików między domenami | mostu przez internet — to narzędzie do sieci lokalnej |

Domyślne odkrywanie DDS opiera się na multicaście w podsieci i to jest
projekt pod jedną halę, nie pod zakład z kilkuset maszynami. W większej
sieci multicast bywa wycięty na przełącznikach albo wręcz przeciwnie —
działa aż za dobrze i każdy węzeł poznaje każdy inny, przez co koszt
odkrywania rośnie kwadratowo. Od wydania Iron ROS 2 ma zmienne środowiskowe
do ograniczania zasięgu odkrywania i do wskazywania konkretnych hostów
zamiast multicastu; **sprawdź w dokumentacji swojego dystrybutu, jak
dokładnie nazywają się i co robią w Jazzy**, bo to jest obszar, który
zmieniał się między wydaniami i połowa poradników w sieci opisuje stan
sprzed zmiany.

`domain_bridge` (w apt jako `ros-jazzy-domain-bridge`) rozwiązuje problem
„dwie wyspy, jeden wspólny kanał": łączy wybrane topiki między dwoma
`ROS_DOMAIN_ID` w jednym procesie, a co ma przechodzić, deklarujesz w pliku
YAML. To jest właściwy sposób myślenia o granicach w większej instalacji —
**domyślnie nic nie przechodzi, przechodzi to, co wypisałeś.**

Osobnym kierunkiem rozwoju ROS-a są alternatywne warstwy transportowe pod
RMW — inne implementacje DDS oraz warstwy oparte na innym protokole niż
DDS, projektowane pod przypadki, w których domyślne odkrywanie jest
problemem (routing przez internet, sieci zawodne, duża liczba węzłów).
**Sprawdź, co jest dostępne w twoim dystrybucie**, zanim wpiszesz cokolwiek
do `.devcontainer/Containerfile`. Zmiana RMW to zmiana całej floty naraz —
obie strony muszą mówić tym samym.

### Normy i granica odpowiedzialności

| norma | czego dotyczy |
|---|---|
| ISO 10218 | roboty przemysłowe: część o samym robocie i część o instalacji, czyli o twojej celi |
| ISO/TS 15066 | współpraca człowieka z robotem: siły, prędkości, granice dopuszczalnego kontaktu |
| IEC 61508 | bezpieczeństwo funkcjonalne systemów elektronicznych, norma-matka dla branż |
| ISO 13849 | bezpieczeństwo części systemów sterowania związanych z bezpieczeństwem, w wersji maszynowej |

A teraz zdanie, które jest najważniejszym zdaniem tego etapu i może całej
roadmapy:

> **Twoja warstwa obserwowalności NIE jest funkcją bezpieczeństwa.**

Zatrzymanie awaryjne realizuje sterownik bezpieczeństwa: osobny sprzęt,
dwukanałowy, z samotestowaniem, certyfikowany, z określonym poziomem
nienaruszalności i z okablowaniem, które nie przechodzi przez twój komputer.
Nie realizuje go węzeł w Pythonie, który wykrył nieszczelność, i nie
realizuje go alert w Grafanie. Twój `grasp_monitor` może orzec, że chwyt
się nie udał. Nie może zagwarantować, że coś się zatrzyma — bo nie ma
gwarantowanego czasu reakcji, nie ma gwarancji, że proces żyje, nie ma
gwarancji, że wiadomość dotarła (kanał jest `BEST_EFFORT`), i nie ma
nikogo, kto to zweryfikował i podpisał.

Ten błąd nie ujawnia się przy wdrożeniu. Ujawnia się wtedy, kiedy ktoś na podstawie twojego zdania **zrezygnuje z prawdziwego
zabezpieczenia** — nie postawi skanera, nie doda bramki, nie policzy
odległości — bo przecież „software to wykrywa". Twoja pomyłka zostaje
wpisana w projekt instalacji i materializuje się miesiące później,
w sytuacji, o której się nie dowiesz z dashboardu.

Odwrotna strona tej samej monety jest twoją zawodową przewagą:
**umiejętność powiedzenia „to nie jest funkcja bezpieczeństwa,
potrzebujecie tu sterownika" podnosi twoją wartość w zespole natychmiast.**
Nie musisz umieć zaprojektować obwodu bezpieczeństwa. Musisz wiedzieć, że istnieje, że jest cudzy i że nie wolno
go udawać.

### Mapa dalszej drogi

| kierunek | po co tobie | kiedy zacząć |
|---|---|---|
| `ros2_control` w głąb | to jest warstwa, w której żyje prawdziwy ruch; z [etapu 08](./08-tf2-urdf-ros2-control.md) znasz jej zarys, nie wnętrze | gdy pierwszy raz zapytasz „dlaczego ten sterownik gubi cykle" |
| C++ i `rclcpp` | tam, gdzie Python nie sięga: pętle kHz, sterowniki sprzętu, cudzy kod, który musisz czytać | gdy trafisz na węzeł, którego nie możesz naprawić, bo nie umiesz go przeczytać |
| systemy czasu rzeczywistego | czym jest gwarancja terminu, czym `PREEMPT_RT`, dlaczego GC i alokacja są wrogami | [etap 09](./09-latencja-i-tracing.md) zostawił cię dokładnie na tej granicy |
| magistrale przemysłowe i PLC | EtherCAT, PROFINET, Modbus — tym mówi hala; PLC jest po drugiej stronie twojej celi | przy pierwszej integracji z linią, która istniała przed tobą |
| percepcja jako klient twoich metryk | nie musisz trenować modeli; musisz umieć ocenić cudzy na danych | masz to z [etapu 10](./10-ewaluacja-na-danych.md), pogłębiaj przy pierwszym modelu w projekcie |

Gdzie czytać: dokumentacja Jazzy, REP-y, ROS Discourse i nagrania z ROSCon —
z krótkim „po co" przy każdej pozycji w „Co przeczytać" na końcu pliku.

Do czego kontrybuować: **do narzędzi, nie do algorytmów.** `rosbag2`,
`ros2_tracing`, mosty, dokumentacja, komunikaty błędów, które nic nie mówią.
To jest najkrótsza droga do widoczności w tym świecie — algorytmów
planowania ruchu jest kto pisać, a narzędzi do patrzenia na nie brakuje. Zaczyna się od jednego zgłoszonego
błędu z reprodukcją, a nie od pull requesta.

### Jak ta rola nazywa się na rynku

W ogłoszeniach nazywa się to „ROS developer", czasem „robotics software
engineer", i treść ogłoszenia zwykle wylicza pakiety. Praca polega na tym,
czego właśnie się nauczyłeś: sprawić, żeby system było widać, dało się go
zmierzyć i udowodnić, że działa.

Co pokazać w portfolio: **to repo.** Nie dlatego, że jest imponujące, tylko
dlatego, że ma cztery rzeczy, których cudze portfolio zwykle nie ma —
nagrania, testy, które umieją zawieść, metryki z liczbami i opisany katalog
awarii z [etapu 11](./11-ci-i-awarie.md). Plus `NOTES.md`, w którym widać,
jak myślałeś.

---

## Zadania

Wynik to plik w `projects/grab-fail-detection/`, nie kod w `ws/src/`. Pisz
krótko — jedna strona na dokument. Dokument, którego nie da się przeczytać w pięć minut
o trzeciej w nocy, nie zadziała o trzeciej w nocy.

### Zadanie 12.1 — Architektura obserwowalności celi na jednej stronie (rdzeń)

**Cel:** mieć jeden rysunek, z którego widać, co zostaje na robocie, co leci
dalej, jakim kanałem i jak często.
**Ćwiczysz:** piramidę telemetrii — jej cztery warstwy są czterema słowami
dopóty, dopóki nie obsadzisz ich własnymi topikami i nie policzysz bajtów.

Narysuj — ASCII w pliku, kartka i zdjęcie, cokolwiek — cztery warstwy
piramidy z modelu pojęciowego, obsadzone **twoimi** danymi: dwa topiki,
które masz, plus te, które dołożysz. Każda strzałka wychodząca z robota ma
podpis: co, czym, jak często, ile bajtów na godzinę. Policz te bajty, nie
zgaduj — masz punkt odniesienia w nagraniu z repo.

Zaznacz na rysunku **granicę bezpieczeństwa**: co jest twoje, a co jest
sterownika bezpieczeństwa. Ta linia ma być na rysunku, nawet jeśli po jej
drugiej stronie w twoim projekcie na razie nie ma nic.

**Gotowe, gdy:** umiesz pokazać palcem na rysunku każdą daną z tabeli
„co wolno wysyłać ciągle" i powiedzieć, którą strzałką leci — a suma bajtów
na godzinę jest liczbą, nie słowem „mało".

### Zadanie 12.2 — Pięć SLI z progami i uzasadnieniem (rdzeń)

**Cel:** zamienić „działa dobrze" na pięć liczb, na które umiesz się umówić.
**Ćwiczysz:** granicę między SLI a warunkiem brzegowym — widać ją dopiero
wtedy, gdy próbujesz wpisać próg przy wskaźniku bezpieczeństwa.

Dla każdego z pięciu wskaźników z tabeli w modelu pojęciowym napisz cztery
rzeczy w jednym wierszu tabeli: **definicja** (co dokładnie liczymy,
z jakich zdarzeń), **próg** (konkretna liczba), **uzasadnienie progu**
(skąd ta liczba — z danych, z umowy z klientem, czy z sufitu; „z sufitu"
jest dopuszczalną odpowiedzią, o ile ją napiszesz) i **skąd dane**
(który topik, który licznik, które nagranie).

Osobno, na dole, wypisz wskaźniki, które **odrzuciłeś** i dlaczego. Ta lista
jest trudniejsza i ważniejsza.

**Gotowe, gdy:** dla każdego progu umiesz odpowiedzieć na pytanie „a dlaczego
nie dwa razy więcej" — i choć raz odpowiedź brzmi „bo policzyłem na nagraniu".

### Zadanie 12.3 — Polityka retencji nagrań (rdzeń)

**Cel:** mieć zapisaną odpowiedź na pytanie, co znika i kiedy, zanim dysk
odpowie za ciebie.
**Ćwiczysz:** trzecią decyzję retencji, tę o pełnym dysku — przeczytana jest
szczegółem operacyjnym, zapisana każe ci wskazać, co znika pierwsze.

Napisz politykę na pół strony. Ma zawierać: **budżet dysku** w gigabajtach,
**okres retencji osobno dla każdej klasy danych** (skalary, migawki awarii,
obraz z kamery — jeśli kiedyś będzie), **co się dzieje przy zapełnieniu
dysku** (co nadpisujemy pierwsze i dlaczego akurat to), **kto ma dostęp**
oraz **co nie opuszcza robota bez decyzji człowieka**.

Dopisz na końcu akapit o kamerze w hali, po której chodzą ludzie — nawet
jeśli w twoim projekcie kamery jeszcze nie ma. Jedno zdanie tego akapitu
ma brzmieć „to wymaga konsultacji prawnej" i ma wskazywać, czego dokładnie
dotyczy pytanie.

**Gotowe, gdy:** umiesz z tej polityki wyliczyć, po ilu dniach zniknie
nagranie awarii, której nikt nie obejrzał.

### Zadanie 12.4 — Procedura „awaria w polu → diagnoza" (rdzeń)

**Cel:** mieć listę kroków, którą wykona ktoś inny niż ty.
**Ćwiczysz:** robota jako świadka, nie klienta — teza sprawdza się dopiero
pod cudzą ręką, bo wtedy krok wymagający SSH przestaje być krokiem.

Napisz ponumerowaną procedurę: od zdarzenia, które przyszło z robota, do
wskazania przyczyny. Każdy krok ma mieć **narzędzie z konkretnego etapu**:
migawkę i pracę na nagraniu z [etapu 03](./03-bagi-jako-dane.md), introspekcję
i QoS z [etapu 05](./05-introspekcja-qos-narzedzia.md), logi i diagnostykę
z [etapu 06](./06-logi-diagnostyka-lifecycle.md), pomiar opóźnienia
z [etapu 09](./09-latencja-i-tracing.md).

Ograniczenie, które nadaje temu sens: **na żadnym kroku nie masz SSH
do robota.** Jeśli krok wymaga sesji na maszynie, nie jest krokiem
procedury — jest luką w telemetrii i ląduje na liście z zadania 12.5.

**Gotowe, gdy:** procedura ma mniej niż dziesięć kroków i każdy zaczyna się
od czasownika.

### Zadanie 12.5 — „Zepsuj to" w wersji sztabowej (rdzeń)

**Cel:** znaleźć luki w telemetrii, zanim znajdzie je awaria.
**Ćwiczysz:** noc z „Wycinka prawdziwej roboty", tyle że bez szczęścia —
luka w telemetrii ujawnia się w chwili odruchu, a odruchu się nie czyta.

Wybierz **jedną** pozycję z katalogu awarii z
[etapu 11](./11-ci-i-awarie.md) — na przykład tę, w której `vacuum_sensor`
dostaje zły parametr `state` i wywraca się `RuntimeError`-em w callbacku
timera. Przejdź ją **na piśmie**, w takich warunkach:

    3:07 w nocy. Robot stoi 400 km stąd.
    Nie masz SSH. Nie masz VPN-a. Jest zdarzenie, które przyszło o 3:05.
    Operator na miejscu odbiera telefon i wykona to, co mu powiesz.

Prowadź dziennik w dwóch kolumnach: **co robisz** i **czego ci w tej chwili
brakuje**. Za każdym razem, gdy odruchowo sięgasz po coś, czego nie masz
(„zobaczyłbym `ros2 node list`", „sprawdziłbym, czy proces żyje", „obejrzałbym
ostatnie dziesięć sekund ciśnienia"), stawiasz wiersz w drugiej kolumnie.

Nie oszukuj się na kroku, na którym się zatniesz. Zatnięcie się jest
wynikiem tego zadania, a nie jego porażką.

**Gotowe, gdy:** druga kolumna ma co najmniej pięć wierszy i każdy z nich
umiesz przepisać na zdanie zaczynające się od „robot musi wysyłać…" albo
„robot musi zapisywać…". **To jest twoja lista zadań na przyszły kwartał.**

### Zadanie 12.6 — Plan na 90 dni (rdzeń)

**Cel:** wyjść z tej roadmapy z jedną kartką zamiast z listą życzeń.
**Ćwiczysz:** zamianę braku na obserwowalny efekt — tę samą operację, którą
każdy etap robi w polu „kończy się", tym razem bez cudzego kryterium.

Trzy miesiące, trzy sekcje, w każdej maksymalnie trzy pozycje. Każda pozycja
ma **obserwowalny efekt** — dokładnie w tym sensie, w jakim każdy etap tej
roadmapy ma „kończy się". „Nauczyć się C++" nie jest pozycją. „Przeczytać
i umieć wytłumaczyć jeden węzeł `ros2_control` w C++" — jest.

Weź materiał z dwóch miejsc: z listy luk z zadania 12.5 (to jest priorytet,
bo to są rzeczy, które już ci zabrakły) oraz z tabeli kierunków w modelu
pojęciowym. Jedna pozycja w kwartale ma być kontrybucją na zewnątrz — choćby
zgłoszonym błędem z reprodukcją.

**Gotowe, gdy:** plan mieści się na jednej kartce i żadna pozycja nie zaczyna
się od „zapoznać się z".

### Zadanie 12.7 — Prometheus i Grafana obok kontenera (rozszerzenie)

**Cel:** zobaczyć trzy własne SLI na wykresie, który odświeża się sam.
**Ćwiczysz:** model odpytywania na własnej skórze — dopiero gdy sam ustawisz
cel, który ktoś odpytuje, pytanie o robota za NAT-em przestaje być akapitem.

Postaw Prometheusa i Grafanę jako osobne kontenery obok
`robotics-ros2` — to nie ma iść do `.devcontainer/Containerfile`, bo to nie
jest część środowiska deweloperskiego, tylko osobna usługa. W węźle wystaw
endpoint `/metrics` (biblioteka `prometheus_client`; zanim sięgniesz po
`pip install`, zobacz „Pułapki"). Wystaw trzy wskaźniki z zadania 12.2 — sensowny
zestaw na start to licznik werdyktów z podziałem na stan, histogram
opóźnienia czujnik → werdykt i licznik cykli.

**Gotowe, gdy:** na dashboardzie w Grafanie widzisz zmianę po
`scripts/dev/ros2/set-param.sh /vacuum_sensor state leak` — a wykres
licznika rośnie schodkami, nie leży płasko (jeśli leży, patrz „Pułapki").

---

## Pułapki

| objaw | przyczyna | co zrobić |
|---|---|---|
| Prometheus nie widzi robota, choć konfiguracja jest poprawna | model odpytywania: serwer inicjuje połączenie, a robot jest za NAT-em bez wystawionego portu | VPN, tryb agenta z wypychaniem metryk albo lokalny Prometheus na robocie — Pushgateway to nie jest odpowiedź na ciągłą telemetrię |
| `pip install prometheus-client` kończy się `externally-managed-environment` | Ubuntu 24.04 i PEP 668 — systemowy Python jest chroniony | pakiet z apt albo venv; i tak wpisz wybór do `Containerfile`, bo inaczej zginie przy odtworzeniu |
| licznik w Grafanie jest płaską linią tuż nad zerem | patrzysz na surową wartość `Counter`, która tylko rośnie | oglądaj pochodną (`rate()`), nie wartość; dla `Counter` surowa wartość nie niesie prawie nic |
| Grafana albo Prometheus w podmanie rootless nie widzą swoich plików konfiguracyjnych | SELinux — wolumen podmontowany bez etykiety | `:Z` przy montowaniu albo `--security-opt label=disable`; komunikat mówi „permission denied", więc szukasz w prawach pliku i nic nie znajdujesz |
| p95 opóźnienia wychodzi ujemne po dołożeniu drugiej maszyny | zegary nie są zsynchronizowane; dotąd nie było problemu, bo kontener dzieli zegar z hostem | NTP jako minimum; PTP dopiero gdy walczysz o milisekundy między maszynami |
| opóźnienie wygląda realnie, ale jest stale przesunięte o tę samą wartość | stały offset zegara, nie opóźnienie transportu | porównaj zegary, zanim zaczniesz optymalizować kod — mierzysz cudzy dryf i nazywasz go wydajnością |
| po zmianie `ROS_DOMAIN_ID` węzły „znikają" mimo że procesy żyją | zmienna ustawiona w jednej sesji; skrypty z `scripts/dev/ros2/` wchodzą przez powłokę logowania i widzą profil, nie twój `export` | ustaw domenę tam, gdzie ją widzą obie strony, i sprawdź `scripts/dev/ros2/list-running-nodes.sh` z obu miejsc |
| Foxglove łączy się z mostem, ale panele są puste | niedopasowane QoS między publikującym a mostem — ten sam problem, co w [etapie 05](./05-introspekcja-qos-narzedzia.md) | porównaj obie strony przez `scripts/dev/ros2/show-topic-connections.sh`; `/vacuum_pressure` jest `BEST_EFFORT` |
| most Foxglove „przestał działać" po zmianie w `devcontainer.json` | zniknęło `--network=host` i port nie jest już widoczny z Fedory | sprawdź `runArgs`; z mostem nic się nie stało, zmieniła się sieć |
| nagranie rośnie dwa razy szybciej, niż liczyłeś | zakomentowana detekcja zbocza w `grasp_monitor.py` — werdykt leci 50 Hz zamiast na zmianę stanu | to nie jest problem retencji, tylko wady z listy w [roadmapie](./00-roadmapa.md); napraw źródło, nie dysk |
| dysk pełny, a awarii nie ma w nagraniu | robot przestał nagrywać, zanim doszło do awarii, która zapełniła dysk | polityka retencji musi mówić, co nadpisujemy pierwsze — brak decyzji to też decyzja, tylko cudza |

---

## Sprawdź się

1. Tracisz terminal, ekran i powtarzalność. Który artefakt z całej roadmapy
   jako jedyny przeżywa wszystkie trzy straty naraz i dlaczego akurat on?
2. Dlaczego model odpytywania Prometheusa psuje się przy robocie za NAT-em,
   a model MQTT nie? Co dokładnie jest tą różnicą — protokół czy to, kto
   inicjuje połączenie?
3. Masz wykres z Grafany pokazujący spadek ciśnienia o 3:05. Czego z tego
   wykresu **nie** odtworzysz i czego ci potrzeba, żeby to odtworzyć?
4. Dopuszczalny odsetek upuszczonych przedmiotów istnieje, dopuszczalny
   odsetek przygnieceń ręki nie. Co ta asymetria oznacza dla tabeli twoich
   SLO — i dlaczego bezpieczeństwa nie da się wliczyć do budżetu błędu?
5. Dlaczego kanarek z backendu nie przenosi się na robota wprost? Podaj dwa
   powody, z których jeden dotyczy przerwania, a drugi wycofania zmiany.
6. Twój węzeł wykrył nieszczelność i opublikował werdykt. Dlaczego to nie
   jest funkcja bezpieczeństwa — wymień trzy rzeczy, których twojemu
   kanałowi brakuje, żeby nią być?
7. `ROS_DOMAIN_ID` rozdziela dwie instalacje w jednej sieci. Dlaczego mimo
   to nie jest zabezpieczeniem?
8. Po dołożeniu drugiego komputera dostajesz ujemne opóźnienia. Gdzie
   szukasz i dlaczego nie w swoim kodzie?

---

## Co przeczytać

- **Dokumentacja Jazzy** (`https://docs.ros.org/en/jazzy/`) — sekcje
  o `ROS_DOMAIN_ID` i o konfiguracji odkrywania. Po to, żeby wiedzieć, co
  twój dystrybut faktycznie ma, a nie co miał ten, o którym pisał autor
  poradnika.
- **REP-2000** (`https://www.ros.org/reps/`) — wydania ROS 2 i platformy
  docelowe. Po to, żeby wiedzieć, jak długo Jazzy będzie wspierane i co to
  znaczy dla robota, który ma stać w hali cztery lata.
- **REP-2004** (tamże) — kategorie jakości pakietów. Po to, żeby umieć
  ocenić cudzy pakiet, zanim wpuścisz go na robota w polu, i żeby wiedzieć,
  co właściwie zgłaszasz, gdy zgłaszasz brak.
- **`https://github.com/ros2/rosbag2`** — zgłoszenia i README. Po to, żeby
  zobaczyć, gdzie kończy się to narzędzie i jak wygląda kontrybucja do
  narzędzia, którego sam używasz.
- **ROS Discourse** — po to, żeby widzieć zmiany, zanim trafią do
  dokumentacji; szczególnie wątki o wydaniach i o warstwach transportowych.
- **Nagrania z ROSCon** — po to, żeby posłuchać, jak firmy opowiadają
  o wdrożeniach, które im nie wyszły. To jedyne publiczne źródło wiedzy
  plemiennej o flocie.

Norm (ISO 10218, ISO/TS 15066, IEC 61508, ISO 13849) nie linkuję, bo są
płatne i nie są lekturą na wieczór. Wystarczy, że znasz numery i wiesz,
kiedy powiedzieć „to jest pytanie do inżyniera bezpieczeństwa, nie do mnie".

---

## Dziennik

Ostatni wpis. Odpowiedz pisemnie, nie w głowie.

1. Który wiersz z drugiej kolumny zadania 12.5 — ten o brakujących danych —
   zaskoczył cię najbardziej? Czego byłeś pewien, że masz, a nie masz?
2. Co zjadło najwięcej czasu w tym etapie i czy było to liczenie, czy
   podejmowanie decyzji?
3. Który próg w zadaniu 12.2 wpisałeś z sufitu i co musiałbyś zmierzyć,
   żeby przestać?
4. Napisz jedno zdanie o granicy między obserwowalnością a bezpieczeństwem,
   którego nie umiałbyś napisać dwanaście etapów temu.
5. Wróć do `projects/grab-fail-detection/NOTES.md`, do wpisu z dnia
   pierwszego. Co z tamtej listy jest dziś oczywiste?

---

← [Roadmapa](./00-roadmapa.md)

Roadmapa jest skończona, projekt nie. Cela nadal nie chwyta niczego
prawdziwego — ale masz już warstwę, która powie ci, co się stało, gdy
wreszcie zacznie.
