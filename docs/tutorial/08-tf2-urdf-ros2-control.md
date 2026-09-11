# Etap 08 — Geometria i napędy: TF2, URDF, ros2_control

> Umiesz powiedzieć nie tylko **kiedy** coś się stało, ale i **gdzie** był wtedy
> chwytak — i umiesz to udowodnić z nagrania, zamiast pamiętać.

| | |
|---|---|
| wejście | etapy [02](./02-czas-zdarzenia-stan.md) (stemple, `use_sim_time`, `/clock`) i [07](./07-gazebo-stanowisko.md) (świat w Gazebo Harmonic, most `ros_gz_bridge`); trzy nowe pakiety w `Containerfile` |
| czas | 3–4 wieczory; sam URDF zjada pierwszy z nich i to jest normalne |
| kończy się | ramię jedzie na komendę, chwyta przedmiot przez odłączalne złącze, a `/vacuum_pressure` publikuje wartość wynikającą ze stanu symulacji, nie z parametru ustawionego twoją ręką |

Ten etap wygląda na etap o mechanice. Nie jest. Jest o **obserwowalności**:
dokładasz drugą współrzędną zdarzenia. Stempel czasu z etapu 02 mówi KIEDY.
Układ współrzędnych mówi GDZIE. Dopiero jedno z drugim jest zdarzeniem —
wcześniej masz liczbę, która wisi w próżni.

---

## Po ludzku: co to jest w twoim świecie

| pojęcie robotyczne | odpowiednik z backendu | gdzie analogia pęka |
|---|---|---|
| drzewo TF | trace context propagowany przez system | nie jedzie razem z danymi — leci osobnym kanałem (`/tf`) i sklejasz go z pomiarem dopiero po stemplu |
| `lookup_transform(a, b, t)` | zapytanie „stan na moment T" do event-sourcowanej bazy | ta baza ma retencję rzędu 10 sekund i **interpoluje** między próbkami, zamiast powiedzieć „brak rekordu" |
| URDF | schemat modelu domeny | opisuje też masę i bezwładność, więc błąd w nim nie rzuca wyjątku, tylko daje model, który sam odlatuje |
| `ros2_control` | warstwa portów i adapterów, wstrzykiwana zależność | pętla ma twardy budżet czasowy; wolniejsza implementacja to nie gorszy SLA, tylko niestabilny regulator |
| `controller_manager` | kontener IoC ładujący wtyczki w czasie działania | wtyczki rywalizują o **wyłączny** dostęp do zasobu (przegubu); dwie naraz to nie wyścig, tylko odmowa startu |
| `joint_state_broadcaster` | eksporter metryk | ładuje się dokładnie tym samym mechanizmem co sterownik i stoi na tej samej liście — stąd klasyczne „mam sterownik, a nic nie jedzie" |

---

## Po co to — czego bez tego nie da się zrobić

Otwórz `ws/src/grip_monitor/grip_monitor/vacuum_sensor.py`. Cała treść pomiaru
to jedna linia:

```python
msg = Float32()
msg.data = state_value + noise
```

`Float32` nie ma `header`. Nie ma więc ani `stamp`, ani `frame_id`. To drugie
jest tu ważniejsze, niż wygląda: pole `frame_id` jest miejscem, w którym
wiadomość mówi, **w jakim układzie współrzędnych ma sens**. Ciśnienie akurat
jest skalarem, ale sąsiednia wiadomość — pozycja, siła, chmura punktów — bez
`frame_id` jest zestawem liczb bez jednostki odniesienia.

Teraz `grasp_monitor.py`:

```python
self.pub.publish(str_msg)   # '[state] sealed'
```

Werdykt „chwyt nieudany" bez pozycji chwytaka jest **bezużyteczny dla analizy**.
Nie wiesz, czy chybił nad pojemnikiem (zły punkt chwytu — problem percepcji),
czy zgubił przedmiot w drodze (za szybki ruch albo słaba uszczelka — problem
ruchu). To są dwa różne defekty, dwie różne poprawki i dwa różne zespoły.
Z twojego nagrania nie wynika, który to był.

Sprawdź to na `projects/grab-fail-detection/bags/chwyt-3-stany/`: 2124
wiadomości, dwa topiki, zero transformacji. Ten bag już nigdy nie odpowie na
pytanie „gdzie". Pytanie „kiedy" naprawiłeś w etapie 02 i **to jest dokładnie
ta sama naprawa, tylko w drugiej osi**.

I rzecz trzecia, najbardziej bolesna:

```python
state = self.get_parameter('state').value
```

Twój czujnik czyta parametr. Parametr ustawia człowiek przez
`scripts/dev/ros2/set-param.sh`. To nie jest pomiar, to jest deklaracja.
Po tym etapie ciśnienie bierze się ze stanu symulacji — z tego, czy złącze
faktycznie powstało — i dopiero wtedy `vacuum_sensor.py` przestaje być
zgadywanką.

---

## Dlaczego to ciekawe

**TF2 to rozproszona baza czasowa bez serwera.** Nie ma centralnego procesu,
który wie, gdzie co jest. Każdy węzeł, który potrzebuje transformacji,
subskrybuje `/tf` i buduje **własną** kopię bufora. Nadawcy nie wiedzą,
kto ich słucha, i nie obchodzi ich, ilu jest odbiorców. Cały układ to
kilkanaście małych strumieni krawędzi grafu, z których każdy odbiorca składa
sobie drzewo. Backendowo: replikacja z eventual consistency, w której
„eventual" ma wartość liczbową i nazywa się opóźnieniem nadawcy.

