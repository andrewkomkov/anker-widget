# anker-widget

Menu bar app and desktop widget for macOS. They show the charging power of each pad
of the Anker Prime Wireless Charging Station 3-in-1 (A25X7). The data comes over Bluetooth LE.
You do not need the Anker app or the Anker cloud.

<p>
  <img src="docs/widget-medium.png" height="180" alt="Средний виджет">
  <img src="docs/widget-small.png" height="180" alt="Малый виджет">
</p>

---

Мощность беспроводной зарядки Anker Prime Wireless Charging Station 3-in-1 (A25X7)
в строке меню и в виджете macOS. Зарядка даёт телефону до 25 Вт, ещё две площадки — для часов
и наушников. Данные идут по Bluetooth, без приложения Anker и облака.

## Как устроено

```
зарядка ──BLE──> daemon/ankerd.py ──JSON-строки──> AnkerBar.app ──state.json──> виджет
                 (SolixBLE)                        (строка меню)  (App Group)
```

- `daemon/ankerd.py` держит соединение через [SolixBLE](https://github.com/flip-dots/SolixBLE).
  Он использует класс `MagGo3in1`: у этой зарядки тот же протокол. Демон находит первое
  устройство Anker с сервисом `ff09`. Нужное устройство можно задать флагом `--name`.
  Демон печатает состояние при каждом изменении и раз в 15 с.
- `app/` — проект xcodegen. `AnkerBar` запускает демон и показывает мощность в строке меню.
  Он пишет состояние в `~/Library/Group Containers/<TEAM_ID>.com.andrewkomkov.ankerbar/state.json`
  и обновляет виджет. Сам виджет не работает с Bluetooth.
- Разрешение на Bluetooth система спрашивает у AnkerBar, потому что демон — его дочерний процесс.

## Протокол

- BLE-имя зарядки — её серийный номер. Сервис — `8c850001-0302-41c5-b46e-cf057c562025`.
- При рукопожатии зарядка присылает имя, версию прошивки, серийный номер и MAC.
  Номера модели в протоколе нет.
- Телеметрия приходит командой `4300` после подписки `4200`. Площадки передаются в TLV `a2`/`a3`/`a4`.
  Каждая занимает 8 байт little-endian:
  `04 <статус> <напряжение, 0,01 В> <ток, 0,01 А> <мощность, 0,01 Вт>`.
  Пример: 7,40 В × 0,30 А = 2,22 Вт (телефон), 5,00 В × 0,20 А = 1,00 Вт (часы).
- Площадки: 1 — наушники, 2 — телефон, 3 — часы. Зарядка передаёт только номер площадки,
  поэтому названия записаны в коде (`PadKind.forPad`).
- Если телефон заряжен на 100 %, зарядка подаёт около 1 Вт.

## Установка

Нужны macOS 15 или новее, Xcode, [xcodegen](https://github.com/yonaskolb/XcodeGen) и Python 3.11 или новее.

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python daemon/ankerd.py --once      # проверка: одна строка состояния

cd app
cp Local.xcconfig.example Local.xcconfig      # впишите свой Team ID
xcodegen generate
xcodebuild -project AnkerBar.xcodeproj -scheme AnkerBar -configuration Release \
  -derivedDataPath build build
cp -R build/Build/Products/Release/AnkerBar.app ~/Applications/
open ~/Applications/AnkerBar.app
```

Виджету нужна подпись с командой разработчика: App Group в песочнице работает только с ней.
Team ID — это поле OU сертификата Apple Development. Если в Xcode нет аккаунта, включите в
`Local.xcconfig` ручную подпись (пример есть в файле).

Приложение запускает демон из `.venv` этой папки. Путь записывается в Info.plist при сборке
(`AnkerProjectDir`), поэтому не перемещайте папку после сборки.

Виджет добавляется так: правый клик по рабочему столу → «Изменить виджеты» → «Anker Prime».

## Ограничения

- Виджет обновляется не чаще раза в минуту: это лимит WidgetKit. Если меняется статус площадки,
  виджет обновляется сразу. Живые цифры — в строке меню.
- Если AnkerBar не присылает данные больше 2 минут, виджет показывает их как устаревшие.
- Проверено на одной зарядке A25X7 с прошивкой v0.0.5.2.

## Проверка вида виджета

`tools/render_widget.swift` рисует виджет в PNG без установки:

```bash
swiftc -parse-as-library -o /tmp/render app/Shared/ChargerState.swift \
  app/AnkerWidget/WidgetViews.swift tools/render_widget.swift
/tmp/render .
```

## Лицензия

MIT. Протокол взят из [SolixBLE](https://github.com/flip-dots/SolixBLE) (MIT).
Anker — товарный знак Anker Innovations. Проект с Anker не связан.
