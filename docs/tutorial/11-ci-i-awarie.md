# Etap 11 — CI i wstrzykiwanie awarii

> Po tym etapie regresja zapala się bez ciebie, a awarię umiesz wywołać na
> żądanie — zamiast czekać, aż zdarzy się sama, w polu, o 3 w nocy.

| | |
|---|---|
| wejście | [04](./04-piramida-testow.md) testy, [06](./06-logi-diagnostyka-lifecycle.md) diagnostyka, [07](./07-gazebo-stanowisko.md) symulacja bezgłowa, [10](./10-ewaluacja-na-danych.md) metryki i progi; repo ze złotym nagraniem i skryptem ewaluacji |
| czas | 3–4 wieczory — przepływ CI zajmie jeden, katalog awarii resztę |
| kończy się | PR w tym repo świeci na czerwono, gdy detektor przestaje wydawać werdykty, i zostawia nagranie, logi oraz metryki, z których widać dlaczego |

## Po ludzku: co to jest w twoim świecie

| w backendzie | tutaj | gdzie analogia pęka |
|---|---|---|
| pipeline CI | przepływ budujący obraz z `.devcontainer/Containerfile` | budujesz cały system operacyjny robota, nie samą aplikację — pierwszy build to minuty i ~7 GB, nie 30 sekund |
| stacktrace z produkcji | nagranie (bag) z przebiegu | stacktrace mówi, gdzie kod pękł; tutaj kod nie pęka — **milknie**, a jedynym dowodem jest strumień danych |
| chaos engineering (ubity pod) | wstrzykiwanie awarii w topiki i procesy | nie ma repliki ani load balancera, który to przykryje; padnięty węzeł to po prostu ślepy robot |
| flaky test | test z prawdziwym DDS | niedeterminizm siedzi w transporcie, nie w twoim kodzie — mock go usuwa razem z tym, co miałeś sprawdzić |
| soak test | nocny przebieg w symulacji | zegar symulacji da się przyspieszyć; w backendzie godzina to godzina |
| kanarek, wdrożenie 5% ruchu | brak odpowiednika | robot nie ma 5% ruchu — albo wykonuje cykl, albo go nie wykonuje |

## Po co to — czego bez tego nie da się zrobić

**Po pierwsze: dzisiaj nikt tych testów nie uruchamia.** `colcon test` odpala
się wtedy, gdy o nim pamiętasz, na twojej maszynie, na twoim buildzie, po
twojej ostatniej zmianie. Test, który zależy od pamięci autora, jest notatką.

**Po drugie: `.devcontainer/Containerfile` startuje z `FROM
docker.io/osrf/ros:jazzy-desktop` — a to jest tag ruchomy.** Obraz pod tą
nazwą zmienia się w czasie. Dzisiaj `colcon build` przechodzi. Za sześć
tygodni, gdy zrobisz Rebuild Container przed demem, może nie przejść — i
dowiesz się o tym dokładnie wtedy, kiedy nie masz czasu. CI, który buduje ten
plik co noc, jest **czujnikiem dryfu środowiska**: mówi ci o zmianie w dniu,
w którym zaszła, a nie w dniu, w którym ci przeszkodziła.

**Po trzecie, i to jest najważniejsze: w `grasp_monitor.py` siedzi teraz błąd,
którego nie złapie żaden istniejący test.** Osiem linii, bez wyjątku, bez
logu, bez śladu:

```python
mean = np.mean(self.frame)

if is_at_level(mean, 0):
    self.publish_state_change('open')
if mean < -1 and mean > -58:
    self.publish_state_change('leak')
if is_at_level(mean, -59):
    self.publish_state_change('sealed')
```

Trzy `if` i **ani jednego `else`**. Gdy `mean` jest `NaN`, wszystkie trzy są
fałszywe (każde porównanie z NaN jest fałszem). Gdy `mean` wynosi -1000, też
wszystkie trzy są fałszywe. Gdy czujnik padnie, callback po prostu przestaje
się wywoływać. **Trzy różne awarie, jeden objaw: cisza na `/grasp_verdict`** —
i węzeł, który przez cały czas wygląda na zdrowy w `list-running-nodes.sh`.

Bez tego etapu ta cisza nie ma kto zauważyć.

## Dlaczego to ciekawe

Cisza jest domyślnym wyjściem tego detektora. Nie zaprojektowałeś jej — ona
powstała z braku `else`. I to jest wzorzec, który w robotyce spotkasz
wszędzie: **stan „nie wiem" nie jest reprezentowany, więc przebiera się za
stan „nic się nie dzieje"**. W backendzie brak odpowiedzi zgłosi timeout
klienta. Tutaj nikt nie czeka na odpowiedź — odbiorca po prostu dalej ma
ostatnią wartość, którą usłyszał, i uznaje, że nic się nie zmieniło.

Drugi ładny pomysł tego etapu: **artefaktem po czerwonym buildzie jest
nagranie.** W backendzie po awarii masz stacktrace i log — dwa teksty, i to
wystarcza, bo funkcja albo rzuciła, albo nie. Tutaj przyczyna jest rozłożona
w czasie i w kilku procesach: kolejność wiadomości, zgubiona ramka, callback,
który trwał 40 ms za długo. Żadne pojedyncze zdanie tego nie opisze. Nagranie
— tak, bo jest **odtwarzalne**, więc czerwony build zamienia się w fixture
z etapu [03](./03-bagi-jako-dane.md), zanim zdążysz zapomnieć, o co chodziło.

Trzeci: symulacja w CI ma sens **wyłącznie dzięki zegarowi symulacji**. Test
integracyjny mierzący czas rzeczywisty na współdzielonym runnerze jest
losowaniem. Ten sam test na `/clock` z Gazebo jest deterministyczny, bo czas
przestaje być zasobem konkurencyjnym.

## Dlaczego to trudne

**Migotliwość jest tu domyślna, nie wyjątkowa.** W backendzie flaky test to
zwykle twój błąd — wyścig, którego nie widzisz. Tutaj dochodzi warstwa, której
nie kontrolujesz: odkrywanie węzłów przez DDS trwa nieokreślony czas, a
`BEST_EFFORT` na `/vacuum_pressure` **ma prawo gubić wiadomości** i robi to
częściej na obciążonym runnerze niż na twoim laptopie. Test, który zakłada, że
dostanie 25 próbek, dostanie ich 23 i padnie — poprawnie, tylko nie o tym, co
sprawdzałeś.

