# Etap 03 — Bagi jako dane testowe

> Po tym etapie masz katalog nagrań, o których wiesz, co w nich jest, i skrypt
> czytający je bez uruchamiania ROS-a — czyli zbiór danych zamiast pamiątki
> po udanym przebiegu.

| | |
|---|---|
| wejście | etapy 01–02; `grip_monitor` się buduje, istnieje `projects/grab-fail-detection/bags/chwyt-3-stany/` |
| czas | 2–3 wieczory |
| kończy się | `read-bag.py` wypisuje tabelę z trzech osobnych nagrań, a `grasp_monitor` chodzi na odtwarzanym nagraniu z `--clock` |

W backendzie masz nagrane odpowiedzi HTTP. Tu masz nagrany świat — z tą
różnicą, że świat się nie odtwarza. Odtwarzają się wyłącznie wiadomości.

---

## Po ludzku: co to jest w twoim świecie

| pojęcie robotyczne | odpowiednik z backendu | gdzie analogia pęka |
|---|---|---|
| bag (katalog + `metadata.yaml`) | katalog fixture'ów z manifestem | manifest jest osobnym plikiem — można go zgubić albo w nim skłamać, a `ros2 bag` uwierzy |
| mcap | format samoopisujący (Parquet, Avro) | schemat mówi „`float32 data`"; nie mówi, że to hektopaskale ani że minus znaczy podciśnienie |
| `ros2 bag play` | odtworzenie nagranych odpowiedzi (VCR, WireMock) | nagrany serwis odpowiada, **gdy go zapytasz**; nagranie mówi do ściany we własnym tempie i nie czeka na nikogo |
| `--clock` | zamrożony zegar w teście (`freezegun`) | zegar jest globalny dla grafu i każdy węzeł musi się **zgodzić** go słuchać |
| tryb migawkowy | bufor pierścieniowy, flight recorder | zrzut wyzwalasz z zewnątrz usługą, a bufor jest limitowany w bajtach, nie w sekundach |
| `bags/` w `.gitignore` | artefakty buildu poza repo | artefakt odtworzysz z kodu; nagrania nie odtworzysz, bo świat już był inny |

---

## Po co to — czego bez tego nie da się zrobić

Dziś sprawdzenie `grasp_monitor` wygląda tak: uruchamiasz `vacuum_sensor`,
przestawiasz mu parametr ręcznie, patrzysz w `print-topic-messages.sh`. Trzy
problemy, każdy zabójczy:

1. **Wejście jest za każdym razem inne** — `gauss(0, 0.5)` w `vacuum_sensor.py`
   losuje od nowa. Nie powiesz „po zmianie jest lepiej", bo nie ma „tego samego".
2. **Moment przełączenia stanu znasz tylko ty**, z pamięci. Nigdzie nie jest
   zapisane, że sekunda 7,00 to początek szczelnego chwytu.
3. **Nie ma czego podać testowi.** Bez nagrań jedynym testem jest patrzenie.

Twoje jedno nagranie zawiera już odpowiedzi na pytania, których nie zadałeś:

```
/grasp_verdict:  1062 wiadomości, 4 zmiany wartości
                 [state] empty  350    0.00 ->  7.00
                 [state] leak   429    7.00 ->  7.48  i  13.14 -> 21.22
                 [state] sealed 283    7.48 -> 13.14
```

**`[state] empty`.** Dzisiejszy `grasp_monitor.py` publikuje `'open'`, nie
`'empty'`. Nagranie powstało na wersji kodu, której już nie ma, i nikt tego nie
zauważył, bo `String` niczego nie obiecuje ([etap 01](./01-kontrakty-wiadomosci.md)).
Fixture i kod rozjechały się w ciszy — tak właśnie umierają zbiory danych.

**Te 0,48 s.** Między 7,00 a 7,48 detektor twierdzi `leak`, choć chwyt jest już
szczelny. To dokładnie 24 wiadomości, czyli `deque(maxlen=25)` przesuwający się
przez zbocze: średnia wędruje z 0 do -59 i po drodze siedzi w paśmie
`-58 < mean < -1`. Na terminalu tego nie widać. W nagraniu — co do wiadomości.

**1062 i 1062.** Werdykt ma tyle samo wiadomości co pomiar, choć zmienia wartość
cztery razy. To wada numer 3 z roadmapy — zakomentowana detekcja zbocza —
pierwszy raz jako liczba, nie jako wrażenie.

---

## Dlaczego to ciekawe

Zajmie dziesięć sekund:

```bash
grep -a -o 'float32 data' projects/grab-fail-detection/bags/chwyt-3-stany/*.mcap
```

Dostajesz `float32 data`. **Definicja wiadomości leży w środku pliku
binarnego.** Obok niej `ros2msg`, `std_msgs/msg/Float32` i
`RIHS01_7170d3d8f841…` — ten sam hash typu, który liczyłeś w etapie 01.

To jest cała pointa mcap, a konsekwencja jest praktyczna: nagranie sprzed roku,
z firmy, która już nie istnieje, zrobione na dystrybucji, której nie masz, nadal
się otwiera.

Druga nieoczywista rzecz: nagranie zapisuje nie tylko dane, ale i **kontrakt
transportu**. Przy każdym topiku siedzi `offered_qos_profiles` nadawcy —
nagranie pamięta, że czujnik nadawał `best_effort`, a werdykt `reliable`.
Odpowiednik z backendu: nagranie ruchu HTTP niosące ze sobą ustawienia TCP
drugiej strony. Tam byłaby to ciekawostka. Tu decyduje o tym, czy odtworzone
dane w ogóle do kogoś dojdą.

