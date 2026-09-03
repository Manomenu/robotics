# ~/repos/robotics

## Maksyma

**Co skrypt tworzy poza repo, to `<nazwa>-revert.sh` musi cofnąć.**

Skrypt, który zmienia coś na maszynie — instaluje pakiet, tworzy kontener,
zapisuje plik w `$HOME` — ma bliźniaka z sufiksem `-revert.sh`, który
przywraca stan sprzed. Skrypt bez skutków ubocznych (`ros2-enter.sh`)
bliźniaka nie ma i to jest sygnał, że nic po sobie nie zostawia.

Konsekwencja: projekt nie dokłada się do `~/.dotfiles`. Wszystkie jego
zależności instalują się i odinstalowują skryptami z tego repo, bo tylko
wtedy usunięcie repo faktycznie kończy sprawę.

Reverty są idempotentne i mówią, czego nie ruszyły.

## Granice

- `~/scripts` — maszyna (przeżywa projekty). `repo/scripts` — projekt.
- Kontener `ros2` jest granicą czystości: ROS, apt i wszystkie
  nieprzewidziane zależności żyją w nim, nie na Fedorze.
- Katalog domowy jest z kontenerem **współdzielony**. Nic z kontenera nie
  pisze do `$HOME` — sourcing ROS-a idzie do `/etc/profile.d/ros2.sh`,
  czyli do systemu plików kontenera.

## Układ

    ws/src/            pakiety ROS — wszystko, co MUSI być pakietem
    projects/<nazwa>/  notatki, analiza offline, dane danego projektu
    scripts/           środowisko tego repo

Jeden colcon workspace na całe repo. Kolejny projekt to kolejny pakiet
w `ws/src/` plus katalog w `projects/`, nie nowe repo.