**Baza zwraca rekord, którego nigdy nie było.** Gdy pytasz o transformację
w chwili między dwiema próbkami, tf2 interpoluje: liniowo po translacji,
slerpem po obrocie. To decyzja projektowa, nie niedoróbka — bez niej złożenie
pomiaru z kamery (30 Hz) z pozycją ramienia (100 Hz, inne fazy) byłoby
niemożliwe. Cena: nigdy nie dostaniesz błędu „nie mam danych na ten moment",
dopóki jesteś w środku przedziału.

**Rozdzielenie wiedzy o geometrii od jej użycia.** `robot_state_publisher` nie
wie nic o twoim zastosowaniu. Dostaje URDF (statyczna geometria) plus
`/joint_states` (zmienne w czasie) i wypluwa `/tf`. Jedna instancja obsługuje
wszystkich odbiorców w systemie. Twój kod nigdy nie liczy kinematyki prostej —
pyta bazę.

**`ros2_control` to wstrzykiwanie zależności w robotyce.** Między „chcę, żeby
ramię tu pojechało" a sterownikiem silnika stoi warstwa z jednym zadaniem:
uczynić górę niezależną od dołu. Ten sam plik YAML ze sterownikami i ten sam
kod aplikacji pójdzie na prawdziwy sprzęt — zmienia się **wyłącznie**
interfejs sprzętowy (`gz_ros2_control/GazeboSimSystem` na sterownik magistrali).
To jedyny znany mi sensowny sposób, żeby warstwa ruchu była w ogóle testowalna.

**Podciśnienia nikt tu nie liczy.** Chwyt w symulacji to nie model przepływu
gazu, tylko złącze, które powstaje przy kontakcie i znika na komendę. Jedna
linijka kłamstwa, która daje ci powtarzalne awarie na żądanie.

---

## Dlaczego to trudne

**Prawie każdy błąd TF jest w rzeczywistości błędem czasu.** Komunikat mówi
o ramkach, bo to po ramkach tf2 szuka. Ale przyczyną w dziewięciu przypadkach
na dziesięć jest to, że dwie strony mierzą czas różnymi zegarami: jedna ma
`use_sim_time`, druga nie. Będziesz czytał zdanie o `base_link` i szukał
literówki w nazwie, podczas gdy problem jest w parametrze innego węzła.

**URDF nie ma walidatora sensowności.** `check_urdf` sprawdza składnię i to,
czy drzewo jest drzewem. Nie sprawdza, czy masa ramienia to 2 kg czy 2 gramy,
czy tensor bezwładności jest dodatnio określony, czy oś złącza wskazuje tam,
gdzie myślisz. Plik przechodzi walidację, model startuje i rozlatuje się
w pierwszej klatce — a komunikat, jeśli w ogóle padnie, wyleci na stdout
`gz sim`, nie do `/rosout`.

**Logi `ros2_control` w symulacji są w cudzym procesie.** `controller_manager`
przy `gz_ros2_control` nie jest osobnym procesem — żyje **wewnątrz** `gz sim`
jako wtyczka. `ros2 node list` pokaże `/controller_manager`, ale gdy sterownik
odmówi startu, powodu szukaj w terminalu z Gazebo. Ludzie tracą na tym godziny,
bo szukają w `/rosout`, gdzie tego nie ma.

**Wiedza plemienna, której nie ma w dokumentacji:** rozsądne proporcje inercji
dla prostych brył, relacja `update_rate` kontrolera do kroku symulacji,
kolejność „najpierw wstaw model, potem uruchom sterowniki", to, że nazwy
kolizji zmieniają się przy konwersji URDF na SDF. Niczego z tego nie
wydedukujesz — to się zbiera po jednym incydencie.

---

## Model pojęciowy

### Zdarzenie ma dwie współrzędne

Zapisz to sobie, bo cała reszta etapu jest tylko implementacją:

    zdarzenie = (co, kiedy, gdzie)
                      |      |
                 header.stamp  header.frame_id + drzewo TF

Etap 02 dał ci pierwszą. Ten daje drugą. Zdarzenie z jedną z nich to notatka.

### URDF: z czego składa się model

URDF to XML opisujący **drzewo**: linki (bryły sztywne) połączone złączami.
Korzeń nazywa się zwykle `base_link`. Pętle kinematyczne są niedozwolone —
i to jest ograniczenie formatu, nie fizyki.

| typ złącza | stopnie swobody | do czego |
|---|---|---|
| `fixed` | 0 | przykręcony czujnik, flansza, końcówka narzędzia |
| `revolute` | 1 obrót, **z limitami** | przegub ramienia |
| `continuous` | 1 obrót bez limitów | koło, obrotnica |
| `prismatic` | 1 przesunięcie z limitami | oś liniowa, szczęka chwytaka |
| `floating`, `planar` | 6 / 2 | dopuszczone przez format, ale połowa narzędzi ich nie obsługuje — nie zaczynaj od nich |

Link ma do trzech opisów geometrii i to jest najczęstsze źródło nieporozumień:

| blok | kto to czyta | co się stanie, gdy go brakuje |
|---|---|---|
| `<visual>` | rviz2, GUI Gazebo | model niewidoczny, fizyka działa dalej |
| `<collision>` | silnik fizyki | link przenika przez wszystko; **kontakt nigdy nie powstaje, więc chwyt nie zadziała** |
| `<inertial>` | silnik fizyki | model drga, przewraca się albo odlatuje przy starcie |