---

## Dlaczego to trudne

**Odtwarzanie wygląda jak rzeczywistość i nie jest nią.** Te same nazwy
topików, te same typy, ten sam wykres. Dlatego ludzie budują na tym testy,
które przechodzą, a potem robot w polu robi coś innego.

**Prawdy o świecie nie ma w nagraniu.** Twoje ma dwa topiki i tylko dwa.
Nie ma `/rosout`, nie ma `/parameter_events`. Moment, w którym przestawiłeś
`state` z `open` na `sealed` — jedyna rzecz, którą wiesz na pewno, bo sam ją
zrobiłeś — **nie został nagrany**. Zostały same skutki.

**Nagrania nie mieszczą się w gicie.** Twoje 21 sekund to 137 KiB, bo dwa topiki
po 50 Hz i cztery bajty na pomiar. Dorzuć kamerę RGB 1280×720 bez kompresji:
2,76 MB na klatkę, 30 klatek na sekundę, **5 GB na minutę**.

**Reszta to wiedza plemienna.** Że `--clock` bez `use_sim_time` nie robi nic. Że
odtwarzacz startuje szybciej, niż subskrybent zdąży się zgłosić. I że `reliable`
przed tym wyścigiem **nie** chroni.

---

## Wycinek prawdziwej roboty

Z hali klienta przychodzi nagranie: cztery gigabajty, dwadzieścia minut,
czterdzieści topików i jedno zdanie opisu — „około 14:30 zgubiło paczkę". Linia
stoi od rana, integrator mówi, że to software, dostawca chwytaka — że mechanika,
a rozstrzygnąć ma ktoś, kogo tam nie było.

Robisz dokładnie to, co w zadaniach niżej, tylko na cudzych danych. `ros2 bag
info` i `metadata.yaml`: co w ogóle nagrano i z jakim QoS. `read-bag.py` na
całości — „około 14:30" robi się sekundą 1043. `ros2 bag convert` wycina osiem
sekund razem z oryginalnymi stemplami. I wychodzi rzecz normalna: brakuje akurat
tego topiku, który by spór rozstrzygnął, bo stanu chwytaka nikt nie kazał
nagrywać. Stąd drugi wątek tego samego dnia — co ma się nagrywać na stałe, żeby
następnym razem nie zabrakło; dysk na robocie ma 500 GB, nie nieskończoność.

Zostaje po tobie katalog z wycinkiem, plik etykiet i jedno polecenie, które
odtwarza ten przypadek za każdym razem tak samo. I zdanie, którego większość
kandydatów nie umie powiedzieć: „to nagranie nie rozstrzyga sporu — i wiem,
którego topiku brakuje, żeby rozstrzygało". Triage nagrań i decydowanie, co
robot zapisuje o sobie, bywa w większych zespołach osobnym etatem obok testów.

---

## Model pojęciowy

### Co jest w środku

Bag to **katalog**, nie plik: dane (`chwyt-3-stany_0.mcap`, 137 KiB) plus
manifest (`metadata.yaml`, 2 KiB). Wszystko, co powie ci `ros2 bag info`, siedzi
w manifeście. Przeczytaj go teraz — to najważniejsze pięć minut tego etapu:

```yaml
  storage_identifier: mcap            # domyślny format w Jazzy, nie wybierałeś go
  duration: {nanoseconds: 21220236007}
  message_count: 2124
  topics_with_message_count:
    - topic_metadata:
        name: /vacuum_pressure
        type: std_msgs/msg/Float32
        offered_qos_profiles:
          - reliability: best_effort  # QoS NADAWCY, zapamiętane
            durability: volatile
        type_description_hash: RIHS01_7170d3d8f841f7be…
      message_count: 1062
  compression_format: ""
  ros_distro: jazzy
```

| co czytasz | wartość u ciebie | co z tego wynika |
|---|---|---|
| `storage_identifier` | `mcap` | nie podawałeś `-s` — w Jazzy mcap jest domyślny |
| `duration` + `message_count` | 21,220 s, 2124 | 1062 / 21,22 = **50,00 Hz** na obu topikach |
| dwa topiki | `/vacuum_pressure`, `/grasp_verdict` | nagrałeś tylko to, co wskazałeś; reszta grafu przepadła |
| `offered_qos_profiles` | best_effort / reliable | odtwarzacz odtworzy **te** profile, nie domyślne |
| `type_description_hash` | dwa różne `RIHS01_…` | tożsamość typu sprawdzalna bez kodu |
| `compression_format` | `""` | nieskompresowane, 6,4 KiB/s |
| `ros_distro` | `jazzy` | wiadomo, na czym to powstało, gdy za rok coś nie zagra |

### mcap kontra sqlite3

Do Iron domyślny był sqlite3 (`.db3`), od Jazzy jest mcap. To nie kwestia gustu.

| | sqlite3 | mcap |
|---|---|---|
| definicje wiadomości | **nie ma** — trzymasz je u siebie w workspace | **w pliku**, jako tekst `.msg` plus hash typu |
| odczyt bez ROS-a | nie | tak, plik jest samoopisujący |
| cudzym narzędziem | bajty i tak nieczytelne | Foxglove, biblioteka `mcap`, `mcap` CLI |
| po ucięciu procesu | baza bywa nie do otwarcia | plik czytelny do ostatniego kompletnego chunka |

