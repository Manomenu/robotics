# Etap 07 — Gazebo jako stanowisko testowe

> Potrafisz postawić stanowisko, na którym awaria dzieje się **na żądanie i tak
> samo za każdym razem** — zamiast zgadywać jej przebieg w `gauss(0, 0.5)`.

| | |
|---|---|
| wejście | etapy [02](./02-czas-zdarzenia-stan.md) (czas, `use_sim_time`), [03](./03-bagi-jako-dane.md) (bagi), [05](./05-introspekcja-qos-narzedzia.md) (introspekcja, GUI w kontenerze); repo z `grip_monitor` i skryptami `scripts/dev/ros2/` |
| czas | 3–4 wieczory |
| kończy się | własny świat SDF startuje bezgłowo, `/clock` idzie mostem do ROS-a, a dwa przebiegi tej samej symulacji dają identyczny wydruk |

Teza etapu: **symulator nie jest po to, żeby ładnie wyglądało.** Jest po to, żeby
awaria dała się wywołać na żądanie i powtórzyć co do kroku. Cienie, tekstury
i ładna woda to koszt, nie produkt.

## Po ludzku: co to jest w twoim świecie

| pojęcie robotyczne | odpowiednik z backendu | gdzie analogia pęka |
|---|---|---|
| świat SDF | `docker-compose.yml` — deklaratywne środowisko testowe | opisuje fizykę, nie procesy; literówka nie wywala startu, tylko cicho zmienia wynik |
| system (plugin) Gazebo | middleware w aplikacji webowej | nie ma domyślnego zestawu — bez wpisanego `Physics` świat wstaje i **nic się nie rusza**, a nikt nie rzuca wyjątku |
| `ros_gz_bridge` | gateway między dwiema szynami zdarzeń | tłumaczy tylko topiki wymienione z nazwy **i typu**; czego nie wymieniłeś, tego nie ma i nikt tego nie zgłosi |
| `/clock` + `use_sim_time` | wstrzyknięty zegar, `freezegun` | to nie mock w procesie, tylko **topic** — podlega QoS, a węzeł bez niego stoi w zerze i nie mówi dlaczego |
| RTF (współczynnik czasu rzeczywistego) | mnożnik przyspieszenia testów | RTF 0,3 to nie „wolniej" — to inna rzeczywistość dla każdego, kto liczy czas zegarem ściennym |
| tryb bezgłowy (`gz sim -s`) | headless browser w CI | serwer i GUI to **dwa procesy** gadające po transporcie Gazebo; klienta można dopiąć do biegnącej symulacji i odpiąć |

## Po co to — czego bez tego nie da się zrobić

Otwórz `ws/src/grip_monitor/grip_monitor/vacuum_sensor.py`. Cały twój model
świata to trzy stałe (`0.0`, `-59.0`, `-20.0`) wybierane `if`-em po parametrze
`state`, plus `gauss(0, 0.5)` dosypany na wierzch. Cztery rzeczy, których z tego
nie wyciśniesz — i żadnej nie załatasz większym szumem:

1. **Nie ma przejścia.** Po `set-param.sh /vacuum_sensor state open` sygnał
   przeskakuje z −59 na 0 w jednym ticku. Naprawdę ciśnienie wraca przez
   dziesiątki–setki milisekund i to właśnie kształt tego zbocza jest sygnałem,
   na którym stoi detekcja. `deque(maxlen=25)` w `grasp_monitor.py` uśrednia
   akurat to, czego nie ma.
2. **Nie ma zdarzenia.** Nie istnieje moment, w którym przedmiot wypada
   z chwytaka — jest tylko twoja ręka na skrypcie. Nie da się więc zapytać „ile
   milisekund od upadku do werdyktu", bo nie ma chwili zero.
3. **Nie ma prawdy.** Progi `is_at_level(mean, -59)` i `-1 > mean > -58`
   dopasowałeś do liczb, które sam wpisałeś dwa pliki wyżej. To jest test
   tautologiczny: sprawdza, czy `-59.0` mieści się w przedziale wokół `-59.0`.
4. **Nie ma powtarzalnej awarii.** [Etap 10](./10-ewaluacja-na-danych.md) każe
   ci wybrać próg z danych, [etap 11](./11-ci-i-awarie.md) — zapalić test
   regresji. Oba potrzebują awarii, którą umiesz wywołać sto razy pod rząd.

I jedna rzecz, którą symulacja daje za darmo, a rzeczywistość nie daje wcale:
**etykietę**. W symulacji wiesz, gdzie naprawdę jest przedmiot — jego pozycja
to dana z silnika fizyki, niezależna od sygnału ciśnienia. Macierz pomyłek
z etapu 10 potrzebuje kolumny „prawda". Tu ją dostajesz; na prawdziwym
stanowisku klikałbyś ją z nagrań wideo.

W symulacji przedmiot **naprawdę wypada** z chwytaka, a sygnał ciśnienia jest
konsekwencją zdarzenia, nie założeniem o nim. To jest cała różnica.

## Dlaczego to ciekawe