Brak `<inertial>` to najczęstsza przyczyna „model eksploduje przy starcie".
Mechanizm: URDF bez bezwładności daje link o masie zerowej; konwersja do SDF
albo go pochłonie do rodzica, albo zostawi bryłę, której silnik nie umie
całkować. Tensor liczony ze złej skali (inercja rzędu `1e-9` przy masie 2 kg)
daje ten sam efekt, tylko wygląda groźniej — ramię wibruje, aż wyleci poza świat.
Licz inercję z wzorów dla prostopadłościanu i walca, zaokrąglaj, ale nie zeruj.

### `robot_state_publisher`: skąd on wie, gdzie jest ramię

Nie wie. Dostaje to z zewnątrz i tylko przelicza:

    URDF (geometria, stała)  +  /joint_states (kąty, 50-100 Hz)  ->  /tf

To jest cała jego rola. Konsekwencja praktyczna: jeśli nikt nie publikuje
`/joint_states`, `robot_state_publisher` wstanie bez błędu i będzie nadawał
**wyłącznie** transformacje ze złączy typu `fixed`. Ramię w rviz2 stoi
w pozycji zerowej, żaden komunikat nie mówi dlaczego.

Na czas rozwoju modelu, zanim masz sterowniki, wypełnia tę lukę
`joint_state_publisher` — atrapa, która publikuje kąty z parametrów albo
z suwaków. Gdy dojdzie `ros2_control`, atrapę **wyłączasz**; jej miejsce
zajmuje `joint_state_broadcaster`. Dwa węzły publikujące `/joint_states`
naraz to migoczący model i godzina szukania.

### Xacro: żeby nie przepisywać sześciu identycznych złączy

Xacro to preprocesor XML. Robi trzy rzeczy: właściwości (`${}`), makra
i wyrażenia arytmetyczne. Bez niego model ramienia o sześciu osiach to sześć
prawie identycznych bloków po trzydzieści linii, z których każdy ma szansę
na literówkę.

```xml
<xacro:macro name="box_inertia" params="m x y z">
  <inertial>
    <mass value="${m}"/>
    <inertia ixx="${m*(y*y+z*z)/12}" iyy="${m*(x*x+z*z)/12}" izz="${m*(x*x+y*y)/12}"
             ixy="0" ixz="0" iyz="0"/>
  </inertial>
</xacro:macro>
```

Rozwinięcie sprawdzasz z ręki: `xacro model.urdf.xacro > /tmp/model.urdf`,
potem `check_urdf /tmp/model.urdf`. Rób to **zanim** pójdziesz do launcha —
błędy xacro w launchu wyglądają jak błędy launcha.

### TF2 jako baza danych transformacji w czasie

Trzy rzeczy do zapamiętania.

**Bufor.** Węzeł-odbiorca trzyma okno historii (domyślnie rzędu 10 sekund).
Starsze transformacje wypadają. Jeśli analizujesz zdarzenie sprzed 30 sekund,
musisz powiększyć bufor przy jego tworzeniu — inaczej dostaniesz błąd
ekstrapolacji w przeszłość i pomyślisz, że to problem zegara.

**Zapytanie z konkretnym stemplem.** To jest sedno etapu:

```python
from rclpy.duration import Duration
from rclpy.time import Time
from tf2_ros.buffer import Buffer
from tf2_ros.transform_listener import TransformListener

self.tf_buffer = Buffer(cache_time=Duration(seconds=30))
self.tf_listener = TransformListener(self.tf_buffer, self)

t = self.tf_buffer.lookup_transform(
    'base_link',                       # w czyim układzie chcesz odpowiedź
    'tool_tip',                        # czego pozycji szukasz
    Time.from_msg(msg.header.stamp),   # NA KIEDY
    timeout=Duration(seconds=0.2),
)
```

Podanie `Time()` (czyli zera) znaczy „daj najnowszą, jaką masz". To jest skrót,
który usuwa wszystkie błędy TF **i jednocześnie niszczy cel tego etapu**:
dostajesz pozycję z chwili zapytania, nie z chwili pomiaru. Jeśli twój kod ma
`Time()`, to nie mierzysz — zgadujesz z dokładnością do opóźnienia potoku.

**Dwa kanały.** `/tf` niesie transformacje zmienne w czasie i leci z częstością
nadawcy. `/tf_static` niesie te, które się nie zmieniają — i ma trwałość
`transient_local`, żeby węzeł uruchomiony później dostał je mimo wszystko.
To jest **ten sam mechanizm, którego użyłeś w etapie 02**, tylko tym razem
korzystasz z cudzego ustawienia zamiast dobierać własne. Konsekwencja
praktyczna: statyczną transformację publikuje się raz, nie w pętli. Publikowanie
`/tf_static` cyklicznie jest błędem, który „działa".

### Narzędzia (wszystkie działają bez ekranu)

| polecenie | co daje | uwaga |
|---|---|---|
| `ros2 run tf2_tools view_frames` | plik PDF z całym drzewem i częstotliwościami krawędzi | **działa bez GUI** — zapisuje plik do bieżącego katalogu, PDF otwierasz na Fedorze |
| `ros2 run tf2_ros tf2_echo A B` | pozycja `B` wyrażona w układzie `A`, na żywo | pierwszy argument to układ odniesienia, drugi to rzecz, o którą pytasz |
| `ros2 run tf2_ros tf2_monitor` | średnie i maksymalne opóźnienia oraz częstotliwości **per nadawca** | jedyne narzędzie, które pokaże, że jeden nadawca się spóźnia |