Pierwszy wiersz jest jedynym do zapamiętania. Nagranie w sqlite3 mówi „topik ma
typ `std_msgs/msg/Float32`" i to jest **napis**. Nie masz tej definicji
zbudowanej u siebie, w tej samej wersji? Masz worek bajtów. To bezpośrednia
konsekwencja etapu 01: skoro tożsamość typu jest hashem, to plik, który nie
niesie definicji, nie niesie niczego sprawdzalnego.

Zastrzeżenie do zadania 03.4: niezależność dotyczy **formatu pliku**. Ścieżka
`rosbag2_py` + `deserialize_message` nadal woła typesupport zainstalowany
w systemie; ze schematu w pliku korzystają dopiero narzędzia czytające mcap
natywnie (Foxglove, biblioteka `mcap`). Dla `std_msgs` różnicy nie zobaczysz —
zobaczysz ją w dniu, w którym dostaniesz nagranie z cudzymi interfejsami.

### Nagrywanie

W kontenerze (z Ghostty wejdź przez `scripts/dev/enter-devcontainer.sh`):

```bash
cd projects/grab-fail-detection/bags
ros2 bag record /vacuum_pressure /grasp_verdict -o chwyt-3-stany
ros2 bag record -a                     # wszystko, co widać
ros2 bag record -e '/vacuum.*'         # regex na nazwach topików
ros2 bag record -a -x '/rosout'        # wszystko oprócz (nazwa flagi: patrz niżej)
```

| opcja | co robi | kiedy naprawdę jej użyjesz |
|---|---|---|
| `-o KATALOG` | nazwa nagrania | zawsze — inaczej dostajesz `rosbag2_2026_09_12-21_14_03` |
| `-a` | wszystko widoczne | pierwszy kontakt z cudzym systemem |
| `-e REGEX` | wybór wyrażeniem | gdy topików jest 40 i mają wspólny prefiks |
| exclude (`-x`) | odejmuje od `-a` albo `-e` | wycinasz obraz z kamery, żeby zmieścić resztę |
| `-d SEK` / `-b BAJTY` | dzieli nagranie po czasie / rozmiarze | długie przebiegi: pliki po 5 minut zamiast jednego na 6 godzin |
| `--compression-mode` + `--compression-format` | kompresja `file` albo `message`, np. `zstd` | gdy wąskim gardłem jest dysk, a nie CPU |
| `--max-cache-size` | bufor w pamięci przed zapisem | wysokie częstotliwości; to samo ogranicza bufor migawki |
| `--qos-profile-overrides-path` | QoS **subskrypcji** nagrywarki | gdy nagrywarka nie widzi topiku przez niedopasowanie |

Nazwy flag wykluczających zmieniały się między dystrybucjami (`--exclude`,
`--exclude-regex`, osobne warianty na listę nazw), a w Jazzy `-a` potrafi złapać
też usługi. Nie zgaduj: `ros2 bag record --help`.

`--compression-mode file` pakuje gotowy plik i odbiera ci to, po co brałeś mcap:
losowy dostęp i otwieralność cudzym narzędziem bez rozpakowania. `message`
kosztuje CPU przy nagrywaniu. Sam mcap umie kompresować własne chunki (przez
`--storage-config-file`) i to zwykle lepszy pomysł.

### Odtwarzanie

```bash
ros2 bag play chwyt-3-stany --clock 200 -r 0.5 --topics /vacuum_pressure
```

| opcja | co robi | po co |
|---|---|---|
| `--clock [HZ]` | publikuje `/clock` z nagrania | żeby węzły z `use_sim_time` miały czas z nagrania, nie z zegarka — [etap 02](./02-czas-zdarzenia-stan.md) |
| `-r TEMPO` | mnożnik (`-r 0.1` = dziesięć razy wolniej) | debugowanie zbocza, na którym coś się psuje |
| `-l` | w kółko | gdy coś ma być „zawsze zasilone" |
| `--start-offset SEK` | zaczyna od N-tej sekundy | wracasz do awarii z 14. sekundy czterdziesty raz |
| `--topics A B` | tylko wskazane | żeby nagrany `/grasp_verdict` nie konkurował z żywym węzłem |
| `--remap STARY:=NOWY` | zmiana nazwy przy odtwarzaniu | porównanie „nagrane kontra świeżo policzone" obok siebie |
| `--start-paused` / `--delay SEK` | staje na pierwszej wiadomości / czeka | lek na wyścig przy starcie |
| `--read-ahead-queue-size` | ile czytać z wyprzedzeniem | gdy dysk nie nadąża i odtwarzanie „czka" |
| `--qos-profile-overrides-path` | QoS **publikacji** odtwarzacza | gdy nagrane profile nie pasują do dzisiejszego konsumenta |

Odtwarzacz czyta do kolejki wyprzedzającej i stamtąd wysyła w tempie wynikającym
ze stempli. Wolny nośnik opróżnia kolejkę i wiadomości wychodzą z opóźnieniem;
za duża kolejka zjada pamięć.

Ma też klawiaturę — skróty wypisuje przy starcie — i te same operacje wystawia
jako usługi. Gdy gra, uruchom `ros2 service list` i zajrzyj pod prefiks węzła
odtwarzacza: pauza, krok, tempo i skok w czasie idą ze skryptu i z testu.

Plik nadpisań QoS: klucz to nazwa topiku, wartość to profil.