**Złote nagrania nie są w repozytorium.** `.gitignore` wycina `**/bags/`
i `*.mcap` — słusznie, bo to setki megabajtów danych odtwarzalnych. Ale CI,
który ma odtworzyć złote nagranie, nie ma skąd go wziąć. To jest realny
problem do rozwiązania, nie detal.

**Środowisko w CI nie jest tym samym środowiskiem, nawet gdy jest tym samym
obrazem.** UID użytkownika, rozmiar `/dev/shm`, brak terminala, inna liczba
rdzeni. Każda z tych rzeczy potrafi zmienić wynik testu ROS-owego.

**Wiedza plemienna, której nie ma w dokumentacji:** że `tc netem` na `lo` nie
dotknie ruchu DDS, bo Fast DDS między procesami na jednej maszynie idzie przez
pamięć dzieloną (stąd `--ipc=host` w `runArgs`). Że domyślne 64 MB `/dev/shm`
w kontenerze potrafi wysypać discovery. Że `~/.ros/log` w kontenerze to
katalog domowy użytkownika `ubuntu`, a nie twój — więc po zakończeniu zadania
znika razem z kontenerem, jeśli go stamtąd nie wyniosłeś.

## Model pojęciowy

### Dwie drogi do CI i dlaczego wybieramy trudniejszą

| | (a) gotowe akcje ROS-a | (b) obraz z `.devcontainer/Containerfile` |
|---|---|---|
| co to jest | `ros-tooling/setup-ros` stawia ROS-a na runnerze, `ros-tooling/action-ros-ci` robi build + test + coverage | budujesz ten sam obraz, w którym pracujesz, i w nim wołasz `colcon` |
| czas pierwszego przebiegu | 3–6 minut | 8–15 minut (pełny build obrazu) |
| czas kolejnego | podobny | 2–4 minuty (obraz z rejestru) |
| co testuje | twój kod w **cudzym** środowisku | twój kod w **twoim** środowisku |
| kiedy dowiesz się o dryfie obrazu | nigdy | tej samej nocy |
| ile utrzymania | mało | trzeba ogarnąć rejestr i cache warstw |

**Bierzemy (b).** Uzasadnienie jest maksymą tego repo, a nie gustem:
**środowisko jest OPISANE jednym plikiem** — tak mówi komentarz w
`devcontainer.json` i tak zbudowane jest całe `scripts/`. Jeśli CI postawi
sobie własnego ROS-a przez `setup-ros`, to repo ma nagle **dwa źródła prawdy
o środowisku**: `Containerfile` dla ciebie i workflow dla CI. Rozjadą się —
nie „jeśli", tylko „kiedy", i to zwykle przy pakiecie, który dopisałeś tylko
w jednym miejscu. Zielony CI przestaje wtedy znaczyć „u mnie też zadziała".

Koszt tej decyzji jest realny: build obrazu jest wolny i ciężki. Zbijasz go
tak:

1. **Obraz buduje osobny przepływ**, wyzwalany tylko zmianą `.devcontainer/**`
   (plus raz na dobę, jako czujnik dryfu). Publikuje gotowy obraz do GHCR.
2. **Przepływ testowy obraz tylko pobiera.** Zwykły PR nie płaci za build.
3. **Warstwy w `Containerfile` uporządkowane od najrzadziej zmiennej**: `apt`
   przed czymkolwiek, co ruszasz co tydzień. Jedna zmiana w ostatniej
   linijce nie może unieważniać instalacji ROS-owych pakietów.
4. **Baza przypięta cyfrowo**, nie tagiem: `FROM docker.io/osrf/ros@sha256:…`
   w przepływie nocnym porównujesz z ruchomym tagiem i dostajesz PR-a, gdy
   się różnią. Wtedy dryf jest zdarzeniem, a nie niespodzianką.

Jest jeszcze jedna korzyść, specyficzna dla tego repo. `scripts/lib/container.sh`
rozpoznaje kontener po pliku `/run/.containerenv` — **który tworzy podman, a
nie docker**. Jeśli w CI uruchomisz obraz podmanem (runnery Ubuntu mają go
w obrazie; sprawdź `podman --version`), to `scripts/dev/build-colcon-workspace.sh`
zadziała w CI *bez żadnej zmiany*, bo `run-in-devcontainer` uzna, że jest już
na miejscu. Trzecia strona granicy dostaje to samo polecenie za darmo. Z
dockerem trzeba by je przepisać w workflow — czyli zrobić dokładnie tę drugą
kopię prawdy, której unikamy.

### Kolejność: od najtańszego, bo informacja jest ważniejsza niż kompletność

| szczebel | czas | co ci mówi porażka |
|---|---|---|
| ruff (`check` + `format --check`) | ~2 s | dokładnie: plik i linia. Nie potrzebuje ROS-a ani obrazu — leci **przed** buildem obrazu |
| testy czystej logiki (progi, `is_at_level`) | ~1 s | „ta funkcja liczy źle" — najwęższa możliwa informacja |
| testy węzła (callback wołany wprost, bez DDS) | 2–5 s | „węzeł źle reaguje na tę wiadomość"; wciąż deterministyczne |
| `launch_testing` (procesy, prawdziwy DDS) | 10–60 s | „te dwa węzły się nie dogadują" — pierwszy szczebel, który potrafi migotać |
| złote nagranie + progi z etapu 10 | 1–3 min | „detektor się pogorszył o tyle i tyle" — porażka ilościowa, nie binarna |
| symulacja bezgłowa (nocna) | 5–60 min | „cała cela nie wykonuje cyklu" — najszersza informacja i najdroższa |

Reguła jest prosta: **im wyżej, tym dłużej i tym mniej precyzyjnie**. Padnięty
`launch_testing` mówi ci, że coś jest nie tak między dwoma procesami — i nic
więcej. Padnięty test czystej logiki mówi, w której linii. Dlatego drogie
szczeble odpalasz dopiero, gdy tanie są zielone: nie dlatego, że oszczędzasz
minuty CI, tylko dlatego, że **nie chcesz diagnozować literówki przez
symulator**.

### Artefakty: bez czego czerwony build jest bezużyteczny