`tf2_tools` jest już w obrazie — nie dokładaj go do `Containerfile`.
Flagi sprawdzaj przez `--help`, bo różnią się między dystrybucjami.

### Trzy komunikaty, które zobaczysz, i co naprawdę znaczą

| fragment komunikatu | co realnie zaszło | pierwsze pytanie |
|---|---|---|
| `extrapolation into the future` | pytasz o czas **nowszy** niż najnowsza dana w buforze | czy pytający i nadawca mają ten sam zegar (`use_sim_time`)? |
| `extrapolation into the past` | pytasz o czas **starszy** niż najstarsza dana — bufor się przewinął albo stemple pochodzą z dwóch różnych zegarów | jak wyżej, plus: czy bufor jest dość długi? |
| `... does not exist` | nazwa ramki nieznana — literówka, albo nadawca jeszcze nie wystartował | `view_frames`: czy ta ramka w ogóle jest w drzewie? |
| cisza / wyjątek tuż po starcie | bufor jest pusty, bo pytasz, zanim cokolwiek przyszło | podaj `timeout=`, zamiast pytać natychmiast |

Zwróć uwagę na symetrię dwóch pierwszych wierszy. Gdy nadawca nadaje czasem
ściennym (`1.79e9` sekund), a odbiorca pyta czasem symulacji (`42.0`), dostajesz
**ekstrapolację w przeszłość**. Gdy role się odwrócą — ekstrapolację w przyszłość.
To jest jedna usterka z dwiema twarzami i dlatego z samego komunikatu nie
wynika, który węzeł jest zepsuty. Wynika tylko, że dwa zegary się rozjechały.

Dlatego zasada: **błąd TF jest domyślnie błędem czasu, dopóki nie udowodnisz,
że jest błędem nazwy.** Kolejność sprawdzania: `use_sim_time` we wszystkich
węzłach, potem rząd wielkości stempli w `/tf`, dopiero potem literówki.

### REP-103 i REP-105: konwencje, których nikt nie sprawdza

REP-103 mówi: jednostki SI (metry, radiany, sekundy, kilogramy), układ
prawoskrętny, **x do przodu, y w lewo, z do góry**. REP-105 mówi, jak nazywają
się i co znaczą ramki: `base_link` przypięty do podstawy robota, `odom` ciągły
ale dryfujący, `map` skokowy ale bez dryfu.

Twoja cela stoi w miejscu, więc `odom` i `map` są ci obojętne. Konwencja osi —
nie. Powód, dla którego łamanie tych konwencji kosztuje więcej niż w zwykłym
softwarze: **cudze pakiety je zakładają i nie sprawdzają**. Nie ma walidacji,
nie ma błędu, nie ma ostrzeżenia. Sterownik chwytaka, wtyczka symulatora,
biblioteka kinematyki — wszystkie przyjmą twoje centymetry i stopnie jako metry
i radiany. Efektem nie jest wyjątek, tylko ramię, które jedzie sto razy za
daleko. W backendzie zła jednostka daje błąd parsowania. Tutaj daje ruch.

### `ros2_control`: po co warstwa pośrednia

Bez niej każda aplikacja gadałaby wprost ze sterownikiem silnika i cały kod
ruchu byłby nieprzenośny między symulacją a sprzętem — czyli nietestowalny.
Warstwa dzieli świat na cztery części:

| element | czym jest | odpowiednik |
|---|---|---|
| `controller_manager` | proces z pętlą o stałej częstości; ładuje wtyczki i pilnuje zasobów | kontener IoC z harmonogramem |
| interfejs sprzętowy | wtyczka gadająca z fizycznym (lub udawanym) sprzętem | adapter portu |
| sterownik | wtyczka licząca komendy z zadania | logika biznesowa |
| interfejsy stanu/komendy | nazwane kanały `<przegub>/<wielkość>` | typowane porty między nimi |

Zasoby są **wyłączne**: jeden interfejs komendy może być zajęty tylko przez
jeden sterownik naraz. Dwa sterowniki na ten sam przegub to nie wyścig, tylko
odmowa aktywacji drugiego. To celowe — inaczej dwa regulatory walczyłyby
o ten sam silnik.

**`joint_state_broadcaster` to nie jest sterownik** i to jest pierwsza rzecz,
która myli. Ładuje się tym samym mechanizmem, stoi na tej samej liście, ma
stan `active` — ale nie zajmuje żadnego interfejsu komendy. Czyta tylko stany
i publikuje `/joint_states` oraz `/dynamic_joint_states`. Jest nadajnikiem,
nie sterownikiem. Bez niego `robot_state_publisher` nie ma z czego liczyć TF,
więc model w rviz2 stoi jak wryty, mimo że ramię w Gazebo się rusza.

`joint_trajectory_controller` to ten, który faktycznie jedzie: przyjmuje
trajektorię (punkty + czasy) akcją `control_msgs/action/FollowJointTrajectory`
albo tematem `~/joint_trajectory`, i interpoluje między punktami. Planowanie
ruchu — czyli wymyślanie tych punktów tak, żeby ominąć przeszkody — to osobna
specjalizacja (MoveIt 2) i w tej roadmapie jej nie ma.

Trzy pliki, w tej kolejności:

```xml
<!-- 1. w URDF: co sprzęt umie -->
<ros2_control name="GazeboSystem" type="system">
  <hardware>
    <plugin>gz_ros2_control/GazeboSimSystem</plugin>
  </hardware>
  <joint name="shoulder_joint">
    <command_interface name="position">
      <param name="min">-1.57</param>
      <param name="max">1.57</param>
    </command_interface>
    <state_interface name="position"/>
    <state_interface name="velocity"/>
    <state_interface name="effort"/>
  </joint>
</ros2_control>
```