```yaml
# qos-play.yaml — wymuś reliable na topiku nagranym jako best_effort
/vacuum_pressure:
  reliability: reliable
  durability: volatile
  history: keep_last
  depth: 100
```

Zapamiętaj kierunek: ten sam plik przy `record` nadpisuje QoS **subskrypcji**,
przy `play` — QoS **publikacji**. Dwie różne rzeczy pod jedną nazwą flagi.

### Cięcie: `ros2 bag convert`

`convert` czyta nagrania i zapisuje nowe według pliku opcji wyjściowych. Tym
filtrujesz topiki, wycinasz przedział czasu i zmieniasz format albo kompresję —
czyli tym robisz z jednego 21-sekundowego nagrania trzy jednostanowe.

```yaml
# split.yaml
output_bags:
  - uri: 2026-09-12_open
    storage_id: mcap
    topics: [/vacuum_pressure, /grasp_verdict]
    start_time_ns: 1788702196873060456
    end_time_ns:   1788702203873060456   # +7,00 s
  - uri: 2026-09-12_sealed
    storage_id: mcap
    topics: [/vacuum_pressure, /grasp_verdict]
    start_time_ns: 1788702203873060456
    end_time_ns:   1788702210013060456   # +13,14 s
```

```bash
ros2 bag convert -i chwyt-3-stany -o split.yaml
```

Stemple bierzesz ze `starting_time` w `metadata.yaml` plus przesunięcie
w nanosekundach; zestaw kluczy pliku opcji różni się między wersjami rosbag2.
Jest droga objazdowa (`play --start-offset` do jednego terminala, `record`
w drugim), ale ma cenę: ponowne nagranie zapisuje **dzisiejsze** stemple, gubi
oryginalne i przepuszcza dane przez DDS. `convert` kopiuje wiadomości razem
ze stemplami.

### Tryb migawkowy: czarna skrzynka

Na stanowisku nagrywasz wszystko. Na robocie w polu nie możesz — a i tak
interesuje cię tylko trzydzieści sekund przed awarią.

```bash
ros2 bag record -a --snapshot-mode --max-cache-size 536870912 -o blackbox
```

Nagrywarka subskrybuje normalnie, ale **nic nie zapisuje**: trzyma wiadomości
w buforze w pamięci i wyrzuca najstarsze, gdy się zapełni. Zrzut na dysk
następuje dopiero na żądanie z zewnątrz.

Bufor jest limitowany **w bajtach** (`--max-cache-size`), nie w sekundach.
„Ostatnie 30 sekund" musisz przeliczyć z przepływności: u ciebie 6,4 KiB/s,
więc 30 s mieści się w 200 KiB; z kamerą te same 30 sekund to dziesiątki
gigabajtów i cała idea się wywraca.

Wyzwolenie zrzutu to wywołanie usługi. Jej nazwa zawiera nazwę węzła nagrywarki,
którą można zmienić (`--node-name`) — **sprawdź ją u siebie**, nie przepisuj
w ciemno; typ potwierdzisz przez `ros2 service type`:

```bash
ros2 service list | grep -i snapshot
ros2 service call /rosbag2_recorder/snapshot rosbag2_interfaces/srv/Snapshot "{}"
```

### Czytanie nagrania offline z Pythona

Najważniejsze narzędzie tego etapu: skraca pętlę z minutowej na sekundową —
żadnego `colcon build`, żadnego węzła, żadnego grafu, jeden proces czytający plik.

```python
#!/usr/bin/env python3
"""Czyta bag offline i wypisuje, co w nim jest — bez grafu ROS-a."""

import argparse
import statistics

from rclpy.serialization import deserialize_message
import rosbag2_py
from rosidl_runtime_py.utilities import get_message


def read_messages(uri: str):
    reader = rosbag2_py.SequentialReader()
    reader.open(
        rosbag2_py.StorageOptions(uri=uri, storage_id='mcap'),
        rosbag2_py.ConverterOptions(input_serialization_format='cdr',
                                    output_serialization_format='cdr'),
    )
    types = {t.name: t.type for t in reader.get_all_topics_and_types()}

    while reader.has_next():
        topic, raw, stamp_ns = reader.read_next()
        yield topic, stamp_ns, deserialize_message(raw, get_message(types[topic]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bag', help='katalog nagrania albo plik .mcap')

    stamps, values, verdicts = {}, {}, []
    for topic, stamp_ns, msg in read_messages(parser.parse_args().bag):
        stamps.setdefault(topic, []).append(stamp_ns)
        data = getattr(msg, 'data', None)
        if isinstance(data, float):
            values.setdefault(topic, []).append(data)
        elif isinstance(data, str):
            verdicts.append((stamp_ns, data))

    t0 = min(ts[0] for ts in stamps.values())
    print(f'{"topik":<20}{"n":>6}{"Hz":>8}{"min":>10}{"max":>10}{"śr.":>10}')
    for topic, ts in sorted(stamps.items()):
        span = (ts[-1] - ts[0]) / 1e9
        hz = (len(ts) - 1) / span if span > 0 else 0.0
        v = values.get(topic)
        stats = f'{min(v):10.2f}{max(v):10.2f}{statistics.fmean(v):10.2f}' if v else ''
        print(f'{topic:<20}{len(ts):6d}{hz:8.2f}{stats}')

    if not verdicts:
        return

    print('\nprzedziały werdyktu (zmiana wartości, nie każda wiadomość):')
    start, current = verdicts[0]
    for stamp_ns, text in verdicts[1:] + [(verdicts[-1][0], None)]:
        if text != current:
            print(f'  {(start - t0) / 1e9:6.2f} -> {(stamp_ns - t0) / 1e9:6.2f}  {current}')
            start, current = stamp_ns, text


if __name__ == '__main__':
    main()
```