Czerwony build, przy którym widzisz wyłącznie „exit code 1", kosztuje cię
godzinę odtwarzania sytuacji lokalnie. Cztery rzeczy, które muszą wyjechać
z kontenera **zawsze, także po porażce** (`if: always()` na kroku zbierającym):

| artefakt | skąd | po co |
|---|---|---|
| wyniki testów maszynowo | `ws/build/<pakiet>/pytest.xml` (JUnit; sprawdź `ls ws/build/grip_monitor/*.xml`) oraz `colcon test-result --all --verbose` | żeby widzieć **który** test padł i z jakim komunikatem, bez czytania 4000 linii logu |
| logi ROS-a | `~/.ros/log/` — ale w kontenerze to `$HOME` użytkownika `ubuntu`, więc ustaw `ROS_LOG_DIR` na ścieżkę wewnątrz repo | cała ściana z `/rosout` i stderr każdego węzła, w tym ostrzeżenia RMW o QoS |
| nagranie z przebiegu | `ros2 bag record` włączony w teście integracyjnym i symulacyjnym | **to jest ta różnica wobec backendu**: nie „co się wywaliło", tylko „co leciało przez system w sekundzie 7,3" |
| wykresy z ewaluacji | PNG i JSON ze skryptu z etapu [10](./10-ewaluacja-na-danych.md) | porażka progu jest liczbą; wykres mówi, czy przesunął się cały rozkład, czy dorzuciłeś jeden ogon |

Nagranie z CI jest najcenniejsze i najczęściej pomijane. Jeśli test
integracyjny zapisuje bag do katalogu artefaktów, to czerwony build w PR-cie
daje ci plik, który **odtworzysz u siebie** poleceniem `ros2 bag play`.
Sprawa przechodzi z „nie umiem tego powtórzyć" do „mam to na dysku" w jednym
kroku. Pilnuj tylko rozmiaru — 21 sekund `/vacuum_pressure` to około 2000
wiadomości, ale godzina symulacji z obrazem to gigabajty; nagrywaj wtedy
wybrane topiki, nie `--all`.

### Migotliwość jako osobny problem inżynierski

Test z prawdziwym DDS jest niedeterministyczny **z natury**. Nie jest to wada
do usunięcia, tylko właściwość do obsłużenia. Cztery reguły:

1. **Izolacja przez `ROS_DOMAIN_ID` per zadanie.** Dwa przebiegi na tym samym
   self-hosted runnerze zobaczą nawzajem swoje węzły i będą wysyłać sobie
   dane. Nadawaj domenę z numeru przebiegu (bezpieczny zakres to 0–101) i
   dołóż `ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST`, żeby ruch nie wyszedł poza
   maszynę. (W Jazzy to następca `ROS_LOCALHOST_ONLY`, który jest oznaczony
   jako przestarzały.)
2. **Zero stałych `sleep`.** `time.sleep(2)` znaczy „mam nadzieję, że discovery
   zdąży" i na obciążonym runnerze nie zdąży. Czekasz **na zdarzenie**:
   pierwsza wiadomość, `wait_for_service`, licznik nadawców różny od zera.
3. **Limit czasu na każdym oczekiwaniu.** Oczekiwanie bez limitu w CI to
   zadanie wiszące 6 godzin i zabite przez platformę, bez żadnej informacji.
   Limit zamienia to w czytelną porażkę: „nie doczekałem się werdyktu w 5 s".
4. **Ponowienie jest sygnałem, nie lekarstwem.** Jeśli dodajesz retry, to musi
   on być **liczony i raportowany**. Retry, którego nie widać w podsumowaniu,
   to nie stabilizacja tylko ukrycie danych — a dane mówiły, że coś jest za
   wolne albo za ciasne.

Zamiast wyłączać migotliwy test, **wpisz go do rejestru**. Plik
`docs/testy-migotliwe.md`, jeden wiersz na test:

| test | pierwsze migotanie | jak często | podejrzenie | przy jakim limicie padał | termin |
|---|---|---|---|---|---|
| `test_werdykt_po_starcie` | 2026-09-14 | 1 na 12 | discovery > 2 s przy zajętym runnerze | 2 s | 2026-09-28 |

Rejestr działa dlatego, że robi z migotania **dług z terminem**, a nie stan
stały. Test zostaje włączony i dalej potrafi zaczerwienić build — bo test
wyłączony przestaje cokolwiek chronić w tej samej minucie, w której go
wyłączyłeś, tylko nikt tego nie zauważa. Reguła domykająca: wiersz starszy niż
dwa tygodnie kończy się albo naprawą, albo skasowaniem testu. Trzeciej opcji
nie ma.

### Symulacja w CI: kiedy warto zapłacić

Serwer Gazebo chodzi bezgłowo (etap [07](./07-gazebo-stanowisko.md)), więc
technicznie da się. Pytanie brzmi: kiedy to się opłaca.

**Kryterium:** test symulacyjny sprawdza **integrację**, nigdy logikę.

| to trzymaj w symulacji | to trzymaj niżej |
|---|---|
| czy sterowniki z `ros2_control` w ogóle wstają | czy próg -59 jest dobrze dobrany |
| czy most `ros_gz_bridge` przenosi dane w obie strony | czy `is_at_level` liczy poprawnie |
| czy cela wykonuje pełny cykl: podejście, chwyt, uniesienie, werdykt | czy NaN nie ucisza detektora |
| czy TF spina się w jedno drzewo | czy werdykt leci raz na zmianę stanu |

Jeżeli test dałoby się napisać bez symulatora, to **musi** być napisany bez
symulatora. Symulator w CI jest wart swojej ceny tylko wtedy, gdy sprawdza
rzeczy, które istnieją wyłącznie przy złożeniu wszystkiego razem.

I jedna rzecz warunkuje całą resztę: **zegar symulacji**. Węzły startujesz
z `use_sim_time:=true`, Gazebo publikuje `/clock`, a wtedy czas przestaje być
zasobem współdzielonym z innymi zadaniami na runnerze. Test typu „werdykt ma
przyjść w ciągu 200 ms od zamknięcia chwytaka" mierzony zegarem ściennym jest
losowaniem; ten sam test na zegarze symulacji jest powtarzalny. **To jest
jedyny powód, dla którego test symulacyjny da się w ogóle trzymać w CI** — bez
tego byłby generatorem migotania i wyleciałby po miesiącu.