**Zegar staje się zmienną, którą sterujesz.** W produkcji czas jest daną
wejściową — leci i tyle. Tutaj możesz go zatrzymać, przesunąć o dokładnie 100
kroków, puścić dziesięć razy szybciej albo trzy razy wolniej. Cała logika pisana
„na czas ścienny" musi nagle jawnie powiedzieć, z jakiego zegara korzysta.
Węzły, które tego nie mówią, wysypują się natychmiast — i dobrze, bo to znaczy,
że miały ukryte założenie.

**Odwrócenie strzałki przyczynowej.** Dziś ciśnienie jest przyczyną: ustawiasz
`state`, węzeł publikuje liczbę, detektor ją klasyfikuje. W symulacji ciśnienie
robi się skutkiem: przedmiot traci kontakt → to jest zdarzenie → model ciśnienia
na nie reaguje. Kierunek strzałki decyduje o tym, czy detektor coś wykrywa, czy
tylko odczytuje twoją decyzję z powrotem.

**Dwa transporty obok siebie, z jawną granicą.** Rzadko widzi się system,
w którym granica między dwoma światami komunikacyjnymi jest osobnym procesem —
takim, który można zabić, podejrzeć i źle skonfigurować. `ros_gz_bridge` jest
dokładnie tym. Po jego postawieniu masz **dwa grafy do introspekcji zamiast
jednego**, a umiejętność ustalenia, po której stronie mostu dane się urywają,
to jest dokładnie ta kompetencja, za którą ci zapłacą.

**Determinizm jako przewaga, której rzeczywistość nie ma.** Prawdziwe stanowisko
nigdy nie powtórzy przebiegu: tarcie zależy od kurzu, przyssawka się zużywa,
temperatura pełza. Symulacja może powtórzyć co do bitu. Skoro może — **musi**,
bo inaczej marnujesz jedyną rzecz, której nie dostaniesz nigdzie indziej.

## Dlaczego to trudne

Nie dlatego, że fizyka jest skomplikowana. Dlatego, że **wszystko tu psuje się
cicho**.

| co zrobisz źle | co zobaczysz |
|---|---|
| zapomnisz systemu `Physics` | świat wstaje, nic nie spada |
| zapomnisz `SceneBroadcaster` | serwer liczy poprawnie, GUI pokazuje pustkę |
| pomylisz nazwę typu gz w moście | most startuje, `ros2 topic list` pokazuje topic, `echo` milczy |
| źle ustawisz `GZ_SIM_RESOURCE_PATH` | świat ładuje się bez modelu, którego `<include>` nie znalazł |
| pominiesz most dla `/clock` przy `use_sim_time:=true` | węzeł startuje, spinuje i nie robi nic — bo dla niego jest wiecznie chwila zero |