```yaml
# 2. w YAML: kto ma czym sterować
controller_manager:
  ros__parameters:
    update_rate: 100  # Hz
    joint_state_broadcaster:
      type: joint_state_broadcaster/JointStateBroadcaster
    arm_controller:
      type: joint_trajectory_controller/JointTrajectoryController

arm_controller:
  ros__parameters:
    joints: [shoulder_joint, elbow_joint]
    command_interfaces: [position]
    state_interfaces: [position, velocity]
```

```bash
# 3. uruchomienie sterowników (albo to samo w launchu)
ros2 run controller_manager spawner joint_state_broadcaster
ros2 run controller_manager spawner arm_controller
```

**Osobna warstwa introspekcji, z własnym CLI.** Obok `ros2 node` i `ros2 topic`
dostajesz `ros2 control`. To nie jest ozdobnik — węzły i topiki nie powiedzą ci
nic o tym, kto trzyma który przegub:

```bash
ros2 control list_controllers          # nazwa, typ, stan (active/inactive)
ros2 control list_hardware_interfaces  # które interfejsy istnieją i kto je zajął
ros2 control --help                    # reszta czasowników
```

Gdy ramię nie jedzie, to jest pierwsze polecenie, nie `ros2 topic echo`.

### `gz_ros2_control`: jak symulacja udaje sprzęt

Wtyczka ładowana do procesu `gz sim`. Implementuje interfejs sprzętowy tak, że
`controller_manager` nie wie, iż po drugiej stronie jest symulator.

```xml
<gazebo>
  <plugin filename="libgz_ros2_control-system.so"
          name="gz_ros2_control::GazeboSimROS2ControlPlugin">
    <parameters>/ścieżka/do/controllers.yaml</parameters>
  </plugin>
</gazebo>
```

Konsekwencja, którą masz docenić: **ten sam `controllers.yaml` i ten sam kod
aplikacji pójdzie później na prawdziwy sprzęt.** Zmienia się jedna linia —
`<plugin>` w bloku `<ros2_control>`. Reszta systemu nie zauważy przeprowadzki.
To jest robotyczny odpowiednik wstrzykiwania zależności i jedyny sensowny sposób
na testowalność warstwy ruchu: możesz odpalić pełny scenariusz ruchu w CI,
bez ani jednego silnika.

### Chwyt podciśnieniowy w symulacji

Nikt nie liczy przepływu gazu. Emulacja stoi na odłączalnym złączu: Gazebo ma
system, który tworzy sztywne złącze między dwoma **modelami** i pozwala je
rozpiąć oraz spiąć z powrotem komendą na temacie.

```xml
<plugin filename="gz-sim-detachable-joint-system"
        name="gz::sim::systems::DetachableJoint">
  <parent_link>tool_tip</parent_link>
  <child_model>box_1</child_model>
  <child_model_link>link</child_model_link>
  <detach_topic>/cell/gripper/detach</detach_topic>
  <attach_topic>/cell/gripper/attach</attach_topic>
  <output_topic>/cell/gripper/state</output_topic>
</plugin>
```

Nie zgaduj nazw parametrów z pamięci i nie kopiuj ich ze starych przykładów
dla Ignition — element nazywa się `child_model_link`, a nie `child_link`,
i to jest dokładnie ten rodzaj różnicy, który Gazebo połknie bez słowa.
Aktualną listę systemów i ich parametrów masz w dokumentacji Harmonic
(`https://gazebosim.org/docs/harmonic/`); sprawdź ją, zamiast strzelać.

Ważne ograniczenie: złącze łączy **dwa modele**, nie dwa linki jednego modelu.
Chwytany przedmiot musi więc być osobnym modelem w świecie z etapu 07.

Logika, którą składasz:

    kontakt na końcówce  ->  komenda spięcia  ->  ciśnienie leci w dół (sealed)
    komenda puszczenia   ->  komenda rozpięcia ->  ciśnienie wraca do zera (open)
    kontakt bez spięcia  ->                        ciśnienie pośrednie (leak)

Kontakt czyta się z czujnika kontaktu na linku końcówki — w URDF wstawia się go
w bloku `<gazebo reference="...">`, bo sam URDF nie zna pojęcia czujnika, a świat
musi mieć załadowany system `gz::sim::systems::Contact`.

I tu jest pointa etapu: **`vacuum_sensor.py` przestaje być zgadywanką.**
Dziś publikuje wartość parametru, który ustawiłeś ręką. Po tym zadaniu publikuje
wartość wynikającą ze stanu symulacji — a to znaczy, że nagranie z chwytu jest
danymi, a nie zapisem twoich decyzji. Cała reszta roadmapy (ewaluacja detektora
w [etapie 10](./10-ewaluacja-na-danych.md), regresje w CI) opiera się na tej
różnicy.

### rviz2 wraca do gry

Do tej pory nie było czego oglądać: dwa skalary i tekst. Teraz jest model, drzewo
TF i kontakty — czyli pierwsza rzecz w tej roadmapie, którą **łatwiej zrozumieć
patrząc niż czytając**. Przekazanie ekranu z kontenera na Fedorze z Waylandem
i SELinuksem jest zadaniem [etapu 05](./05-introspekcja-qos-narzedzia.md) i tam
po nie wróć. Droga bez GUI: `foxglove_bridge` plus Foxglove w przeglądarce —
ma panel 3D, czyta te same `/tf`, `/robot_description` i `/joint_states`.
A `view_frames` i `tf2_echo` nie potrzebują ekranu w ogóle.

---

## Zadania

### Zadanie 08.1 — Ramię z chwytakiem w xacro (rdzeń)

**Cel:** mieć model, który przechodzi walidację i ma sensowną fizykę.

Najpierw środowisko. Do `.devcontainer/Containerfile`, w jednej warstwie
z resztą pakietów etapu 07:

```dockerfile
RUN apt-get update && apt-get install -y \
      ros-jazzy-ros2-control \
      ros-jazzy-ros2-controllers \
      ros-jazzy-gz-ros2-control \
 && rm -rf /var/lib/apt/lists/*
```

Rebuild Container. Nigdy `apt install` w działającym kontenerze — zginie przy
odtworzeniu.

Potem model, w nowym pakiecie `ws/src/cell_description/` (`ament_python`, jak
`grip_monitor`; pliki xacro instalujesz przez `data_files` w `setup.py`).
Minimum: `base_link` → `shoulder_joint` (`revolute`) → `upper_arm` →
`elbow_joint` (`revolute`) → `forearm` → `tool_joint` (`fixed`) → `tool_tip`.
Każdy link ma `<visual>`, `<collision>` **z jawną nazwą** i `<inertial>`.
Inercję licz makrem, nie z ręki.

```bash
xacro ws/src/cell_description/urdf/cell_arm.urdf.xacro > /tmp/cell_arm.urdf
check_urdf /tmp/cell_arm.urdf
```

**Gotowe, gdy:** `check_urdf` wypisuje drzewo z `base_link` jako korzeniem
i wszystkimi czterema linkami, a w `/tmp/cell_arm.urdf` każdy link ma niezerową
masę.

### Zadanie 08.2 — Drzewo transformacji na ekranie (rdzeń)

**Cel:** zobaczyć `/tf` zanim wejdzie symulator, żeby wiedzieć, co jest czyją winą.

```bash
ros2 run robot_state_publisher robot_state_publisher \
  --ros-args -p robot_description:="$(xacro .../cell_arm.urdf.xacro)"
ros2 run joint_state_publisher joint_state_publisher   # atrapa, na razie
ros2 run tf2_tools view_frames
ros2 run tf2_ros tf2_echo base_link tool_tip
ros2 run tf2_ros tf2_monitor
```

Zanim odpalisz `view_frames`, zgadnij na kartce, ile krawędzi zobaczysz i które
przyjdą z `/tf_static`. Potem porównaj. `tf2_monitor` zostaw na minutę i zapisz
średnie opóźnienie — wrócisz do tej liczby w [etapie 09](./09-latencja-i-tracing.md).

**Gotowe, gdy:** masz plik PDF z drzewem czterech ramek, `tf2_echo` wypisuje
zmieniającą się translację `base_link` → `tool_tip`, a ty umiesz powiedzieć,
która krawędź jest statyczna i dlaczego.

### Zadanie 08.3 — Model w świecie i sterowniki na nogach (rdzeń)

**Cel:** `controller_manager` widzi przeguby, a `ros2 control` to potwierdza.

Dokładasz do modelu blok `<ros2_control>` z `gz_ros2_control/GazeboSimSystem`
i blok `<gazebo><plugin ...>` wskazujący `controllers.yaml`. Świat bierzesz
z etapu 07 — nie budujesz go od nowa. Wstawienie modelu:

```bash
ros2 run ros_gz_sim create -topic robot_description -name cell_arm
ros2 control list_hardware_interfaces
ros2 control list_controllers
```

Kolejność ma znaczenie: `controller_manager` startuje razem z modelem, więc
sterowniki uruchamiasz **po** wstawieniu. Gdy `ros2 control` mówi, że nie może
dosięgnąć usługi — model jeszcze nie jest w świecie.

Wyłącz `joint_state_publisher` z poprzedniego zadania. Od teraz `/joint_states`
publikuje `joint_state_broadcaster` i tylko on.

**Gotowe, gdy:** `list_controllers` pokazuje `joint_state_broadcaster` i
`arm_controller` w stanie `active`, `list_hardware_interfaces` pokazuje
interfejsy komendy jako zajęte (`claimed`), a `view_frames` wciąż daje pełne
drzewo — tylko że kąty biorą się już z symulacji.

### Zadanie 08.4 — Ruch do zadanej pozycji (rdzeń)

**Cel:** wysłać trajektorię i zobaczyć ją w trzech miejscach naraz.

```bash
ros2 topic pub --once /arm_controller/joint_trajectory \
  trajectory_msgs/msg/JointTrajectory \
  "{joint_names: [shoulder_joint, elbow_joint],
    points: [{positions: [0.6, -0.4], time_from_start: {sec: 2}}]}"
```

Obserwuj jednocześnie: ramię w Gazebo, `tf2_echo base_link tool_tip` i
`scripts/dev/ros2/print-topic-messages.sh /joint_states`. Trzy widoki tego
samego zdarzenia — i to jest sens tej warstwy.

**Gotowe, gdy:** translacja z `tf2_echo` zmienia się przez ~2 sekundy i zatrzymuje
na nowej wartości, a `ros2 control list_controllers` dalej pokazuje `active`.

### Zadanie 08.5 — Chwyt przez odłączalne złącze, ciśnienie ze stanu świata (rdzeń)

**Cel:** `/vacuum_pressure` przestaje zależeć od parametru ustawionego ręką.