### Katalog awarii

To jest druga połowa etapu i to jest rzecz, która zostaje z tobą na lata.
Katalog mieszka w `projects/grab-fail-detection/awarie/` — jeden plik na
awarię, `README.md` jako spis. Każda pozycja odpowiada na cztery pytania:
**jak wywołać / co powinno się stać / czym to zobaczysz / w co to zamieniasz**.

| awaria | jak wywołać | co powinno się stać | czym to zobaczysz | w co zamieniasz |
|---|---|---|---|---|
| śmierć węzła | `pkill -f vacuum_sensor` w trakcie pracy | diagnostyka po ~1 s mówi STALE, werdykt przestaje być „świeży" | `show-topic-connections.sh /vacuum_pressure` → Publisher count 0; `/diagnostics` | test `launch_testing` + pozycja STALE z etapu [06](./06-logi-diagnostyka-lifecycle.md) |
| NaN w danych | `ros2 topic pub -r 5 /vacuum_pressure std_msgs/msg/Float32 '{data: .nan}'` | próbka odrzucona, licznik odrzuceń rośnie, werdykt leci dalej | dziś: cisza na `/grasp_verdict` przy żywym węźle | test jednostkowy (zadanie 11.5) |
| wartość poza zakresem | to samo z `'{data: -1000.0}'` | werdykt `unknown`, ostrzeżenie w logu | `measure-topic-rate.sh /grasp_verdict` → cisza | brakujący `else` + test |
| skok wartości | `state:=open` → `state:=sealed` przez `set-param.sh` | jeden werdykt na zmianę stanu | seria fałszywych `leak` w trakcie przejścia (średnia z 25 próbek przechodzi przez pas przecieku) | metryka „werdyktów na zmianę stanu" z etapu 10 |
| niedopasowane QoS | zmień `ReliabilityPolicy` w `grasp_monitor.py` na `RELIABLE` | brak dopasowania, coś to zgłasza | oba węzły żyją, dane nie płyną; `show-topic-connections.sh` pokazuje różne QoS po obu stronach — patrz etap [05](./05-introspekcja-qos-narzedzia.md) | pozycja diagnostyki „brak dopasowanego nadawcy" |
| gubienie wiadomości | `ros2 run topic_tools drop /vacuum_pressure 9 10 /dziurawe` + monitor z `-r vacuum_pressure:=dziurawe` | okno 25 próbek przestaje znaczyć 0,5 s — opóźnienie werdyktu rośnie 10× | `measure-topic-rate.sh` na obu topikach | test: okno liczone w **czasie**, nie w próbkach |
| opóźnianie | `ros2 run topic_tools throttle messages /vacuum_pressure 5 /wolne` | jak wyżej, plus przeterminowane dane | różnica stempli czasu (etap [02](./02-czas-zdarzenia-stan.md)) | próg wieku próbki |
| obciążenie CPU | `for _ in $(seq $(nproc)); do yes > /dev/null & done`, sprzątasz `pkill -x yes` | częstotliwość spada łagodnie, nie skokowo; system o tym mówi | `measure-topic-rate.sh /vacuum_pressure`; opóźnienie callbacków z etapu [09](./09-latencja-i-tracing.md) | próg na p95 opóźnienia |
| skok zegara | `ros2 bag play --loop --clock` + węzły z `use_sim_time:=true` | brak wybuchu na granicy pętli, bufory czyszczone | ujemne różnice stempli w logu | test odporności na cofnięcie czasu |
| pełny dysk przy nagrywaniu | tmpfs 20 MB wpięty przez `mounts` w `devcontainer.json`, `ros2 bag record -o /maly-dysk/proba` | nagrywanie kończy się **komunikatem**, węzły pracują dalej | co zostało w katalogu bagu i czy da się go odtworzyć | pozycja diagnostyki „mało miejsca" |
| dwóch nadawców | drugi czujnik: `run-node.sh grip_monitor vacuum_sensor --ros-args -r __node:=vacuum_sensor_b -p state:=open` przy pierwszym na `sealed` | wykrycie i zgłoszenie dwóch źródeł | detektor melduje `leak` — bo średnia z -59 i 0 to ≈ -29,5, czyli **środek pasa przecieku**; przeciek, którego nigdy nie było | kontrola liczby nadawców przy starcie |

Ostatni wiersz jest wart chwili. Dwa poprawne czujniki, żaden nie jest
uszkodzony, żaden nie kłamie — a detektor z pełnym przekonaniem raportuje stan
fizycznie nieistniejący. To nie jest awaria danych, tylko awaria **założenia**,
że na topiku jest jeden nadawca. W backendzie dwa procesy piszące do jednej
kolejki są normą; tutaj są cichą korupcją.

O `tc netem` — dwa ostrzeżenia, bo to najczęściej polecane i najgorzej
działające narzędzie w tym zestawie. Po pierwsze, w kontenerze bez
`CAP_NET_ADMIN` (a rootless podman go domyślnie nie daje) `tc` odmówi.
Po drugie, i ważniejsze: `runArgs` zawiera `--network=host`, więc kontener
**dzieli stos sieciowy z twoją Fedorą** — gdyby uprawnienia były, grzebałbyś
w sieci hosta, nie w sandboksie. A na dokładkę i tak by to nic nie dało: przy
`--ipc=host` Fast DDS między procesami na jednej maszynie idzie przez pamięć
dzieloną, więc `netem` na `lo` nie dotknie tego ruchu. Musiałbyś najpierw
wyłączyć transport SHM profilem XML przez `FASTRTPS_DEFAULT_PROFILES_FILE`.
**Bezpieczniejsza i uczciwsza alternatywa jest na poziomie ROS-a:**
`topic_tools drop` i `throttle` albo własny węzeł-przekaźnik, który gubi,
opóźnia i przekłamuje na parametr. Gubi te same wiadomości, nie dotyka
niczyjej sieci i da się go wpiąć do testu.

### Pętla, która robi z tego zawód

> **awaria w polu → nagranie → odtworzenie → test regresji → dopiero potem poprawka**

Kolejność jest całą treścią. Kuszące jest odwrotnie: widzisz przyczynę,
poprawiasz w trzy minuty, zamykasz zgłoszenie. Tylko że **poprawka bez testu
jest hipotezą** — sprawdziłeś ją raz, ręcznie, w warunkach, których już nie
odtworzysz. Nie masz dowodu, że trafiłeś w przyczynę, a nie w objaw.

W robotyce jest drugi powód, mocniejszy. Ta sama awaria wraca za trzy
miesiące. Wraca, bo ktoś czyści kod, widzi dziwny warunek bez komentarza
i go usuwa — słusznie, bo nic nie mówi, po co tam jest. **Test jest jedyną
formą komentarza, która potrafi się bronić.** Warunek `if not isfinite(measure)`
bez testu to śmieć, który zniknie przy pierwszym refaktorze. Ten sam warunek
z testem nazwanym `test_nan_nie_ucisza_detektora` jest udokumentowanym
wymaganiem — i usunięcie go zapala czerwone światło w PR-cie tego, kto
sprząta.

Praktycznie: krokiem drugim jest **zapisanie nagrania do katalogu awarii**
razem z opisem, a nie „mam to w pamięci". Krok trzeci — odtworzenie —
jest bramką: jeśli z nagrania nie potrafisz wywołać awarii ponownie, to nie
rozumiesz jej jeszcze i poprawka byłaby zgadywaniem.

### Testy długotrwałe: czego szuka godzina

| co obserwujesz | jak mierzysz | dlaczego 30-sekundowy test tego nie znajdzie |
|---|---|---|
| wyciek pamięci | `VmRSS` z `/proc/<pid>/status`, próbkowane co 5 s | przyrost rzędu kilobajtów na minutę tonie w szumie alokatora; widać go dopiero jako trend |
| rosnąca liczba deskryptorów | `ls /proc/<pid>/fd | wc -l` | limit to zwykle 1024; przy jednym wycieku na sekundę pierwsze `EMFILE` przychodzi po 17 minutach |
| dryf zegara | różnica `/clock` i czasu ściennego | dryf to promil — po 30 s daje 30 ms, po godzinie 3,6 s, i dopiero wtedy psuje synchronizację |
| degradacja częstotliwości | `ros2 topic hz` zapisywany do pliku, nie na ekran | spadek 50 → 48 Hz mieści się w wariancji krótkiego pomiaru |
| pęczniejący bufor TF | rozmiar bufora / zużycie pamięci węzła słuchającego TF | bufor domyślnie trzyma 10 s historii; problem zaczyna się, gdy ktoś publikuje transformaty szybciej, niż wygasają |

Wspólny mianownik: **to są zjawiska w pochodnej, nie w wartości.** Test
30-sekundowy sprawdza, czy wartość jest poprawna teraz. Te błędy mają
poprawną wartość przez cały czas trwania takiego testu i psują się dopiero
z nachylenia. Stąd jedyne sensowne asercje nocnego przebiegu nie brzmią
„RSS < 300 MB", tylko **„przyrost RSS między 10. a 60. minutą jest mniejszy
niż X MB"** — porównujesz nachylenie, a nie poziom, bo poziom zależy od tego,
co ten proces akurat robił.

## Zadania

### Zadanie 11.1 — Przepływ CI na obrazie z `Containerfile` (rdzeń)

**Cel:** każdy PR buduje ten sam obraz, w którym pracujesz, i uruchamia w nim
lint oraz testy.

Dwa pliki. Pierwszy, `.github/workflows/obraz.yml`, buduje i publikuje obraz
do GHCR przy zmianie `.devcontainer/**` oraz raz na dobę (`schedule`) — to
jest twój czujnik dryfu. Drugi, `.github/workflows/ci.yml`, obraz tylko
pobiera:

```yaml
name: ci

on:
  push:
    branches: [master]
  pull_request:
  workflow_dispatch:

env:
  # Ta sama ścieżka co na Fedorze i w workspaceMount z devcontainer.json.
  # Dzięki temu /etc/profile.d/ros2.sh z Containerfile trafia w istniejące
  # ws/install/setup.bash i nic nie trzeba tłumaczyć.
  REPO: /home/maniumek/repos/robotics

jobs:
  lint:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      # Ta sama wersja, którą przypiąłeś w Containerfile — inaczej CI
      # i Ctrl+S w edytorze będą się kłóciły o formatowanie.
      - run: pip install "ruff==<wersja z Containerfile>"
      - run: ruff check .
      - run: ruff format --check .

  testy:
    needs: lint          # najtańsze pierwsze; bez tego nie ma po co budować
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4

      - name: Obraz środowiska
        run: podman pull "ghcr.io/${{ github.repository_owner }}/robotics-ros2:latest"

      - name: Build i testy
        run: |
          podman run --rm \
            -v "$GITHUB_WORKSPACE:$REPO" -w "$REPO" \
            --shm-size=1g \
            --userns=keep-id:uid=1000,gid=1000 \
            -e ROS_DOMAIN_ID=$(( GITHUB_RUN_NUMBER % 100 + 1 )) \
            -e ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST \
            -e ROS_LOG_DIR="$REPO/artefakty/ros-log" \
            "ghcr.io/${{ github.repository_owner }}/robotics-ros2:latest" \
            bash -lc '
              scripts/dev/build-colcon-workspace.sh &&
              cd ws && colcon test --event-handlers console_direct+ &&
              colcon test-result --all --verbose
            '
```

Zwróć uwagę na `scripts/dev/build-colcon-workspace.sh` w środku: to jest
**dokładnie ten sam skrypt**, który odpalasz z Ghostty. Działa, bo podman
tworzy `/run/.containerenv`, a `scripts/lib/container.sh` po tym pliku
rozpoznaje, że jest już na miejscu. Z dockerem trzeba by wkleić `colcon build`
drugi raz do workflow.

Rozdziel też testy tanie od drogich markerem pytesta (`@pytest.mark.wolne`
zarejestrowany w `setup.cfg`) i odpalaj je osobnymi krokami:
`colcon test --pytest-args -m "not wolne"` przed `-m wolne`.

**Gotowe, gdy:** PR z celowo zepsutym formatowaniem pada w zadaniu `lint`
w kilkanaście sekund i nie dochodzi do budowania; PR z zepsutą logiką
przechodzi lint i pada w `testy`, a w logu widać nazwę testu.

### Zadanie 11.2 — Artefakty (rdzeń)