| element | co robi | dlaczego tak |
|---|---|---|
| `SequentialReader` | czyta po kolei, w kolejności zapisu | jest też filtr: `reader.set_filter(rosbag2_py.StorageFilter(topics=[...]))` |
| `StorageOptions(uri, storage_id)` | skąd i jakim pluginem | pusty `storage_id` każe wykryć format z `metadata.yaml` |
| `ConverterOptions` | format serializacji wejścia i wyjścia | `cdr` -> `cdr` znaczy „oddaj surowe bajty, nie przerabiaj" |
| `get_message` + `deserialize_message` | z napisu `std_msgs/msg/Float32` robi klasę, z bajtów obiekt | jedyny krok, który potrzebuje typu **u ciebie** w systemie |

`stamp_ns` z `read_next()` to czas **odbioru przez nagrywarkę**. Twoje
wiadomości nie mają nagłówka, więc to jedyny czas, jaki w ogóle mają — i bardzo
dobry powód, żeby skończyć etap 01.

### Dyscyplina zbioru danych

**Jedno nagranie = jeden scenariusz.** `chwyt-3-stany` ma trzy stany w jednym
pliku, więc każde pytanie o niego zaczyna się od „ale w której sekundzie".

**Nazwa niesie sens** — `YYYY-MM-DD_scenariusz_NN`:

```
2026-09-12_open_01/   2026-09-12_sealed_01/   2026-09-12_sealed-to-leak_01/
```

**Plik etykiet obok nagrania.** Prawdę o stanie znasz — sam ustawiałeś parametr.
Zapisz ją, zanim zapomnisz:

```yaml
# labels/2026-09-12_sealed-to-leak_01.yaml
bag: 2026-09-12_sealed-to-leak_01
recorded: 2026-09-12T21:14:03+02:00
code_rev: 913d160            # git rev-parse --short HEAD w chwili nagrania
sensor: {node: vacuum_sensor, rate_hz: 50, noise_sd: 0.5}
segments:
  - {t_start: 0.00, t_end: 6.20, state: sealed}
  - {t_start: 6.20, t_end: 14.80, state: leak}
notes: >
  Parametr `state` przestawiany ręcznie przez set-param.sh. Czasy z terminala,
  nie z bagu — /parameter_events nie było nagrywane.
```

`code_rev` to nie ozdoba: gdybyś miał go przy `chwyt-3-stany`, od razu
wiedziałbyś, czemu w środku jest `[state] empty`.

**`README.md` w `bags/`** — konwencja nazw, gdzie fizycznie leżą duże pliki, jak
odtworzyć nagranie od zera.

W `.gitignore` masz `**/bags/`, `*.db3`, `*.mcap`, czyli `bags/` **w całości**
jest poza gitem — razem z `README.md` i etykietami, które chcesz wersjonować.
Negacja nie pomoże: git nie wchodzi do wykluczonego katalogu, więc
`!**/bags/*.yaml` nic nie da. Trzy wyjścia, wybierz świadomie:

| wariant | zyskujesz | tracisz |
|---|---|---|
| **etykiety poza `bags/`** (`projects/grab-fail-detection/labels/`) | metadane w gicie, dane poza — czysty podział, zero kombinowania z ignorem | ścieżka do nagrania żyje w etykiecie, przeniesienie danych wymaga poprawki |
| przepisać `.gitignore` tak, by wpuścić `*.yaml` i `*.md` | wszystko w jednym katalogu | reguły stają się nieoczywiste, łatwo wciągnąć 5 GB |
| git-lfs na `*.mcap` | dane wersjonowane razem z kodem | limity i koszt hostingu, klon puchnie, przy kamerze i tak nie zadziała |

Przy kilkuset kilobajtach kuszące jest git-lfs, a migracja historii lfs boli
bardziej niż przeniesienie katalogu. Wariant pierwszy skaluje się w obie strony:
**w gicie żyje opis, dane żyją tam, gdzie się mieszczą** (zewnętrzny dysk, NAS,
ta sama struktura katalogów), a łącznikiem jest nazwa. Nazewnictwo zastępuje
wersjonowanie, bo nagrania są niezmienne: poprawione nagranie to nowe nagranie
z nowym numerem, nigdy nadpisane stare.

### Dlaczego odtwarzanie NIE JEST rzeczywistością

Sześć sposobów, na jakie zielony wynik kłamie. Ta lista ma zostać w głowie.

1. **Brak sprzężenia zwrotnego.** Prawdziwy czujnik zareagowałby na to, że robot
   puścił obiekt; nagranie leci tak samo. Pętla przez świat jest tu martwa.
2. **Jitter odtwarzacza.** Nagrane odstępy mają u ciebie medianę 19,99 ms
   i maksimum 20,71 ms. Odtwarzacz nie powtórzy tego co do mikrosekundy — sam
   jest procesem z timerem, kolejką i dyskiem pod spodem.
3. **Domyślnie nie ma `/clock`.** Bez `--clock` węzły biorą czas z zegara
   systemowego, czyli z dziś, a dane są z nagrania.
4. **Wyścig przy starcie.** `play` zaczyna publikować, zanim subskrybent się
   zgłosi. Przy `best_effort` te wiadomości **znikają**: bez błędu, bez
   ostrzeżenia, bez luki w numeracji.
5. **Nagrane QoS kontra QoS konsumenta.** Odtwarzacz oferuje profil z nagrania.
   Dzisiejszy węzeł żąda `reliable`, a nagranie daje `best_effort`? Nie połączą się
   w ogóle — i to jest cisza, nie błąd.
6. **Nie ma wszystkich topików.** W pliku jest tylko to, co wskazałeś. Systemu,
   który naprawdę działał, w nim nie ma.

Do czwartego punktu wykłada się każdy z backendu: **`reliable` nie chroni przed
wyścigiem.** Niezawodność dotyczy dostarczenia do **dopasowanego** subskrybenta;
kto nie był dopasowany w chwili publikacji, nie dostanie nic — chyba że nadawca
ma `transient_local`, jedyny mechanizm w tym zestawie obsługujący spóźnialskich.

---

## Zadania

### Zadanie 03.1 — Przeczytaj swoje nagranie (rdzeń)

**Cel:** wyciągnąć z istniejącego nagrania cztery fakty, których dziś nie znasz.
**Ćwiczysz:** `ros2 bag info` niczego nie mierzy, tylko przepisuje manifest —
widać to dopiero, gdy Hz policzysz sam z `duration` i `message_count`.

```bash
ros2 bag info projects/grab-fail-detection/bags/chwyt-3-stany
cat projects/grab-fail-detection/bags/chwyt-3-stany/metadata.yaml
```

Zapisz w `NOTES.md`: częstotliwość każdego topiku, QoS każdego nadawcy, oba
hashe typów i powód, dla którego nie ma tam `/rosout` ani `/parameter_events`.

Potem skopiuj sam plik `.mcap` do pustego katalogu i spróbuj `ros2 bag info` na
nim, bez `metadata.yaml`. Zadziała — masz dowód, że definicje siedzą w pliku.
Nie zadziała — `ros2 bag reindex` odtworzy manifest z samego pliku, co jest tym
samym dowodem od drugiej strony.

**Gotowe, gdy:** umiesz z pamięci podać Hz i QoS obu topików i wiesz, którą
sekundę nagrania trzeba obejrzeć, żeby zobaczyć zbocze.

### Zadanie 03.2 — Trzy scenariusze, trzy nagrania (rdzeń)

**Cel:** zamienić jedno wielostanowe nagranie na zbiór jednostanowych.
**Ćwiczysz:** że „prawdy o świecie nie ma w nagraniu" jest decyzją podjętą przy
`record`, a nie cechą formatu — dopisujesz `/parameter_events` i brak znika.

Dla każdego stanu osobno: czujnik z parametrem, detektor, około 10 sekund zapisu.

```bash
scripts/dev/ros2/run-node.sh grip_monitor vacuum_sensor --ros-args -p state:=sealed
scripts/dev/ros2/run-node.sh grip_monitor grasp_monitor
# w trzecim terminalu, w kontenerze:
ros2 bag record /vacuum_pressure /grasp_verdict /parameter_events -o 2026-09-12_sealed_01
```

`/parameter_events` jest tu nowe i o to chodzi: tym razem moment przestawienia
parametru **wyląduje w nagraniu**. Czwarte nagranie zrób ze zboczem — nagrywaj
i w trakcie zawołaj `scripts/dev/ros2/set-param.sh /vacuum_sensor state leak`.

**Gotowe, gdy:** `ros2 bag info` na każdym z czterech nagrań pokazuje trzy
topiki i sensowny czas, a w nagraniu ze zboczem widać na `/parameter_events`
zmianę `state`.

*Wariant (rozszerzenie):* zamiast nagrywać od nowa, potnij `chwyt-3-stany` przez
`ros2 bag convert`. Porównaj stemple obu metod — wycięty fragment ma stemple
z 2026-09-06, ponowne nagranie ma dzisiejsze.

### Zadanie 03.3 — Etykiety i `README` (rdzeń)

**Cel:** dopisać do nagrań prawdę, której w nich nie ma.
**Ćwiczysz:** rozejście się metadanych i danych — milczący `git status` na pliku
etykiet przekonuje o tym skuteczniej niż akapit o `**/bags/`.

Do każdego nagrania plik YAML z przedziałami czasu, stanem i `code_rev` (wzór
wyżej). `README.md` z konwencją nazw i miejscem, gdzie żyją dane. Podejmij
decyzję z tabeli o `.gitignore` i **zapisz uzasadnienie** w `NOTES.md`; wybór
wariantu jest mniej ważny niż to, że jest świadomy.

**Gotowe, gdy:** `git status` pokazuje etykiety jako do zacommitowania, a
nagrania jako niewidoczne dla gita.

### Zadanie 03.4 — `read-bag.py`: tabela offline (rdzeń)

**Cel:** zobaczyć zawartość nagrania bez uruchamiania czegokolwiek z ROS-a.
**Ćwiczysz:** granicę samoopisywalności — dopiero pisząc ten skrypt zobaczysz, że
`deserialize_message` i tak pyta twój system o typ, choć plik niesie definicję.

Napisz `projects/grab-fail-detection/tools/read-bag.py` na szkielecie wyżej: ma
wypisać topik, liczbę wiadomości, częstotliwość, zakres wartości i przedziały
stanów. Na `chwyt-3-stany` powinieneś dostać dokładnie to:

```
topik                    n      Hz       min       max       śr.
/grasp_verdict        1062   50.00
/vacuum_pressure      1062   50.00    -60.53      1.27    -24.70

przedziały werdyktu (zmiana wartości, nie każda wiadomość):
    0.00 ->   7.00  [state] empty
    7.00 ->   7.48  [state] leak
    7.48 ->  13.14  [state] sealed
   13.14 ->  21.22  [state] leak
```

Potem dołóż porównanie tych przedziałów z plikiem etykiet. Żadnych metryk — od
tego jest [etap 10](./10-ewaluacja-na-danych.md); na razie różnica ma być widać
gołym okiem.

**Gotowe, gdy:** skrypt działa bez `colcon build`, bez uruchomionego węzła
i bez `ros2 daemon`, a ty umiesz wyjaśnić `[state] empty` i te 0,48 s
fałszywego `leak`.

### Zadanie 03.5 — Odtwarzanie pod żywy detektor (rdzeń)

**Cel:** zasilić `grasp_monitor` z nagrania zamiast z czujnika.
**Ćwiczysz:** odtwarzacz jest zwykłym nadawcą w grafie, nie osobnym trybem —
widać to dopiero wtedy, gdy `--topics` zdejmie z topiku drugiego nadawcę.

```bash
# terminal 1 — detektor (vacuum_sensor ma NIE działać)
scripts/dev/ros2/run-node.sh grip_monitor grasp_monitor
# terminal 2 — nagranie zamiast czujnika, tylko pomiar
ros2 bag play 2026-09-12_sealed-to-leak_01 --clock 200 --topics /vacuum_pressure
# terminal 3
scripts/dev/ros2/print-topic-messages.sh /grasp_verdict --field data
```

`--topics` jest istotne: bez tego odtworzyłbyś też nagrany `/grasp_verdict`
i miałbyś na jednym topiku dwóch nadawców — nagranego i żywego. Zrób to raz
celowo i zobacz, jak nieczytelny robi się wynik.

**Gotowe, gdy:** `/grasp_verdict` zmienia się w tej samej sekundzie co stan
w pliku etykiet, a `show-topic-connections.sh /vacuum_pressure` pokazuje jednego
nadawcę (odtwarzacz) i jednego odbiorcę.

### Zadanie 03.6 — Zepsuj to: wyścig i QoS (rdzeń)

**Cel:** zobaczyć dwa najczęstsze powody, dla których „nagranie się odtwarza,
a nic nie przychodzi".
**Ćwiczysz:** ciszę jako objaw — żadna z tych awarii nie daje błędu, więc jedynym
dowodem są dwie policzone liczby wiadomości, a nie wrażenie „chyba działa".

**Wariant A — wyścig.** Odwróć kolejność z 03.5: najpierw `ros2 bag play`,
potem `grasp_monitor`. Policz, ile wiadomości przepadło — porównaj liczbę
z `read-bag.py` z tym, co doszło (`print-topic-messages.sh` do pliku i `wc -l`).
Powtórz z `-r 0.1`: nagranie trwa dziesięć razy dłużej, więc procentowo tracisz
dziesięć razy mniej. Start kosztuje tyle samo **sekund**, tylko sekunda znaczy
teraz mniej wiadomości. Napraw przez `--start-paused` albo `--delay 3` i sprawdź,
że strata znika.

**Wariant B — QoS.** Nagrany `/vacuum_pressure` jest `best_effort`. Poproś
o `reliable`:

```bash
scripts/dev/ros2/print-topic-messages.sh /vacuum_pressure --qos-reliability reliable
```

(Dokładną nazwę flagi potwierdź w `ros2 topic echo --help` — opcje z tego
skryptu idą wprost do `echo`.) Cisza, żadnego błędu. Teraz
`show-topic-connections.sh /vacuum_pressure` i zobacz obie strony kontraktu obok
siebie. Na koniec odtwórz z `qos-play.yaml` wymuszającym `reliable` i pokaż, że
ten sam odbiorca nagle dostaje dane.

**Gotowe, gdy:** umiesz podać liczbę zgubionych wiadomości dla obu temp i
wskazać palcem w wydruku `ros2 topic info -v` linię, przez którą nie było
połączenia.

### Zadanie 03.7 — Czarna skrzynka (rozszerzenie)

**Cel:** nagrywać bez zapisywania i zrzucić dane dopiero po „awarii".
**Ćwiczysz:** bufor liczony w bajtach, nie w sekundach — ile to jest „ostatnie
30 sekund", dowiadujesz się ze zrzutu, a nie z dokumentacji.

Uruchom nagrywarkę w trybie migawkowym z buforem na jakieś 30 sekund (przelicz
z 6,4 KiB/s). Niech chodzi. Po kilku minutach wywołaj awarię:
`set-param.sh /vacuum_sensor state cokolwiek` rzuci `RuntimeError` w callbacku
timera i czujnik przestanie publikować. Wtedy wywołaj usługę zrzutu.

**Gotowe, gdy:** w powstałym nagraniu widzisz ostatnie sekundy **przed** awarią,
a nie całe kilka minut, i umiesz powiedzieć, ile sekund mieści twój bufor przy
tej przepływności.

*Dodatek:* opakuj nagrywanie skryptem w `scripts/dev/ros2/`. To pierwszy skrypt
w tym katalogu, który **zostawia coś na dysku**, więc reguła o bliźniaku
`-revert.sh` z `AGENTS.md` staje się pytaniem, a nie formalnością — zdecyduj
i zapisz dlaczego.

