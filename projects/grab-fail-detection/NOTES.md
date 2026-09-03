# grab-fail-detection

**Cel:** cela, która chwyta nieznane obiekty z pojemnika i sama orzeka,
czy jej się udało.

Budowane od strony werdyktu, nie od strony kamery — żeby każdy kolejny
element miał gdzie się wpiąć.

    kamera -> chmura punktów -> propozycja chwytu -> ruch
                                                      |
                        sygnały (ciśnienie, prądy, obraz po, masa)
                                                      |
                                    WERDYKT: sukces / chybienie /
                                    podwójny chwyt / zgubiony w drodze
                                                      |
                                          zapis (rosbag) -> analiza offline

## Dziennik

### 2026-09-03 — dzień 1
- [ ] obejrzane: Amazon Picking Challenge, Dex-Net, bin picking transparent
- [ ] kontener ros2 + Jazzy
- [ ] talker/listener obejrzane narzędziami (topic list/echo/hz, rqt_graph)
- [ ] pakiet grip_monitor: vacuum_sensor + grasp_monitor
- [ ] nagrane i odtworzone rosbagiem

Na czym utknąłem:
