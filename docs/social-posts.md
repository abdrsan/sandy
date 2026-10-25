# Тексты для Threads и LinkedIn

Перед публикацией замените `ССЫЛКА_НА_РЕПОЗИТОРИЙ` настоящим публичным адресом.
Удалённый репозиторий в рабочей копии пока не настроен, поэтому адрес не выдуман.
Если прикрепляете демо, используйте запись своей текущей сборки без личных путей,
календарей, буфера и секретов. Тексты подготовлены; публикация не выполнялась.

## Threads — один пост

```text
Развиваю Sandy — нативную панель для Mac на основе open-source Cyclop.

Музыка, файлы, буфер обмена, заметки и мониторинг локальных Claude Code/Codex — у верхнего края экрана. Вызов: ⌃⌥Пробел. Интерфейс на 8 языках, включая казахский и японский.

В README расписал установку из исходников. Мобильные уведомления и подтверждения — следующий этап.

Код: ССЫЛКА_НА_РЕПОЗИТОРИЙ
```

## Threads — серия из пяти сообщений

### 1/5

```text
Показываю Sandy — мой pet project для macOS на основе MIT-проекта Cyclop.

Идея: собрать небольшие ежедневные инструменты у выреза MacBook. Навёл курсор или нажал ⌃⌥Пробел — открыл панель. На мониторе без выреза тоже работает.

Код и инструкция: ССЫЛКА_НА_РЕПОЗИТОРИЙ
```

### 2/5

```text
Внутри: управление музыкой, полка файлов, история буфера, текстовые заготовки, заметки, календарь, валюты и телесуфлёр для записи демо.

Интерфейс на 8 языках: EN, RU, KZ, DE, FR, ES, 中文, 日本語. Переключение прямо в настройках. Языковая пара переводчика настраивается отдельно.
```

### 3/5

```text
Для работы с AI добавил мониторинг локальных Claude Code и Codex: сессии, последняя операция, доступная статистика и уведомления на Mac.

Промпты, ответы и сырой вывод команд в историю Sandy не сохраняются. Это наблюдение за событиями, без выполнения команд и автоапрува. Полнота зависит от журналов агента.
```

### 4/5

```text
Установка сейчас из исходников: macOS 15+, Swift 6, Python 3.

В папке проекта:
./Scripts/bundle.sh

Затем Sandy.app из build → Программы. В README есть настройка языка, клавиш, агентов и разрешений.

Изучаю следующий этап: уведомления на iPhone/Android и подтверждения конкретных действий с телефона.
```

### 5/5

```text
За основу благодарю автора Cyclop. Sandy развиваю как отдельный проект с сохранением MIT-лицензии и авторства исходного кода.

Для мобильного доступа изучил Coucou: планирую шифрование, отзыв устройств и подтверждения с ограниченным сроком. В текущей сборке телефона ещё нет.

Буду рад отзывам: какая функция нужна вам чаще всего?
```

## LinkedIn — русский

```text
Развиваю Sandy — pet project для macOS: небольшую рабочую панель у верхнего края экрана.

Во время работы часто нужны простые вещи: вернуть скопированный текст, временно отложить файл, записать мысль или проверить, закончил ли AI-агент задачу. Мне захотелось собрать эти действия в одном месте, которое открывается наведением на вырез MacBook или сочетанием Control + Option + Space.

Проект основан на Cyclop, опубликованном под MIT. В Sandy я развиваю адаптацию, локализацию и интеграцию локальных агентов, сохраняя авторство использованного кода.

Что доступно сейчас:
• музыка, полка файлов и история буфера;
• заготовки текста, заметки и календарь;
• конвертер валют, локальный перевод и телесуфлёр;
• мониторинг поддерживаемых локальных Claude Code/Codex: сессии, последняя операция, статистика и уведомления на Mac;
• восемь языков интерфейса, включая казахский, китайский и японский;
• глобальное сочетание клавиш, настройка вкладок и нескольких экранов.

Стек: Swift, SwiftUI, AppKit и Swift Package Manager. Отдельный локальный хелпер приводит события агентов к общему формату. В историю мониторинга не сохраняются промпты, ответы и сырой вывод команд. Ограничения источников описаны в документации: текущий монитор не записывает абсолютно всё и не подтверждает действия за пользователя.

Сейчас Sandy устанавливается из исходников. В README подготовил пошаговую настройку для Mac: инструменты, сборка, язык, горячие клавиши, подключение агентов и разрешения macOS.

Следующий этап, который изучаю на примере Coucou: наблюдение за долгими задачами и уведомления на iPhone/Android, экран блокировки и Dynamic Island на iPhone, подтверждение конкретного действия с телефона. Для доступа из разных сетей отдельно прорабатываю шифрование, отзыв устройств и защиту от повторного применения решения. Эти мобильные возможности пока не входят в сборку.

Код и инструкция: ССЫЛКА_НА_РЕПОЗИТОРИЙ
Основа проекта: https://github.com/akalikbergenov/cyclop

Буду рад обратной связи по интерфейсу, установке и сценариям работы с агентами.

#macOS #Swift #SwiftUI #OpenSource #PetProject
```

## LinkedIn — English

```text
I'm developing Sandy, a macOS pet project that puts a small workspace at the top of the screen.

It brings together everyday tools: music controls, a file shelf, clipboard history, text snippets, notes, calendar, currency conversion and a teleprompter for recording demos. Open it by hovering over the MacBook notch or pressing Control + Option + Space. Displays without a notch work too.

Sandy is based on Cyclop, an MIT-licensed project. My work develops the Sandy adaptation, localization and local agent integration while preserving attribution to the original source.

The interface supports eight languages, including Kazakh, Simplified Chinese and Japanese. Translation languages are configured separately, subject to macOS language-pack support.

For AI workflows, Sandy monitors supported local Claude Code and Codex sessions: state, latest operation, available usage statistics and optional Mac notifications. Monitoring is passive. It does not execute requests or approve actions, and its history omits prompts, replies and raw command output. Event coverage depends on the source.

Built with Swift, SwiftUI, AppKit and Swift Package Manager. Installation is currently from source, with a step-by-step Mac setup guide in the README.

I'm researching the next stage using Coucou as a reference: iPhone/Android notifications, long-task monitoring, iPhone Lock Screen and Dynamic Island support, and explicit approval of individual actions. Cross-network access needs encryption, revocable pairing and replay protection. These mobile features are not implemented in the current build.

Repository and setup: ССЫЛКА_НА_РЕПОЗИТОРИЙ
Original project: https://github.com/akalikbergenov/cyclop

Feedback on the interface, setup and agent workflows is welcome.

#macOS #Swift #SwiftUI #OpenSource #BuildInPublic
```

## Что показать в коротком демо

1. Вызов панели горячими клавишами и смену языка.
2. Перетаскивание тестового файла на полку и копирование заготовки.
3. Реальную локальную сессию агента, если она подключена; иначе пропустите кадр.
4. Последний кадр — ссылка на репозиторий и строка «macOS 15+ · сборка из исходников».

Не показывайте мобильный макет как работающий продукт. Для отдельного анонса
мобильного доступа сначала нужна проверенная доставка на настоящем телефоне.