1. Wstaw do świata osobny model przedmiotu (pudełko), bo złącze łączy modele.
2. Dodaj czujnik kontaktu na `tool_tip` (`<gazebo reference="tool_tip">`)
   i upewnij się, że świat ładuje system kontaktu.
3. Dodaj system odłączalnego złącza z tematami spięcia, rozpięcia i stanu.
4. Zmostkuj potrzebne tematy mostem z etapu 07 — sprawdź `ros2 run ros_gz_bridge
   parameter_bridge --help` i listę obsługiwanych par typów, zamiast zgadywać.
5. Napisz węzeł `vacuum_sensor_sim` (nowy plik obok istniejącego, **nie** zamiast
   niego), który słucha kontaktu i stanu złącza i publikuje `Float32` na
   `vacuum_pressure` z tym samym szumem `gauss(0, 0.5)` i tą samą częstością 50 Hz.

Mapowanie stanów zostaw identyczne z oryginałem (`0.0` / `-20.0` / `-59.0`),
żeby `grasp_monitor.py` działał bez zmian. To jest cały test: jeśli werdykty
lecą tak samo, wymieniłeś źródło prawdy, nie kontrakt.

**Gotowe, gdy:** nagrywasz bagiem sekwencję „podjazd — chwyt — przeniesienie —
puszczenie", i na `/grasp_verdict` widać `sealed` dokładnie w tych chwilach,
w których w Gazebo przedmiot wisi na końcówce. Ani razu nie dotykasz
`set-param.sh`.

### Zadanie 08.6 — Zepsuj to: rozjedź zegary, potem wytnij statykę (rdzeń, obowiązkowe)

**Cel:** rozpoznać błąd czasu po komunikacie o ramkach.

**Wariant A.** Uruchom wszystko jak w 08.4, ale w `robot_state_publisher` ustaw
`use_sim_time` na `false`, zostawiając `true` w pozostałych węzłach. Odpal
konsumenta, który robi `lookup_transform` z konkretnym stemplem (może być twój
węzeł z zadania 08.7 albo `tf2_echo`). Przeczytaj komunikat.

Zanim zajrzysz wyżej do tabeli: odpowiedz sobie na głos, **dlaczego** dostałeś
akurat ten wariant ekstrapolacji, a nie drugi. Podpowiedź to rząd wielkości obu
liczb w komunikacie. Dopiero potem sprawdź.

**Wariant B.** Nagraj `/tf` i `/tf_static` razem z resztą, potem odtwórz nagranie
**bez** `/tf_static` (`ros2 bag play --topics ...` z pominięciem tego tematu)
i uruchom konsumenta. Zobacz, czego brakuje w drzewie i jak wygląda błąd.
Następnie odtwórz z `/tf_static`, ale uruchom konsumenta z dwudziestosekundowym
opóźnieniem. Zastanów się, dlaczego tym razem transformacje **są** — i co by się
stało, gdyby `/tf_static` nie miało `transient_local`.

**Gotowe, gdy:** umiesz z pamięci podać kolejność sprawdzania przy błędzie TF
(zegar → rząd wielkości stempli → nazwy) i wiesz, który wariant ekstrapolacji
odpowiada któremu rozjazdowi zegarów.

### Zadanie 08.7 — Cena opóźnienia w milimetrach (rozszerzenie)

**Cel:** wyrazić opóźnienie z etapu 02 w jednostce, która obchodzi mechanika.

Werdykt z `grasp_monitor.py` powstaje ze średniej z `deque(maxlen=25)` przy
50 Hz — czyli opisuje okno **0,48 sekundy wstecz**, a nie chwilę, w której go
wypublikowano. Do tego dochodzi opóźnienie potoku. W tym czasie chwytak jedzie.

Napisz węzeł, który dla każdego werdyktu liczy:

```python
p_pomiar  = buf.lookup_transform('base_link', 'tool_tip', Time.from_msg(stamp_pomiaru))
p_werdykt = buf.lookup_transform('base_link', 'tool_tip', Time.from_msg(stamp_werdyktu))
# dystans euklidesowy między translacjami, w milimetrach
```

`stamp_pomiaru` masz dzięki etapowi 02 — bez niego to zadanie jest niewykonalne
i to jest cała jego pointa. Powtórz pomiar dla trzech prędkości ruchu.

**Gotowe, gdy:** masz trzy liczby w milimetrach i umiesz powiedzieć, przy jakiej
prędkości ramienia werdykt przestaje opisywać miejsce, w którym faktycznie coś
się wydarzyło.

---

## Pułapki