Ani jeden z tych przypadków nie kończy się niezerowym kodem wyjścia. Backendowa
intuicja („jak się nie wywaliło, to działa") jest tu aktywnie szkodliwa.

Do tego wiedza plemienna, której nie ma w jednym miejscu: nazwę systemu wpisuje
się **dwa razy** — raz jako `filename` biblioteki, raz jako `name` klasy — i obie
muszą się zgadzać; atrybut `type` w `<physics>` jest ignorowany, a mimo to wszyscy
piszą tam `type="ignored"`; binarka `gz` przychodzi z pakietów `*-vendor`
zainstalowanych **wewnątrz drzewa ROS-a**, więc nie ma jej w PATH bez sourcowania
`/opt/ros/jazzy/setup.bash`; `gz topic -e` drukuje tekstowy protobuf, a nie YAML
jak `ros2 topic echo`. A w tym repo GUI nie wstanie, więc „model wpadł pod
podłogę" musisz wyczytać z liczb, nie z obrazka.

## Model pojęciowy

### Krok, iteracja, RTF

Gazebo Sim liczy świat **stałym krokiem**. To fundament wszystkiego dalej:

```xml
<physics name="1ms" type="ignored">
  <max_step_size>0.001</max_step_size>
  <real_time_factor>1.0</real_time_factor>
</physics>
```

`max_step_size` to ile czasu **symulowanego** przypada na jedną iterację (tu
1 ms) — nie zależy od tego, jak szybki masz procesor. `real_time_factor` to
**cel**, nie pomiar: 1.0 znaczy „staraj się, żeby sekunda symulacji trwała
sekundę ścienną", 0 znaczy „leć, ile wlezie".

Stąd rzecz nieoczywista: **RTF nie wpływa na wynik fizyki.** 3000 iteracji po
1 ms to zawsze te same 3 sekundy symulowane i ta sama trajektoria, niezależnie
od tego, czy policzyły się w sekundę, czy w minutę. RTF zmienia tylko to, *kiedy*
wyniki docierają na zewnątrz — czyli do twoich węzłów ROS-a.

RTF **faktyczny** czytasz ze statystyk świata:

```bash
gz topic -e -t /world/stanowisko/stats | head -n 40
```

`real_time_factor: 0.3` znaczy, że symulacja idzie trzy razy wolniej niż życie.
To nie awaria — to liczba, na którą się patrzy.

### Encje, komponenty, systemy — i dlaczego nic nie dzieje się samo

Gazebo Sim jest ECS-em: świat to **encje** (modele, linki, złącza) z doczepionymi
**komponentami** (pozycja, masa, geometria kolizji), a **systemy** to funkcje
przemiatające komponenty w fazach `Configure` (raz, przy ładowaniu), `PreUpdate`,
`Update`, `PostUpdate`.

Konsekwencja tłumaczy 80% pytań na forach: **nic nie dzieje się domyślnie**.
Pozycja modelu zmienia się tylko dlatego, że system `Physics` przeczytał
komponenty i je nadpisał. Nie ma go — pozycje stoją, a silnik nie uważa tego za
błąd, bo świat bez fizyki to poprawny świat.

Systemy, które w Harmonic wpisujesz do `<world>` ręcznie:

| `filename` w SDF | `name` w SDF | bez niego |
|---|---|---|
| `gz-sim-physics-system` | `gz::sim::systems::Physics` | nic się nie porusza |
| `gz-sim-user-commands-system` | `gz::sim::systems::UserCommands` | nie da się z zewnątrz dodać, usunąć ani przestawić modelu |
| `gz-sim-scene-broadcaster-system` | `gz::sim::systems::SceneBroadcaster` | nikt nie dostaje pozycji: ani GUI, ani `pose/info` |
| `gz-sim-sensors-system` | `gz::sim::systems::Sensors` | kamery i lidary nie publikują |
| `gz-sim-contact-system` | `gz::sim::systems::Contact` | czujniki kontaktu milczą |

Czujnik kontaktu obsługuje `Contact`, nie `Sensors` — `Sensors` odpowiada za
czujniki wymagające renderowania. Dopóki nie masz w scenie kamery, `Sensors` nic
nie robi; gdy ją dodasz, bezgłowo potrzebujesz `--headless-rendering`.
Uruchamiaj z `-v 4`, dopóki nie nabierzesz wprawy — to jedyny sposób, żeby
zobaczyć, które systemy naprawdę się załadowały.

### Dwa światy komunikacyjne i most między nimi

Gazebo ma **własny transport** (gz-transport) i **własne typy wiadomości**
(gz-msgs). To nie jest DDS, nie jest ROS, i ROS tego nie widzi. Introspekcja po
tej stronie ma swój komplet narzędzi:

```bash
gz topic -l                                 # jakie topiki istnieją po stronie gz
gz topic -i -t /world/stanowisko/stats      # jakiego są typu
gz topic -e -t /clock                       # co tamtędy leci
gz service -l                               # jakie usługi wystawia serwer
```

To są odpowiedniki `list-topics.sh`, `show-topic-connections.sh`
i `print-topic-messages.sh` z `scripts/dev/ros2/` — tylko dla drugiego grafu.
Od tej pory każde pytanie „czy dane płyną" ma **dwie** odpowiedzi.

`ros_gz_bridge` to osobny proces, który subskrybuje po jednej stronie i publikuje
po drugiej. Konfiguruje się go mapowaniami w postaci `/topic@typ_ros@typ_gz`,
gdzie znak między typami mówi o kierunku:

| znak | kierunek | jak to pamiętać |
|---|---|---|
| `@` | dwukierunkowo | most w obie strony |
| `[` | Gazebo → ROS | dane **wchodzą** do ROS-a |
| `]` | ROS → Gazebo | dane **wychodzą** z ROS-a |

Zegar bierzemy z symulacji, więc jednokierunkowo:

```bash
ros2 run ros_gz_bridge parameter_bridge \
  /clock@rosgraph_msgs/msg/Clock[gz.msgs.Clock
```

Przy trzech topikach lista argumentów robi się nieczytelna, przy dziesięciu —
nie do utrzymania. Dlatego most czyta też plik YAML:

```yaml
- ros_topic_name: "/clock"
  gz_topic_name: "/clock"
  ros_type_name: "rosgraph_msgs/msg/Clock"
  gz_type_name: "gz.msgs.Clock"
  direction: GZ_TO_ROS

- ros_topic_name: "/kontakt_chwytak"
  gz_topic_name: "/stanowisko/kontakt_chwytak"
  ros_type_name: "ros_gz_interfaces/msg/Contacts"
  gz_type_name: "gz.msgs.Contacts"
  direction: GZ_TO_ROS
```

```bash
ros2 run ros_gz_bridge parameter_bridge --ros-args -p config_file:=<ścieżka>/bridge.yaml
```

Plik wygrywa z argumentami z jednego powodu: **jest wersjonowany razem z kodem**.
Most uruchamiany z pamięci to konfiguracja, której nikt nie odtworzy.

Nazw typów nie wpisuj z głowy. Pełna tabela odwzorowań ROS ↔ gz jest w README
projektu `ros_gz`; para, której tam nie ma, kończy się mostem, który startuje
i milczy.

### Zegar symulacji

Serwer publikuje `/clock` po stronie Gazebo, most przenosi go do ROS-a, a każdy
węzeł, który ma żyć w czasie symulacji, potrzebuje `use_sim_time:=true` —
mechanizm rozebrałeś w [etapie 02](./02-czas-zdarzenia-stan.md), tutaj tylko
podłączasz źródło. Co się dzieje przy RTF 0,3, gdy węzeł o tym nie wie:

| element | `use_sim_time:=true` | bez, przy RTF 0,3 |
|---|---|---|
| timer `1.0/50` w `vacuum_sensor.py` | 50 tyknięć na sekundę **symulowaną** | 50 na sekundę ścienną, czyli 167 na sekundę symulowaną |
| `deque(maxlen=25)` w `grasp_monitor.py` | zbiera 0,5 s symulacji | zbiera 0,15 s symulacji — inne uśrednienie, inne progi |
| stemple w bagu | rosną w tempie symulacji | rosną w tempie ściennym, nie zestawisz ich z przebiegiem |

Najgorsze jest to, że **nic nie protestuje**: detektor dalej publikuje werdykty,
tylko liczy je na innym oknie, niż myślisz. A przy `use_sim_time:=true` bez mostu
dla `/clock` węzeł zamiera — zegar stoi w zerze, timery nigdy nie dojrzewają,
proces żyje i nie robi nic.

### Determinizm i jego granica

Przy stałym kroku i tej samej sekwencji iteracji Gazebo daje ten sam wynik.
Psują to:

| co psuje | dlaczego |
|---|---|
| zmiana `max_step_size` | inny krok całkowania = inna trajektoria, natychmiast i nieodwracalnie |
| losowe ziarno | jeśli coś w scenie losuje, bez ustalonego ziarna losuje inaczej (`gz sim --help`) |
| czujniki renderujące | renderowanie chodzi własnym rytmem i potrafi zgubić klatkę |
| kolejność ładowania modeli | inne ID encji, inna kolejność rozwiązywania kontaktów |
| **ROS po drugiej stronie mostu** | patrz niżej |

Ostatni wiersz jest najważniejszy i nikt nie pisze go wprost: **determinizm
kończy się na granicy mostu.** Po stronie Gazebo masz powtarzalne liczby; po
stronie ROS-a masz wątki, egzekutory, kolejki QoS i planistę systemowego. Ten sam
przebieg nagrany dwa razy da dwa różne bagi — inne stemple odbioru, inny przeplot
topików, czasem inna liczba wiadomości na `BEST_EFFORT`.

Wniosek praktyczny: **porównuj to, co deterministyczne** (wydruk z gz-transportu,
stan świata po N iteracjach), a od strony ROS-a wymagaj powtarzalności
tolerancyjnej, nie bajtowej. Kto tego nie rozdziela, pisze testy, które migoczą,
i po miesiącu je wyłącza.

### Gdzie to mieszka w repo

`AGENTS.md` mówi: *wszystko, co MUSI być pakietem, jest pakietem*. Świat, do
którego odwołuje się launch, konfiguracja mostu i modele — muszą. Nowy pakiet
obok `grip_monitor`:

```
ws/src/grip_sim/
├── worlds/stanowisko.sdf
├── models/przedmiot/{model.config,model.sdf}
├── models/stol/{model.config,model.sdf}
├── config/bridge.yaml
├── launch/stanowisko.launch.py
├── package.xml
└── setup.py
```

`grip_monitor` **monitoruje**, `grip_sim` **dostarcza świat** — dwa pakiety, bo
dwie odpowiedzialności i dwa tempa zmian.

`GZ_SIM_RESOURCE_PATH` to rozdzielona dwukropkami lista katalogów, w których
Gazebo szuka modeli przy `<include><uri>model://nazwa</uri></include>`. Wskazuje
katalog **zawierający** katalogi modeli:

```bash
export GZ_SIM_RESOURCE_PATH=/home/maniumek/repos/robotics/ws/install/grip_sim/share/grip_sim/models
```

Trzymanie modeli w pakiecie zamiast ściągania z Fuel ma w tym kontenerze
konkretny powód: cache Fuel ląduje w `~/.gz/` **wewnątrz kontenera** i znika przy
każdym Rebuild Container. Świat zależny od pobierania to świat, który nie wstanie
w CI ([etap 11](./11-ci-i-awarie.md)).

### Uczciwie: czego ten symulator nie liczy

| zjawisko | co robi Gazebo | co z tego wynika |
|---|---|---|
| tarcie | współczynnik na parze materiałów, model Coulomba | dobierasz go pod wynik, którego oczekujesz — to nie jest pomiar |
| deformacja przedmiotu | nic, ciała są sztywne | karton, gąbka i folia zachowują się identycznie |
| przepływ powietrza | nic | nie ma czegoś takiego jak „podciśnienie" w tej fizyce |
| uszczelnienie przyssawki | nic | kluczowe zjawisko całego projektu jest poza modelem |

Stąd granica twojej roli, i trzeba ją powiedzieć wprost: **symulacja służy do
testowania LOGIKI i INTEGRACJI, nie do dowodzenia, że chwyt się uda.** Zdanie
„w symulacji trzymało" nie jest argumentem o sprzęcie i nigdy nim nie będzie.

Model ciśnienia, który tu zbudujesz, też będzie przybliżeniem — ale
przybliżeniem, które **reaguje na zdarzenia**: jest kontakt, jest ciśnienie;
kontakt znika, ciśnienie wraca do zera z jakąś stałą czasową. To o dwie klasy
lepiej niż stała w `if`-ie, bo zbocze pojawia się samo, w chwili wyznaczonej
przez fizykę, a nie przez twoją rękę.

## Zadania

### Zadanie 07.1 — Gazebo w obrazie, nie w kontenerze (rdzeń)

**Cel:** mieć Harmonic w odtwarzalnym środowisku i zobaczyć, że cokolwiek chodzi.

W `.devcontainer/Containerfile`, w miejscu przygotowanym na pakiety:

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
      ros-jazzy-ros-gz \
 && rm -rf /var/lib/apt/lists/*
```

Jeden wiersz, ale ciągnie sporo. `ros-jazzy-ros-gz` to metapakiet: przynosi
`ros_gz_bridge`, `ros_gz_sim`, `ros_gz_image` i `ros_gz_interfaces`, a razem
z nimi **całe Gazebo Harmonic** jako pakiety `ros-jazzy-gz-*-vendor`
(`gz-sim-vendor`, `gz-transport-vendor`, `gz-tools-vendor`, `gz-msgs-vendor`,
`gz-common-vendor`, `gz-math-vendor`, `sdformat-vendor` i kilka dalszych).
Nie instaluj `gz-harmonic` z repozytorium OSRF — w tym obrazie to repozytorium
nie jest skonfigurowane, a wersja z ROS-a i tak jest tą, z którą `ros_gz` się
skompilował. Binarka nazywa się `gz`, nie `ign` i nie `gazebo`.

Rebuild Container, potem:

```bash
gz sim --version
gz sim -s -r --iterations 2000 shapes.sdf
```

`shapes.sdf` jest gotowym światem z Gazebo; serwer policzy 2000 iteracji i sam
się zakończy.

**Gotowe, gdy:** `gz sim --version` wypisuje wersję Gazebo Sim 8 (to jest
Harmonic), a bieg `shapes.sdf` kończy się sam, bez błędu i **nie prosząc
o ekran**.

> `gz: command not found` przy wywołaniu z Fedory to nie brak pakietu. Binarka
> wchodzi do PATH dopiero po sourcowaniu `/opt/ros/jazzy/setup.bash`, które to
> repo trzyma w `/etc/profile.d/ros2.sh` — czyli wołaj przez powłokę logowania,
> dokładnie tak jak `run-in-devcontainer` z `scripts/lib/container.sh`.

### Zadanie 07.2 — Własny świat SDF od zera (rdzeń)

**Cel:** napisać najmniejszy świat, który naprawdę działa, i wiedzieć, po co jest
w nim każda linia.

Załóż pakiet `ws/src/grip_sim/` (ament_python, jak `grip_monitor`) i napisz
`worlds/stanowisko.sdf`:

```xml
<?xml version="1.0"?>
<sdf version="1.10">
  <world name="stanowisko">

    <physics name="1ms" type="ignored">
      <max_step_size>0.001</max_step_size>
      <real_time_factor>1.0</real_time_factor>
    </physics>

    <plugin filename="gz-sim-physics-system" name="gz::sim::systems::Physics"/>
    <plugin filename="gz-sim-user-commands-system" name="gz::sim::systems::UserCommands"/>
    <plugin filename="gz-sim-scene-broadcaster-system" name="gz::sim::systems::SceneBroadcaster"/>
    <plugin filename="gz-sim-contact-system" name="gz::sim::systems::Contact"/>

    <light type="directional" name="sun">
      <pose>0 0 10 0 0 0</pose>
      <diffuse>0.8 0.8 0.8 1</diffuse>
      <direction>-0.5 0.1 -0.9</direction>
    </light>

    <model name="ground_plane">
      <static>true</static>
      <link name="link">
        <collision name="collision"><geometry>
          <plane><normal>0 0 1</normal><size>10 10</size></plane></geometry></collision>
        <visual name="visual"><geometry>
          <plane><normal>0 0 1</normal><size>10 10</size></plane></geometry></visual>
      </link>
    </model>

    <model name="przedmiot">
      <pose>0 0 0.9 0 0 0</pose>
      <link name="link">
        <inertial>
          <mass>0.2</mass>
          <inertia><ixx>8.3e-5</ixx><iyy>8.3e-5</iyy><izz>8.3e-5</izz>
                   <ixy>0</ixy><ixz>0</ixz><iyz>0</iyz></inertia>
        </inertial>
        <collision name="collision"><geometry>
          <box><size>0.05 0.05 0.05</size></box></geometry></collision>
        <visual name="visual"><geometry>
          <box><size>0.05 0.05 0.05</size></box></geometry></visual>
      </link>
    </model>

  </world>
</sdf>
```

Bezwładność nie jest z sufitu: dla sześcianu o boku *a* i masie *m* to
`m·(a²+a²)/12`, czyli `0.2·(0.05²+0.05²)/12 ≈ 8.3e-5`. Zły moment bezwładności
to najczęstsza przyczyna przedmiotów, które drgają albo odlatują.

W `setup.py` dołóż instalację danych — uwaga, `data_files` **nie zachowuje
drzewa katalogów**, więc każdy katalog wymienia się osobno:

```python
data_files=[
    ('share/ament_index/resource_index/packages', ['resource/grip_sim']),
    ('share/grip_sim', ['package.xml']),
    ('share/grip_sim/worlds', glob('worlds/*.sdf')),
    ('share/grip_sim/config', glob('config/*.yaml')),
    ('share/grip_sim/models/przedmiot', glob('models/przedmiot/*')),
],
```

**Gotowe, gdy:** `gz sim -s -r -v 4 --iterations 3000 <ścieżka>/stanowisko.sdf`
kończy się bez błędu, w logu widzisz cztery załadowane systemy, a
`gz topic -e -t /world/stanowisko/dynamic_pose/info` (z drugiego terminala,
w trakcie biegu) pokazuje, jak `z` przedmiotu maleje do ~0,025.

### Zadanie 07.3 — Most i dwa grafy (rdzeń)

**Cel:** wystawić `/clock` do ROS-a i umieć powiedzieć, po której stronie mostu
stoją dane.

Napisz `config/bridge.yaml` (wzór wyżej), uruchom serwer bez `--iterations`,
w drugim terminalu most, a w trzecim zrób sobie wykład z tego, że masz dwa grafy:

```bash
gz topic -l     | grep clock        # źródło
ros2 topic list | grep clock        # ujście
scripts/dev/ros2/print-topic-messages.sh /clock --once
```

Potem oba węzły z czasem symulacji:

```bash
scripts/dev/ros2/run-node.sh grip_monitor vacuum_sensor --ros-args -p use_sim_time:=true
scripts/dev/ros2/run-node.sh grip_monitor grasp_monitor --ros-args -p use_sim_time:=true
```

**Gotowe, gdy:** `/clock` widać po obu stronach, a `measure-topic-rate.sh
/vacuum_pressure` pokazuje mniej więcej 50 · RTF herców mierzonych zegarem
ściennym — i umiesz wyjaśnić, dlaczego to jest **poprawne**, a nie zepsute.

> Skrypty w `scripts/dev/ros2/` opisują tylko graf ROS-a. Jeśli zaczniesz często
> sięgać po `gz topic -l`, konwencja z `AGENTS.md` mówi, jak nazwać skrypt, który
> to opakuje: `list-` oddaje terminal i niczego nie zmienia.

### Zadanie 07.4 — Scena: stół, przedmiot, chwytak bez napędów (rdzeń)

**Cel:** zbudować geometrię, w której da się wywołać upadek, i wystawić zdarzenie
kontaktu.

Dołóż model stołu (statyczny blat na wysokości ~0,75 m) i prosty chwytak: jedna
bryła zawieszona nad stołem, na razie **statyczna**. Napędy, złącza, przyczepianie
przedmiotu i `ros2_control` to cały [etap 08](./08-tf2-urdf-ros2-control.md) —
tutaj tego nie ruszaj.

Do linku chwytaka (albo przedmiotu) dołóż czujnik kontaktu:

```xml
<sensor name="czujnik_kontaktu" type="contact">
  <always_on>true</always_on>
  <update_rate>50</update_rate>
  <contact><collision>collision</collision></contact>
  <topic>/stanowisko/kontakt_chwytak</topic>
</sensor>
```

Ustaw pozycję początkową przedmiotu tak, żeby po starcie spadał **na** stół,
a nie przez stół.

**Gotowe, gdy:** `gz topic -e -t /stanowisko/kontakt_chwytak` milczy, dopóki
przedmiot leci, i zaczyna publikować w chwili zetknięcia — a po dopisaniu wpisu
do `bridge.yaml` ten sam moment widać po stronie ROS-a jako
`ros_gz_interfaces/msg/Contacts`. To twoje pierwsze **zdarzenie fizyczne**,
którego nie wywołałeś ręcznie.

### Zadanie 07.5 — Przebieg z symulacji do baga (rdzeń)

**Cel:** domknąć pętlę z [etapem 03](./03-bagi-jako-dane.md) — symulacja jako
generator danych testowych.

```bash
ros2 bag record -s mcap -o projects/grab-fail-detection/bags/sim-upadek \
  /clock /kontakt_chwytak /vacuum_pressure /grasp_verdict
```

Zanim uruchomisz, sprawdź `ros2 bag record --help` pod kątem czasu symulacji:
recorder ma własny zegar i musisz świadomie zdecydować, czy stemple odbioru mają
być symulowane, czy ścienne. Katalog `bags/` jest w `.gitignore` — to dane, nie
kod. Odtwórz nagranie narzędziami, które już masz.

**Gotowe, gdy:** bag się odtwarza, czas w `/clock` rośnie w tempie symulacji,
a ty potrafisz wskazać w danych chwilę kontaktu.

### Zadanie 07.6 — „Zepsuj to": determinizm i zegar (rdzeń, obowiązkowe)

**Cel:** zobaczyć, że powtarzalność jest właściwością, którą się utrzymuje, a nie
którą się dostaje.

**Wariant A — ten sam bieg dwa razy.** Zbieraj wydruk po stronie Gazebo, bo tylko
tam determinizm jest bajtowy:

```bash
bieg () {
  gz topic -e -t /world/stanowisko/dynamic_pose/info > "$1" &
  local pid=$!
  sleep 1
  gz sim -s -r --iterations 3000 <ścieżka>/stanowisko.sdf
  sleep 1
  kill "$pid"
}

bieg /tmp/bieg-1.txt
bieg /tmp/bieg-2.txt
md5sum /tmp/bieg-1.txt /tmp/bieg-2.txt
```

Różna liczba wierszy nie znaczy jeszcze, że fizyka nie jest deterministyczna —
znaczy, że `gz topic -e` dołączył w innym momencie. Wyrównaj próbki (`head -n`),
zanim oskarżysz silnik. To sam w sobie dobry wniosek o tym, co właściwie mierzysz.

**Wariant B — zepsuj krok.** Zmień `max_step_size` na `0.002` i powtórz. Wyniki
rozjadą się natychmiast i nie zbiegną się już nigdy. Drugi sposób na to samo:
`<real_time_factor>0</real_time_factor>` i porównanie tego, co widzi ROS.

**Wariant C — zepsuj zegar.** Usuń wpis `/clock` z `bridge.yaml`, zostawiając
`use_sim_time:=true` w węzłach, i zapytaj narzędziami:

```bash
scripts/dev/ros2/list-running-nodes.sh
scripts/dev/ros2/measure-topic-rate.sh /vacuum_pressure
```

**Gotowe, gdy:** umiesz pokazać trzy rzeczy: (1) dwa identyczne wydruki
z wariantu A, (2) rozjazd po zmianie kroku w wariancie B, (3) w wariancie C węzły
widoczne na liście, ale zero wiadomości, bo dla nich czas stoi w zerze. Umiesz
też powiedzieć, dlaczego bag nagrany dwa razy w wariancie A **nie** będzie
identyczny, mimo że symulacja była.

### Zadanie 07.7 — Dziesięć razy szybciej (rozszerzenie)

**Cel:** znaleźć najsłabsze ogniwo pipeline'u, zanim znajdzie je CI.

Ustaw `<real_time_factor>10</real_time_factor>` i puść całość razem z mostem,
węzłami i nagrywaniem. Pytania, na które ma odpowiedzieć twój wydruk:

- Jaki RTF **faktycznie** osiągasz? (`/world/stanowisko/stats` — cel to nie pomiar.)
- Co wysiada pierwsze: most, `BEST_EFFORT` na `/vacuum_pressure`, recorder baga,
  czy okno 25 próbek w `grasp_monitor.py`?
- Czy `/grasp_verdict` nadal leci z tą samą częstotliwością **w czasie
  symulacji**, czy tylko w ściennym?

**Gotowe, gdy:** masz w `projects/grab-fail-detection/NOTES.md` jedno zdanie
zaczynające się od „przy 10× pierwsze wysiada…", poparte liczbą.

## Pułapki

| objaw | przyczyna | co zrobić |
|---|---|---|
| `gz: command not found` przy `podman exec` | binarki z pakietów `*-vendor` wchodzą do PATH dopiero po sourcowaniu `/opt/ros/jazzy/setup.bash` | wołaj przez powłokę logowania (`bash -lc`), tak jak `run-in-devcontainer`; nie doinstalowuj niczego |
| świat wstaje, nic nie spada | brak systemu `gz::sim::systems::Physics` | dopisz `<plugin>`, uruchom z `-v 4` i przeczytaj listę załadowanych systemów |
| serwer liczy, ale GUI (albo `pose/info`) puste | brak `SceneBroadcaster` | dopisz `gz-sim-scene-broadcaster-system` |
| `ros2 run ros_gz_sim create` nic nie robi i nie zgłasza błędu | brak `UserCommands` — nie ma usługi, do której się dobija | dopisz `gz-sim-user-commands-system`; sprawdź `gz service -l` |
| most chodzi, `ros2 topic list` pokazuje topic, `echo` milczy | nazwa typu gz nie zgadza się z faktycznym typem topicu | `gz topic -i -t /topic` poda prawdziwy typ; porównaj znak po znaku |
| węzeł z `use_sim_time:=true` żyje i nie publikuje | brak `/clock` w ROS-ie — czas stoi w zerze, timery nie dojrzewają | uruchom most dla `/clock` **przed** węzłami |
| `model://x` ignorowane, świat wstaje bez modelu | `GZ_SIM_RESOURCE_PATH` nie wskazuje katalogu **zawierającego** katalogi modeli, albo brak `model.config` | popraw ścieżkę; sprawdź, że model ma `model.config` i `model.sdf` |
| pierwszy start świata z Fuel wisi minutę, po Rebuild znowu | modele lecą z sieci do cache'u `~/.gz/` w kontenerze, który nie przeżywa przebudowy | trzymaj modele w `ws/src/grip_sim/models/` |
| zmiana w `worlds/*.sdf` nie działa mimo `--symlink-install` | `data_files` bywa kopiowane, nie linkowane | przebuduj pakiet albo w czasie iteracji celuj wprost w plik w `ws/src/` |
| dwie symulacje widzą nawzajem swoje topiki | `--network=host` plus domyślna partycja gz-transport | rozdziel je zmienną `GZ_PARTITION` |
| `cannot open display` przy `gz sim` bez `-s` | kontener nie ma przekazanego ekranu | [etap 05](./05-introspekcja-qos-narzedzia.md), albo pracuj bezgłowo |
| przedmiot drga albo odlatuje po dotknięciu stołu | zły `<inertia>` albo za duży krok czasowy dla tej geometrii | policz bezwładność ze wzoru; zmniejsz `max_step_size` |

### GUI: wygoda, nie tryb pracy

`gz sim` bez `-s` próbuje otworzyć okno i w tym kontenerze się nie uda.
Przekazanie GUI (Wayland, SELinux, podman rootless) to zadanie z
[etapu 05](./05-introspekcja-qos-narzedzia.md) i tam jest jego miejsce. Droga
awaryjna, gdy ekranu nie ma: serwer bezgłowo (`gz sim -s -r`), most, i podgląd
danych przez `foxglove_bridge` w przeglądarce na Fedorze — albo w ogóle bez
podglądu na żywo: nagraj bag i obejrzyj po fakcie narzędziami z
[etapu 03](./03-bagi-jako-dane.md).

I tak będziesz pracował głównie tak. Bezgłowo to **jedyny tryb, który pojedzie
w CI** ([etap 11](./11-ci-i-awarie.md)) i jedyny, który da się uruchomić dwieście
razy w nocy. GUI włączasz, gdy nie rozumiesz, co się stało — i wtedy dopinasz sam
klient (`gz sim -g`) do już działającego serwera.

## Sprawdź się

1. Dlaczego zmiana `real_time_factor` **nie** zmienia trajektorii przedmiotu,
   a zmiana `max_step_size` zmienia ją natychmiast?
2. Świat wstaje, nic nie spada. Które trzy rzeczy sprawdzasz, w jakiej kolejności
   i dlaczego w tej?
3. `/clock` jest po stronie Gazebo, most działa, a `ros2 topic echo /clock`
   milczy. Jak w trzech poleceniach ustalasz, po której stronie dane się urywają?
4. Dlaczego dwa identyczne przebiegi symulacji dają dwa **różne** bagi, mimo że
   fizyka policzyła się identycznie? Co z tego wynika dla testu w CI?
5. Węzeł z `use_sim_time:=true` jest na liście i nic nie publikuje. Co się dzieje
   w środku i dlaczego nikt nie zgłasza błędu?
6. Dlaczego „w symulacji chwyt trzymał 30 sekund" nie jest argumentem o przyssawce
   na prawdziwym stanowisku? Wymień dwa zjawiska, których ten silnik nie liczy.
7. Po co rozdzielać `grip_monitor` i `grip_sim` na dwa pakiety, skoro colcon i tak
   buduje jeden workspace?
8. Co zyskujesz, nagrywając ciśnienie z symulacji, czego nie dawał `gauss(0, 0.5)`
   — poza tym, że „jest bardziej realne"?

## Co przeczytać

- **https://gazebosim.org/docs/harmonic/** — dokumentacja tej konkretnej wersji.
  Nazwy systemów i bibliotek bierz stamtąd, nie z odpowiedzi na forach: połowa
  z nich dotyczy jeszcze `ign`.
- **http://sdformat.org/** — specyfikacja SDF. Zaglądaj, gdy nie wiesz, czy dany
  element ma sens w tym miejscu; SDF wybacza nieznane tagi, więc literówki sam
  nie zobaczysz.
- **https://github.com/gazebosim/ros_gz** — README mostu z tabelą odwzorowań
  typów ROS ↔ gz. Jedyne miejsce, gdzie sprawdzisz, czy twoja para typów istnieje.
- **https://github.com/gazebosim/gz-sim** — katalog `examples/worlds` w źródłach.
  Najszybsza nauka składni SDF: gotowe światy, które na pewno działają.
- **https://docs.ros.org/en/jazzy/** — `use_sim_time` jako parametr każdego węzła;
  wracaj tam, gdy przestanie ci się zgadzać, kto komu ustawia zegar.
- **REP-103** — jednostki i układy współrzędnych. Krótkie, a oszczędza wieczoru
  na zastanawianiu się, czemu przedmiot leci w bok zamiast w dół.

## Dziennik

    Co mnie zaskoczyło:

    Co zjadło najwięcej czasu i czy dało się to skrócić:

    Ile trwało, zanim pierwszy raz zobaczyłem /clock po stronie ROS-a
    i co było przyczyną zwłoki:

    Które z moich narzędzi NIE pokazało mi problemu, który miałem:

    Jedno zdanie, którego nie umiałbym napisać tydzień temu:

Dalej → [Etap 08 — Geometria i napędy: TF2, URDF, ros2_control](./08-tf2-urdf-ros2-control.md)
