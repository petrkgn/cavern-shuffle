# Cavern Shuffle — Solitaire (Defold)

Проект пасьянса на движке **Defold** с тематикой "Dragon's Solitaire".

## Обзор проекта

Игра представляет собой карточный пасьянс с элементами RPG. Карты имеют игровые роли:
- **Adventurer** — стандартные карты (2-10, Туз)
- **Enemy** — Короли (Goblin Champion, Giant Spider, Ogre)
- **Obstacle** — Дамы (ловушки по мастям)
- **Item** — Валеты (зелья, сокровища)
- **Boss** — Король пик (Minotaur)

## Технологии

- **Движок:** Defold
- **Язык:** Lua
- **Ассеты:** Kenny's Playing Cards Pack (58x40px)

## Сборка и запуск

### Требования
- [Defold Editor](https://defold.com/download/)

### Запуск в редакторе
1. Откройте проект в Defold Editor
2. Нажмите **Project → Build** (или `Ctrl+B` / `Cmd+B`)
3. Для запуска нажмите **Project → Debug** (или `Ctrl+D` / `Cmd+D`)

### Сборка для платформ
```bash
# Через CLI Defold
bob --platform=html5 build
bob --platform=android build
bob --platform=windows build
```

### Конфигурация
Основные настройки в `game.project`:
- Разрешение: 1024×768
- High DPI: включён
- Режим масштабирования HTML5: stretch

## Структура проекта

```
├── game/
│   ├── scripts/          # Основные скрипты
│   │   ├── card.script           # Логика карты
│   │   ├── game.script           # Главный скрипт игры
│   │   ├── manager.script        # Менеджер сцены
│   │   └── *.gui_script          # GUI-скрипты (меню, UI, эндшпиль)
│   ├── modules/          # Бизнес-логика
│   │   ├── state.lua             # Состояние игры
│   │   ├── constants.lua         # Константы (размеры, масштаб)
│   │   ├── game_config.lua       # Конфигурация карт
│   │   ├── card_utils.lua        # Утилиты для карт
│   │   ├── pile.lua              # Структура стопки
│   │   ├── coords.lua            # Координаты
│   │   ├── geometry.lua          # Геометрия
│   │   └── systems/              # Игровые системы
│   │       ├── input_system.lua      # Обработка ввода
│   │       ├── render_system.lua     # Отрисовка
│   │       ├── drag_drop_system.lua  # Перетаскивание
│   │       ├── rules_system.lua      # Правила игры
│   │       ├── game_flow_system.lua  # Поток игры
│   │       └── tutorial_system.lua   # Подсказки
│   ├── objects/          # Factory-объекты
│   ├── gui/              # GUI-файлы
│   ├── particles/        # Частицы
│   ├── shaders/          # Шейдеры
│   └── render/           # Render-константы
├── main/                 # Коллекции Defold
│   ├── main.collection   # Главная коллекция
│   └── game.collection   # Игровая коллекция
├── assets/               # Ресурсы
│   ├── cards/            # Спрайты карт
│   ├── ui/               # UI-элементы
│   ├── effects/          # Эффекты
│   ├── fonts/            # Шрифты
│   └── sky/, lightning/  # Фоновые ассеты
└── input/                # Конфигурация ввода
```

## Архитектура

### Принцип разделения ответственности
```
ДАННЫЕ (state.lua) → ЛОГИКА (systems/) → ВИЗУАЛ (scripts/, gui/)
```

### State Management
Состояние хранится в `game/modules/state.lua`:
- `state.data.piles` — все стопки (explore, inventory, talon, discard, party, dungeon)
- `state.data.dragging` — активное перетаскивание
- `state.data.party_levels` — уровни отряда по мастям
- `state.data.party_power` — общая сила отряда
- `state.data.minotaur_pos` — позиция босса в подземелье
- `state.data.is_won`, `state.data.is_dealt` — флаги состояния игры

**Правило:** Логика меняет `state.lua` → рендер-система обновляет экран.

### Системы
- **InputSystem** — обработка касаний/кликов, конвертация координат
- **DragDropSystem** — логика перетаскивания карт
- **RenderSystem** — обновление спрайтов, анимации
- **RulesSystem** — проверка правил перемещения
- **GameFlowSystem** — поток игры (deal, win/lose, рестарт)
- **TutorialSystem** — подсказки для игрока

### Конфигурация карт
`game_config.lua` определяет:
- Типы карт (adventurer, enemy, obstacle, item, boss)
- Игровые роли (имена, сила, специальные свойства)
- Джокер с трансформацией из Short Rest

## Технические принципы

### Асинхронность
Для избежания "гонки состояний" использовать:
- `timer.delay()` — отложенные вызовы
- `msg.post()` — асинхронная отправка сообщений

### Одноразовые эффекты (VFX)
- Эффекты создаются через **Factory** динамически
- Объект эффекта проигрывает анимацию и самоуничтожается
- Пример: молнии, частицы (`magic_poof`)

### Адаптивный ввод
- Все координаты мыши конвертируются через `coords.lua`
- Поддержка полноэкранного режима и разных разрешений

## Разработка

### Добавление новых карт
1. Добавьте определение в `game_config.lua.CARD_DEFINITIONS`
2. Убедитесь, что спрайт существует в атласе карт

### Изменение баланса
- `constants.lua` — GLOBAL_SCALE (0.80), размеры карт
- `game_config.lua` — CARD_DEFINITIONS.power для силы врагов

### Журнал изменений

Все изменения логики, архитектуры и игровых механик **обязательно** записываются в `change.md` в корне проекта.

**Когда записывать:**
Запись в журнал производится **после того, как изменения закоммичены и запушены** в репозиторий.

**Команды для обновления:**
- «Обнови change.md по последнему коммиту»
- «Запиши последние изменения в change.md»

**Процесс:**
1. Анализирую последний коммит через `git diff HEAD~1 HEAD`
2. Беру сообщение коммита из `git log -n 1`
3. Анализирую изменённые файлы
4. Генерирую запись в `change.md` в формате ниже

**Формат записи:**
```
### YYYY-MM-DD — Краткое описание

**Файлы:**
- `путь/к/файлу.lua` — что изменено

**Причина:** зачем было сделано (из сообщения коммита)

**Результат:** что изменилось в поведении
```

**Зачем:**
- Возможность откатить изменения при неудачных экспериментах
- Понимание истории изменений логики
- Документирование причин принятых решений
- Сравнение разных реализаций при рефакторинге

### Стиль кода
- **Именование:** `snake_case` для переменных и функций
- **Модули:** Возвращают таблицу `M = {}`
- **Константы:** `UPPER_CASE` (в `constants.lua`)
- **Комментарии:** Минимальные, только для сложной логики
- Lua с явными модулями через `require()`
- Разделение на модули (данные) и системы (логика)
- Координаты через `vmath.vector3()`
- Комментарии на русском языке

### Структура скриптов Defold
```lua
-- 1. require() в начале
local State = require("game.modules.state")

-- 2. Константы
local FLIP_SPEED = 3.0

-- 3. Вспомогательные функции (local)
local function helper() end

-- 4. Функции жизненного цикла
function init(self) end
function update(self, dt) end
function on_message(self, message_id, message, sender) end
```

### Обработка сообщений
Использовать `hash()` для `message_id`:
```lua
if message_id == hash("set_sprite") then
    -- логика
end
```

## Известные решения проблем

### Эффект частиц при трансформации карты (magic_poof)

**Проблема:** При использовании карты "Short Rest" (Валет треф) эффект частиц не появлялся при трансформации в джокера.

**Причины:**
1. **Z-координата:** В Defold ось Z направлена от камеры. Меньший Z = ближе к камере = объект рендерится поверх других. Карты имеют Z=0.01-0.95, поэтому частицы нужно размещать на Z=0.2 (ближе к камере).
2. **Порядок операций:** В `execute_short_rest_chain` эффект вызывался до `redraw_pile`, что приводило к неправильным координатам.
3. **Двойной спавн:** При трансформации джокера эффект создавался дважды — в `restore_item_from_joker` и в `card.script` при анимации переворота.

**Решение:**
1. Использовать фиксированный Z=0.2 для частиц (в `spawn_magic_poof` и `card.script`)
2. Вызывать `spawn_magic_poof` после `RenderSystem.redraw_pile(target_slot)`
3. Передавать `spawn_poof=false` в сообщении `transform_from` для предотвращения двойного спавна
4. Использовать позицию стопки (`pile_pos`) вместо позиции GO карты для надёжности

**Файлы:**
- `game/modules/systems/game_flow_system.lua` — `spawn_magic_poof()`, `execute_short_rest_chain()`, `restore_item_from_joker()`
- `game/scripts/card.script` — обработка `transform_from`, флаг `spawn_poof_on_flip`
- `game/scripts/one_shot_particle.script` — автоматическое удаление GO после завершения частиц

---

## Примечания

- Ассеты карт не включены в репозиторий
- Требуется атлас с картами 58x40px и naming: `card_<suit>_face.png`
- Для сборки могут потребоваться manifest-файлы для нативных расширений

## Ресурсы

- **Defold Docs:** https://defold.com/llms-full.txt, https://defold.com/llms-apis.txt
- **Kenny Assets:** Playing cards pack