---

## Pułapki

| objaw | przyczyna | co zrobić |
|---|---|---|
| `play` gra, subskrybent milczy | nagranie oferuje `best_effort`, konsument żąda `reliable` | `show-topic-connections.sh TOPIC`, potem `--qos-profile-overrides-path` |
| brakuje pierwszych ~0,5 s każdego odtworzenia | odtwarzacz publikuje, zanim subskrybent się dopasuje | `--start-paused` albo `--delay`; przy `-l` strata wraca w każdej pętli |
| węzły mają czas z dziś, dane z nagrania | brak `--clock` albo brak `use_sim_time` w węźle | obie rzeczy naraz, inaczej nie działa nic — [etap 02](./02-czas-zdarzenia-stan.md) |
| `/clock` jest, ale czas skacze schodkami | częstotliwość `--clock` niska wobec 50 Hz danych | podaj wartość, np. `--clock 200` |
| nagranie ma 0 wiadomości mimo działającego węzła | nagrywarka wystartowała przed nadawcą i nie odkryła topiku | uruchamiaj ją po węźle; sprawdzaj `ros2 bag info` od razu po Ctrl+C |
| `record` nie widzi topiku, który `list-topics.sh` pokazuje | ten sam wyścig albo QoS subskrypcji nagrywarki | `--qos-profile-overrides-path` po stronie `record` |
| nagranie skopiowane gdzie indziej nie chce się otworzyć | przeniesiony sam `.mcap`, bez `metadata.yaml` | `ros2 bag reindex` albo kopiuj cały katalog |
| `.mcap.zstd` nie otwiera się w Foxglove | `--compression-mode file` pakuje gotowy plik i zabiera samoopisywalność | rozpakuj albo kompresuj chunki mcap zamiast pliku |
| `git status` nie widzi pliku etykiet | `**/bags/` wyklucza cały katalog, negacja w środku nie działa | trzymaj etykiety poza `bags/` |
| odtworzony werdykt różni się od nagranego na tych samych danych | zgubione wiadomości zmieniły zawartość `deque(maxlen=25)` | to nie niedeterminizm kodu, tylko transportu — porównaj liczby wiadomości |
| `ModuleNotFoundError: rosbag2_py` | skrypt uruchomiony na Fedorze zamiast w kontenerze | `scripts/dev/enter-devcontainer.sh`, potem `python3 …` |
| dwóch nadawców na `/grasp_verdict` przy odtwarzaniu | odtwarzasz całe nagranie, a żywy `grasp_monitor` publikuje równolegle | `--topics /vacuum_pressure` albo `--remap` |

---

## Sprawdź się

1. Dlaczego mcap zastąpił sqlite3 jako domyślny format i co dokładnie tracisz,
   biorąc sqlite3 świadomie?
2. Twoje nagranie ma dwa topiki po 1062 wiadomości. Co ta równość mówi o
   `grasp_monitor.py` — i czy to cecha, czy usterka?
3. Dlaczego `reliable` **nie** ratuje przed zgubieniem wiadomości przy starcie
   odtwarzania, a `transient_local` by ratowało?
4. Po co nagranie pamięta QoS nadawcy, skoro przy odtwarzaniu można je nadpisać —
   i co by się stało, gdyby nie pamiętał?
5. Czym różni się wycięcie fragmentu przez `convert` od odtworzenia
   z `--start-offset` i nagrania na nowo? Podaj dwie różnice w danych
   wyjściowych.
6. Po co plik etykiet, skoro w nagraniu są wartości ciśnienia, z których stan
   „widać"?
7. Tryb migawkowy trzyma „ostatnie 30 sekund". Skąd nagrywarka wie, ile to jest
   30 sekund — i gdzie w tym pytaniu jest haczyk?
8. Nagranie zawiera `[state] empty`, a kod publikuje `[state] open`. Które
   z nich jest błędem i jak zrobić, żeby to się nie powtórzyło?

---

## Co przeczytać

| pozycja | po co |
|---|---|
| `https://github.com/ros2/rosbag2` — README | najaktualniejsze źródło składni pliku opcji `convert`, nadpisań QoS i trybu migawkowego |
| `https://mcap.dev` — specyfikacja formatu | zrozumieć, co znaczy „samoopisujący": rekordy Schema, Channel, Message i indeks na końcu pliku |
| `https://docs.ros.org/en/jazzy/` — rosbag2 i QoS | oficjalne tutoriale `record`/`play` oraz tabela zgodności profili QoS, do której będziesz wracał |
| `ros2 bag record --help`, `play --help`, `convert --help` | w twoim obrazie to jest źródło prawdy o flagach; nazwy zmieniały się między dystrybucjami częściej, niż ktokolwiek przyznaje |
| Foxglove jako przeglądarka mcap | otworzysz nagranie bez ROS-a — przy braku GUI w kontenerze to najkrótsza droga do wykresu ([etap 05](./05-introspekcja-qos-narzedzia.md)) |

---

## Dziennik

    Co mnie zaskoczyło w moim własnym nagraniu:

    Ile wiadomości zgubiłem w 03.6 (play przed subskrybentem) i ile przy -r 0.1:

    Którą decyzję o przechowywaniu danych podjąłem i dlaczego:

    Co zjadło najwięcej czasu:

    Zdanie, którego nie umiałbym napisać tydzień temu:

---

Dalej → [Etap 04 — Piramida testów](./04-piramida-testow.md)