**Cel:** z czerwonego przebiegu wychodzi paczka, z którą umiesz pracować
lokalnie.

```yaml
      - name: Artefakty
        if: always()         # BEZ TEGO nie wykona się właśnie wtedy, gdy jest potrzebne
        uses: actions/upload-artifact@v4
        with:
          name: przebieg-${{ github.run_number }}
          path: |
            ws/build/**/pytest.xml
            ws/log/latest_test/**
            artefakty/**
          retention-days: 14
          if-no-files-found: warn
```

Trzy rzeczy do zrobienia poza samym krokiem: ustaw `ROS_LOG_DIR` na ścieżkę
wewnątrz repo (jest wyżej w `podman run`) — inaczej `~/.ros/log` zostanie
w kontenerze i zniknie razem z nim. Włącz `ros2 bag record` w teście
integracyjnym z zapisem do `artefakty/`, wybranych topików, nie `--all`.
Podłącz renderowanie JUnit XML w podsumowaniu PR-a (np. akcją
`EnricoMi/publish-unit-test-result-action`), żeby nie otwierać logów po to,
by dowiedzieć się, który test padł.

**Gotowe, gdy:** ściągasz artefakt z czerwonego przebiegu, robisz
`ros2 bag play` na nagraniu z niego i widzisz u siebie ten sam przebieg.

### Zadanie 11.3 — Bramka na złotych nagraniach (rdzeń)

**Cel:** pogorszenie detektora zatrzymuje PR-a, zanim ktokolwiek go obejrzy.

Problem do rozwiązania najpierw: `**/bags/` i `*.mcap` są w `.gitignore`,
więc CI nie ma złotego nagrania. Nie wyłączaj tego wpisu. Zamiast tego wypchnij
nagranie jako asset GitHubowego release'u (`dane-v1`), a do repo dodaj **samą
sumę kontrolną** — plik `projects/grab-fail-detection/bags.sha256`. Wtedy
„które nagranie" jest zapisane w gicie i widać w diffie, gdy się zmieni.

```yaml
      - name: Złote nagranie
        run: |
          mkdir -p projects/grab-fail-detection/bags
          curl -sSLf -o /tmp/zlote.tar.gz \
            "https://github.com/${{ github.repository }}/releases/download/dane-v1/chwyt-3-stany.tar.gz"
          sha256sum -c projects/grab-fail-detection/bags.sha256
          tar -C projects/grab-fail-detection/bags -xzf /tmp/zlote.tar.gz
```

Progi trzymaj w `projects/grab-fail-detection/eval/progi.yaml` — w repo,
nie w workflow. Zmiana progu ma być widoczna w PR-cie jak zmiana kodu:

```yaml
f1_sealed_min: 0.95
opoznienie_p95_ms_max: 120
werdyktow_na_zmiane_stanu_max: 1
```

Ostatni próg jest tutaj najciekawszy: pilnuje, żeby nikt nie przywrócił
detekcji zbocza do stanu zakomentowanego, w jakim jest dzisiaj w
`grasp_monitor.py`. Bramka to twój skrypt z etapu 10 uruchomiony na
nagraniu — jedyne, co musi robić, to **zwrócić niezerowy kod wyjścia i
wypisać, która metryka i o ile nie trafiła**.

**Gotowe, gdy:** podnosisz `f1_sealed_min` do 0.999, CI pada i mówi, o ile
zabrakło; wracasz i jest zielono.

### Zadanie 11.4 — Katalog awarii w repo (rdzeń)

**Cel:** awarie przestają być anegdotami, a stają się listą, którą da się
odpalić.

Załóż `projects/grab-fail-detection/awarie/` z `README.md` jako spisem i
jednym plikiem na pozycję z tabeli z sekcji „Katalog awarii". Każdy plik ma
cztery nagłówki: **Jak wywołać / Co powinno się stać / Czym to zobaczysz /
W co to zamieniasz** — plus miejsce na nagranie, gdy już je masz.

Dołóż jeden skrypt: `scripts/dev/ros2/inject-fault.sh NAZWA`, a bez argumentu
wypisujący katalog. Nowy przedrostek `inject-` dopisz do tabeli w `AGENTS.md`,
bo konwencja tego repo wymaga, żeby czasownik mówił dwie rzeczy: skrypt
**trzyma terminal do Ctrl+C** i **zmienia to, co widzą inne węzły**. Revertu
nie potrzebuje — nic z tego nie przeżywa procesu, dokładnie jak `run-` i `set-`.

**Gotowe, gdy:** `scripts/dev/ros2/inject-fault.sh` bez argumentu wypisuje
listę awarii, a `inject-fault.sh nan` w drugim terminalu ucisza
`/grasp_verdict` przy działającym systemie.

### Zadanie 11.5 — „Zepsuj to": NaN (rdzeń, obowiązkowe)

**Cel:** przejść pełną pętlę na jednym małym prawdziwym błędzie —
wstrzyknięcie, cisza, test, poprawka, zielono.

**Krok 1 — wstrzyknij.** Uruchom czujnik i detektor, potwierdź werdykty
(`measure-topic-rate.sh /grasp_verdict`), a potem z trzeciego terminala:

```bash
ros2 topic pub -r 5 /vacuum_pressure std_msgs/msg/Float32 '{data: .nan}'
```

Pięć wiadomości na sekundę przy pięćdziesięciu z czujnika — jedna na
jedenaście — i wyjście milknie **całkowicie**. Wystarczy tyle, bo okno to 25
próbek, czyli około 0,5 s, więc zawsze co najmniej jeden NaN w nim siedzi.

**Krok 2 — zobacz ciszę i to, że nikt jej nie zgłasza.** `/grasp_verdict`
nie ma wiadomości. `list-running-nodes.sh` nadal pokazuje `/grasp_monitor`.
W logu nic. `show-topic-connections.sh /vacuum_pressure` pokazuje dwóch
nadawców i jednego odbiorcę — wszystko „zdrowe". Prześledź, dlaczego:
`np.mean` na oknie z NaN daje NaN; `is_at_level(nan, 0)` sprawdza
`-1 < nan`, co jest fałszem; `nan < -1` też fałsz; `is_at_level(nan, -59)`
też. **Każde porównanie z NaN jest fałszem**, więc żaden z trzech `if` nie
strzela i nie ma `else`, który by to złapał. Detektor nie pada — on cicho
przestaje mieć zdanie.