| objaw | przyczyna | co zrobić |
|---|---|---|
| `robot_state_publisher` wstał, `/tf` ma tylko statyczne krawędzie | nikt nie publikuje `/joint_states` | odpal `joint_state_publisher` (rozwój) albo `joint_state_broadcaster` (symulacja) |
| model w rviz2 migocze albo skacze między pozami | dwa węzły publikują `/joint_states` naraz | wyłącz atrapę po wejściu `ros2_control` |
| URDF nie ładuje się z launcha, choć `xacro` z ręki działa | parametr `robot_description` bez wymuszonego typu | `ParameterValue(Command(['xacro ', ścieżka]), value_type=str)` |
| model odlatuje, drga albo wpada pod podłogę w pierwszej klatce | brak `<inertial>` albo inercja o kilka rzędów za mała | policz tensor z wymiarów bryły, sprawdź każdy link w rozwiniętym URDF |
| `revolute` bez `<limit>` — URDF w ogóle się nie parsuje | `effort` i `velocity` są wymagane dla `revolute` i `prismatic` | dopisz `<limit lower=... upper=... effort=... velocity=.../>` |
| `gz sim` startuje, ale nie ma `/controller_manager` | wtyczka `libgz_ros2_control-system.so` się nie załadowała | sprawdź, czy `ros-jazzy-gz-ros2-control` jest w `Containerfile` i czy kontener przebudowany |
| `ros2 control list_controllers`: nie można dosięgnąć usługi | model nie jest jeszcze wstawiony do świata — `controller_manager` żyje w procesie `gz sim` | najpierw `ros_gz_sim create`, potem spawnery |
| sterownik nie chce przejść w `active`, a `/rosout` milczy | log wtyczki leci na stdout Gazebo, nie do `/rosout` | czytaj terminal z `gz sim`; typowo konflikt zasobów albo zła nazwa przegubu w YAML |
| drugi sterownik na ten sam przegub nie startuje | interfejsy komendy są wyłączne | `ros2 control list_hardware_interfaces` — sprawdź, kto trzyma (`claimed`) |
| kontakt nigdy nie powstaje, złącze się nie spina | brak `<collision>`, brak systemu kontaktu w świecie albo zła nazwa kolizji po konwersji URDF→SDF | `gz sdf -p model.urdf` i porównaj nazwy z tym, co wpisałeś w czujniku |
| `static_transform_publisher` ostrzega o przestarzałej składni | argumenty pozycyjne są w Jazzy wycofane | użyj `--frame-id`, `--child-frame-id`, `--x/--y/--z`, `--roll/--pitch/--yaw` |
| po odtworzeniu baga transformacje statyczne znikają | `/tf_static` wysłane raz na początku, konsument dołączył później | odtwarzaj z `/tf_static`, a przy wątpliwościach sprawdź zapisane QoS w `metadata.yaml` i `ros2 bag play --qos-profile-overrides-path` |
| `gz sim` nie wstaje: „cannot open display" | kontener nie ma przekazanego ekranu | uruchom serwer bez GUI (`gz sim -s`) albo zrób zadanie o ekranie z [etapu 05](./05-introspekcja-qos-narzedzia.md) |

---

## Sprawdź się

1. Dlaczego `lookup_transform` z czasem zerowym („daj najnowszą") jest w tym
   projekcie błędem, mimo że usuwa wszystkie komunikaty o ekstrapolacji?
2. Publikujesz `/tf_static` w pętli 10 Hz. Wszystko działa. Co jest z tym nie tak
   i kiedy to wybuchnie?
3. `joint_state_broadcaster` jest `active`, `arm_controller` też, a ramię
   w rviz2 stoi. Gdzie szukasz — i dlaczego akurat tam?
4. Dostajesz „extrapolation into the past" z liczbami `42.7` i `1790000000.0`.
   Który węzeł ma zły `use_sim_time` — publikujący czy pytający? Skąd wiesz?
5. Dlaczego pomylenie centymetrów z metrami w URDF jest droższe niż ten sam
   błąd w kodzie serwisu HTTP?
6. Po co warstwa `ros2_control`, skoro w symulacji i tak mógłbyś ustawiać kąty
   przegubów wprost? Podaj odpowiedź, w której pada słowo „test".
7. Twój bag z etapu 03 nie ma `/tf`. Które pytania o awarię stają się przez to
   nieodpowiadalne — na zawsze, nie „do czasu dogrania"?
8. Dlaczego chwytany przedmiot musi być osobnym modelem, a nie linkiem ramienia?

---

## Co przeczytać

- **REP-103 i REP-105** (`https://www.ros.org/reps/`) — dwie strony, które
  ustalają, co znaczy `x` i co znaczy `base_link`; czytasz je raz i oszczędzasz
  sobie klasy błędów, których nikt nie zgłasza.
- **Dokumentacja tf2 dla Jazzy** (`https://docs.ros.org/en/jazzy/`) — po to,
  żeby raz na zawsze zapamiętać kolejność argumentów `lookup_transform`
  i różnicę między `canTransform` a złapaniem wyjątku.
- **`https://github.com/ros-controls/ros2_control`** — README i przykłady
  interfejsów sprzętowych; po to, żeby zobaczyć, jak mało kodu dzieli symulację
  od prawdziwego sterownika.
- **`https://github.com/ros-controls/gz_ros2_control`** — przykładowe modele
  i pliki YAML; najszybsza droga do działającej konfiguracji, gdy twoja nie wstaje.
- **Dokumentacja Gazebo Harmonic** (`https://gazebosim.org/docs/harmonic/`) —
  lista systemów wraz z parametrami SDF; sprawdzaj tu pisownię, zamiast kopiować
  przykłady dla Ignition, które wyglądają prawie tak samo.

---

## Dziennik

Wypełnij po skończeniu etapu, zanim przejdziesz dalej.

```
Data:

1. Ile razy dostałem błąd TF, zanim sprawdziłem zegary?


2. Co w URDF zajęło mi najwięcej czasu — i czy dowiedziałbym się tego
   z dokumentacji, czy tylko z awarii?


3. Które narzędzie pokazało mi coś, czego nie wiedziałem: view_frames,
   tf2_monitor czy ros2 control list_hardware_interfaces?


4. Ile milimetrów kosztowało opóźnienie przy najszybszym ruchu?


5. Jedno zdanie, którego nie umiałbym napisać tydzień temu:
```

Dalej → [Etap 09 — Latencja i tracing](./09-latencja-i-tracing.md)