**Krok 3 — napisz test, który tę ciszę wyłapuje.** Do
`ws/src/grip_monitor/test/test_grasp_monitor_awarie.py`:

```python
from types import SimpleNamespace

import rclpy
from std_msgs.msg import Float32

from grip_monitor.grasp_monitor import GraspMonitor


def probka(wartosc: float) -> Float32:
    msg = Float32()
    msg.data = wartosc
    return msg


def test_nan_nie_ucisza_detektora():
    rclpy.init()
    try:
        node = GraspMonitor()
        # Podmieniamy publisher na listę: bez DDS, bez czekania, bez migotania.
        werdykty = []
        node.pub = SimpleNamespace(publish=lambda m: werdykty.append(m.data))

        for _ in range(25):
            node.on_measurement(probka(-59.0))
        assert werdykty, 'detektor milczy juz na poprawnych danych'

        przed = len(werdykty)
        node.on_measurement(probka(float('nan')))
        for _ in range(5):
            node.on_measurement(probka(-59.0))

        assert len(werdykty) > przed, (
            f'po jednej probce NaN detektor zamilkl: {przed} werdyktow przed, '
            f'{len(werdykty)} po pieciu poprawnych probkach'
        )
        node.destroy_node()
    finally:
        rclpy.shutdown()
```

Uruchom go **teraz**, przed poprawką. Ma paść. Test, który nigdy nie zapalił
się na czerwono, nie jest testem.

**Krok 4 — napraw.** Złe dane odrzucasz **na granicy**, żeby nigdy nie weszły
do okna:

```python
from math import isfinite

    def on_measurement(self, msg: Float32):
        measure = msg.data

        if not isfinite(measure):
            self.odrzucone += 1
            self.get_logger().warn(
                f'niepoprawna probka ({measure}), odrzucona; razem {self.odrzucone}',
                throttle_duration_sec=1.0,
            )
            return

        self.frame.append(measure)
```

`throttle_duration_sec` jest tu obowiązkowe: bez niego przy 50 Hz zalejesz
`/rosout` i sam zrobisz sobie drugą awarię. Licznik `self.odrzucone` wystaw
potem jako pozycję diagnostyki z etapu 06 — wtedy „dostaję śmieci" przestaje
być czymś, co widać tylko w logu.

**Krok 5 — zazieleń i domknij.** Test przechodzi. Powtórz wstrzyknięcie
z kroku 1: werdykty lecą dalej, w logu raz na sekundę leci ostrzeżenie.
Potem zrób drugą połowę: dopisz `else`, który przy `mean` spoza wszystkich
trzech pasów publikuje `unknown`, i test z wartością -1000.0. To jest ta sama
awaria co NaN, tylko z innej strony — brak reprezentacji stanu „nie wiem".

**Gotowe, gdy:** `colcon test` był czerwony przed poprawką i jest zielony po,
a wstrzykiwanie NaN przy działającym systemie nie ucisza `/grasp_verdict`
i zostawia ślad w logu.

### Zadanie 11.6 — Druga awaria jako test automatyczny (rdzeń)

**Cel:** śmierć czujnika przestaje być nieodróżnialna od ciszy detektora.

Awaria z pierwszego wiersza katalogu, tym razem jako test `launch_testing`
(szkielet i mechanika — etap [04](./04-piramida-testow.md), tutaj tylko go
mnożysz). Kształt:

1. opis testowy startuje `vacuum_sensor` i `grasp_monitor`,
2. test czeka **na zdarzenie** — pierwszy werdykt na `/grasp_verdict`,
   z limitem czasu 5 s, nie na `sleep`,
3. `subprocess.run(['pkill', '-f', 'vacuum_sensor'])`,
4. asercja: w ciągu 2 s na `/diagnostics` pojawia się STALE dla
   `/vacuum_pressure` (pozycja z etapu 06),
5. `launch_testing` odnotowuje wyjście procesu, więc możesz dodatkowo
   sprawdzić, że zginął tak, jak myślisz.

Jeśli po etapie 06 nie masz pozycji STALE, ten test jest właśnie powodem,
żeby tam wrócić. Dodaj mu marker `wolne` — należy do szczebla, który potrafi
migotać, więc idzie w osobnym kroku CI.

**Gotowe, gdy:** test pada na repo bez diagnostyki STALE i przechodzi z nią,
a w artefaktach z przebiegu widać log z chwili zabicia czujnika.

### Zadanie 11.7 — Nocny przebieg z wykresami (rozszerzenie)

**Cel:** zobaczyć klasę błędów, której nie znajdzie żaden test 30-sekundowy.

Osobny przepływ z `schedule` (cron), godzina symulacji bezgłowej z etapu 07,
węzły na `use_sim_time:=true`. Obok nich prosty samplownik co 5 s do CSV:
`VmRSS` z `/proc/<pid>/status`, liczba deskryptorów z `ls /proc/<pid>/fd | wc -l`,
zmierzona częstotliwość `/vacuum_pressure` i `/grasp_verdict`, różnica między
`/clock` a zegarem ściennym. Na końcu matplotlib rysuje cztery panele w czasie
i wrzucasz PNG plus CSV do artefaktów.

Asercja liczy **nachylenie, nie poziom**: przyrost RSS między 10. a 60. minutą
poniżej progu, liczba deskryptorów bez trendu, mediana częstotliwości w
ostatnich 10 minutach nie niższa niż w pierwszych 10 o więcej niż 2%.

**Gotowe, gdy:** masz wykres z godziny przebiegu i potrafisz z niego
powiedzieć, czy RSS rośnie, czy tylko faluje — a po celowym wstawieniu wycieku
(lista, do której dopisujesz każdą próbkę i nigdy jej nie czyścisz) widać go
na wykresie i nocny przebieg pada.

## Pułapki

| objaw | przyczyna | co zrobić |
|---|---|---|
| w CI `colcon build` przechodzi, a `ros2 run` mówi „package not found" | polecenie poszło przez powłokę nielogowaniową, więc `/etc/profile.d/ros2.sh` się nie wykonał | zawsze `bash -lc`; i montuj repo pod `/home/maniumek/repos/robotics`, bo tę ścieżkę ma wpisaną `Containerfile` |
| testy DDS w CI wiszą albo gubią wiadomości bez powodu | domyślne `/dev/shm` w kontenerze ma 64 MB, Fast DDS się w tym dusi | `--shm-size=1g` przy `podman run` |
| „permission denied" przy `ws/build` w CI | użytkownik w obrazie to `ubuntu` (UID 1000), a runner ma UID 1001 | `--userns=keep-id:uid=1000,gid=1000`; przy starszym podmanie `--user root` i `chown` po fakcie |
| artefaktów nie ma dokładnie przy czerwonym buildzie | krok zbierający bez `if: always()` nie wykonuje się po porażce | `if: always()` na każdym kroku artefaktowym |
| `~/.ros/log` w artefaktach pusty | to `$HOME` użytkownika `ubuntu` **w kontenerze**, nie twój katalog i nie repo | `ROS_LOG_DIR` na ścieżkę wewnątrz zamontowanego repo |
| bramka na złotym nagraniu pada z „no such file" | `**/bags/` i `*.mcap` są w `.gitignore`, w checkoucie ich nie ma | pobieraj z release'u i weryfikuj `sha256sum -c` z pliku w repo |
| `tc netem` w kontenerze: „Operation not permitted" | rootless podman nie daje `CAP_NET_ADMIN` | rób to na poziomie ROS-a (`topic_tools drop`/`throttle`); i tak nie ruszyłbyś ruchu SHM |
| `netem` założony z hosta nic nie zmienia | Fast DDS na jednej maszynie nie idzie przez `lo`, tylko przez pamięć dzieloną | wyłącz SHM profilem XML (`FASTRTPS_DEFAULT_PROFILES_FILE`) albo zrezygnuj z tej drogi |
| test przechodzi lokalnie, pada co dziesiąty raz w CI | stały `sleep` zamiast czekania na zdarzenie; runner ma inne obciążenie i mniej rdzeni | czekaj na zdarzenie z limitem czasu, wpisz test do rejestru migotliwych |
| dwa przebiegi CI widzą nawzajem swoje węzły | ten sam `ROS_DOMAIN_ID` na współdzielonym runnerze | domena z numeru przebiegu + `ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST` |
| `ros2 topic pub` z NaN nie dociera do detektora | zła nazwa topiku albo niezgodne QoS | `show-topic-connections.sh /vacuum_pressure` — sprawdź liczbę nadawców i obie strony QoS |
| nocny przebieg zapełnia dysk runnera | `ros2 bag record --all` przez godzinę to gigabajty | nagrywaj wybrane topiki; przy długim przebiegu rozważ zapis co N-tej próbki |
| `colcon test` zielony, choć żaden test się nie wykonał | zmiana w testach bez przebudowania albo zły filtr markerów | `colcon test-result --all --verbose` pokazuje liczbę testów; zero to porażka, nie sukces |

## Sprawdź się

1. Dlaczego CI budujący obraz z `.devcontainer/Containerfile` jest wart
   dłuższego przebiegu niż `ros-tooling/setup-ros` — i w którym konkretnie
   dniu ta decyzja się zwraca?
2. Śmierć czujnika, NaN w danych i wartość -1000 dają dziś ten sam objaw.
   Jaki? I dlaczego to jest wada projektu, a nie trzy osobne błędy?
3. Dlaczego lint idzie przed testami, a symulacja na końcu — uzasadnij
   informacją z porażki, nie samym czasem wykonania.
4. Co takiego daje nagranie jako artefakt CI, czego nie da stacktrace,
   i dlaczego w backendzie ten sam argument by nie przeszedł?
5. Dlaczego ponowienie migotliwego testu jest gorszym rozwiązaniem niż wpis
   w rejestrze, skoro oba sprawiają, że build jest zielony?
6. Dlaczego test integracyjny w symulacji ma sens tylko z `use_sim_time`,
   i co dokładnie staje się niedeterministyczne bez tego?
7. Dlaczego poprawka przed testem regresji jest w robotyce gorsza niż
   w backendzie — podaj konkretny mechanizm, przez który błąd wraca.
8. Dlaczego `tc netem` na `lo` nie zaburzy komunikacji między `vacuum_sensor`
   a `grasp_monitor` w tym kontenerze?

## Co przeczytać

- `https://docs.ros.org/en/jazzy/` — sekcja o zmiennych środowiskowych
  (`ROS_DOMAIN_ID`, `ROS_AUTOMATIC_DISCOVERY_RANGE`, `ROS_LOG_DIR`), bo to
  one decydują o izolacji i o tym, gdzie wylądują logi w CI.
- `https://github.com/ros-tooling/action-ros-ci` — przeczytaj, **czego** ta
  akcja pilnuje (kolejność build/test, obsługa `colcon`), nawet jeśli jej nie
  używasz; to darmowa lista rzeczy do skopiowania do własnego przepływu.
- `https://github.com/ros2/launch` (katalog `launch_testing`) — źródło jest
  tu lepsze niż dokumentacja: widać, jakie zdarzenia procesów są dostępne
  i na czym naprawdę można asertować.
- `https://github.com/ros-tooling/topic_tools` — kod `drop` i `throttle`,
  żeby wiedzieć, co dokładnie robią z QoS i stemplami, zanim oprzesz na nich
  test awarii.
- `https://gazebosim.org/docs/harmonic/` — tryb serwera bez GUI i sterowanie
  krokiem symulacji; to jest warunek, żeby nocny przebieg był powtarzalny.
- `https://www.ros.org/reps/` — REP-2000 (wersje i platformy dla dystrybucji),
  gdy będziesz decydował, jak mocno przypiąć bazowy obraz.

## Dziennik

    Co mnie zaskoczyło:
      (np. jak mało trzeba wstrzyknąć NaN-ów, żeby uciszyć detektor na stałe)

    Co zjadło najwięcej czasu:
      (typowo: uprawnienia i UID-y przy montowaniu repo do kontenera w CI)

    Która awaria z katalogu okazała się najtrudniejsza do zaobserwowania
    i dlaczego akurat ta:

    Czego nie umiałbym napisać tydzień temu — jedno zdanie:

    Który test w moim repo nigdy nie zapalił się na czerwono:
      (to jest lista rzeczy do zrobienia, nie lista osiągnięć)

Dalej → [Etap 12 — Flota, produkcja i dalsza droga](./12-flota-i-dalej.md)
