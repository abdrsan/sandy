# sandy-agent: события Claude Code и Codex

`Sandy.app/Contents/Helpers/sandy-agent` — нативный хелпер (Swift, без
зависимостей), через который вкладка «Агенты» узнаёт о сессиях. Код:
`Sources/AgentBridgeCore` (разбор, тестируется) и `Sources/SandyAgentBridge`
(командная строка). Интерфейс описан в [agent-monitor.md](agent-monitor.md).

Хелпер **только наблюдает**. Он не запускает агентов, не обращается к моделям и
сети, не отвечает на запросы разрешений и не меняет настройки агентов сам —
только по команде установки hooks.

## Команды

| Команда | Что делает |
|---|---|
| `sandy-agent monitor --claude --codex` | Долгоживущий процесс. События JSONL — в stdout, диагностика — только в stderr. Выходит с кодом 0 по SIGTERM, SIGINT, SIGHUP, при закрытии stdout и если родитель (Sandy) исчез. |
| `sandy-agent claude-hook` | Вызывается Claude Code. Читает payload из stdin, оставляет из него разрешённые поля и дописывает одну строку в почтовый ящик. Ничего не печатает в stdout, всегда выходит с 0, не блокирует Claude (≈5 мс; через 3 с выходит сам, если stdin не закрыт). |
| `sandy-agent install-claude-hooks` | Добавляет hooks Sandy в настройки Claude Code. |
| `sandy-agent uninstall-claude-hooks` | Убирает только записи Sandy. |

Дополнительные ключи (для отладки и тестов): `monitor --codex-home PATH
--spool-dir PATH --replay-window SEC --poll-interval SEC`; `claude-hook
--spool-dir PATH`; `install-claude-hooks --settings PATH --hook-executable PATH
--dry-run`; `uninstall-claude-hooks --settings PATH --dry-run`. Переменные:
`CODEX_HOME`, `CLAUDE_CONFIG_DIR`, `SANDY_AGENT_SPOOL_DIR`,
`SANDY_AGENT_DEBUG=1` (причины отказа хука — в stderr).

## Формат события

Одна строка — один JSON-объект. Поля, значение которых неизвестно, отсутствуют.

```json
{"schema_version":1,"event_id":"codex:01a1740b-5fef-7ea1-bd04-6bc71f85b051:42","source":"codex","session_id":"01a1740b-5fef-7ea1-bd04-6bc71f85b051","timestamp":"2026-10-25T18:00:00.000Z","kind":"working","project_path":"/Users/me/project","operation":"Запуск команды","tool":"exec_command"}
```

| Поле | Значение |
|---|---|
| `kind` | `session_started`, `working`, `waiting`, `turn_completed`, `session_ended`, `failed`, `usage`, `disconnected` |
| `operation` | Короткое название действия по имени инструмента (по-русски; Sandy переводит при показе). Аргументов нет никогда. Неизвестный инструмент — его очищенное имя. |
| `tool` | Имя инструмента, как его называет агент. Дополнительное поле. |
| `error` | Только у `failed`: код вида `rate_limit`, без текста ошибки. Дополнительное поле. |
| `usage` | Накопленные токены **всей сессии**: `input_tokens` (включая кэш), `output_tokens`, `cached_input_tokens`. Не приращение. |

`event_id` выводится из источника, а не из времени запуска хелпера: строка
rollout-а Codex — по её `ordinal`, событие хука Claude — идентификатором,
записанным хуком один раз. Поэтому после переподключения те же события
приходят с теми же ID и отсекаются.

**Начальный снимок.** При запуске хелпер молча прочитывает историю за последние
12 часов и выдаёт по каждой незакрытой сессии только `session_started`,
последнее состояние и последний `usage` — с исходными ID и исходным временем.
Закрытые и потерянные сессии в снимок не попадают. Дальше — живые события.
Подряд одинаковые `working`/`waiting` и неизменившийся `usage` не повторяются.

Примеры:

```json
{"event_id":"claude:4f1c…:1792952371855:SessionStart:c6de1c9c-f5d","kind":"session_started","project_path":"/Users/me/app","schema_version":1,"session_id":"4f1c…","source":"claude","timestamp":"2026-10-25T18:19:31.856Z"}
{"event_id":"claude:4f1c…:1792952373874:PermissionRequest:1bc925df-293","kind":"waiting","operation":"Запуск команды","project_path":"/Users/me/app","schema_version":1,"session_id":"4f1c…","source":"claude","timestamp":"2026-10-25T18:19:33.875Z","tool":"Bash"}
{"event_id":"claude:4f1c…:usage:183402:2210","kind":"usage","project_path":"/Users/me/app","schema_version":1,"session_id":"4f1c…","source":"claude","timestamp":"2026-10-25T18:20:02.114Z","usage":{"cached_input_tokens":160000,"input_tokens":183402,"output_tokens":2210}}
{"error":"rate_limit","event_id":"claude:4f1c…:1792952410002:StopFailure:9a0b…","kind":"failed","project_path":"/Users/me/app","schema_version":1,"session_id":"4f1c…","source":"claude","timestamp":"2026-10-25T18:20:10.002Z"}
{"event_id":"codex:01a1740b-…:57","kind":"turn_completed","project_path":"/Users/me/project","schema_version":1,"session_id":"01a1740b-…","source":"codex","timestamp":"2026-10-25T18:21:00.120Z"}
{"event_id":"codex:01a1740b-…:disconnected:812331","kind":"disconnected","project_path":"/Users/me/project","schema_version":1,"session_id":"01a1740b-…","source":"codex","timestamp":"2026-10-25T18:30:00.000Z"}
```

## Claude Code

**Источник — документированные hooks** (<https://code.claude.com/docs/en/hooks>).
Нужен Claude Code 2.1.78 или новее (тогда появился `StopFailure`); на этой
машине проверялась установка в `settings.json` для 2.1.144, живых сессий Claude
здесь не было — сквозной прогон с настоящим Claude Code не выполнялся.

Hooks пишутся в `~/.claude/settings.json` (или `$CLAUDE_CONFIG_DIR/settings.json`,
если переменная видна процессу, который запускает установку; у приложения из
Finder её обычно нет). Hooks из настроек пользователя срабатывают во всех
местах, где Claude Code работает локально: терминал, IDE, Code во вкладке
Claude Desktop. Облачные сессии `~/.claude` не читают и не видны.

| Hook | Событие |
|---|---|
| `SessionStart` (кроме `source: compact`) | `session_started` |
| `UserPromptSubmit`, `PostToolUse`, `PostToolUseFailure` | `working` |
| `PreToolUse` | `working` + `operation` по инструменту |
| `PreCompact` | `working`, «Сжатие контекста» |
| `PermissionRequest`; `Notification` с `permission_prompt`, `elicitation_dialog`, `elicitation_url_dialog`, `agent_needs_input` | `waiting` |
| `Notification` `idle_prompt`, если последнее состояние — `working` | `waiting` (вывод: Stop не приходит после прерывания) |
| `Stop` | `turn_completed` |
| `StopFailure` | `failed` + код ошибки |
| `SessionEnd` | `session_ended` |

Ошибка инструмента (`PostToolUseFailure`) — не ошибка хода.

**Как событие доходит до монитора.** Хук дописывает строку в
`~/Library/Application Support/Sandy/AgentBridge/claude/<session_id>.jsonl`
(каталог `0700`, файлы `0600`, `O_NOFOLLOW`; файл больше 1 МиБ заменяется одной
новой строкой). Монитор опрашивает каталог раз в секунду. Сокета нет: если Sandy
не запущен, хуку некуда «стучаться» и нечего ждать, а запущенный позже монитор
поднимет текущее состояние из ящика. Файлы старше 7 дней монитор удаляет.

В строке ящика только: ID события, время, имя hook-а, `session_id`, `cwd`, имя
инструмента, тип уведомления, код ошибки из фиксированного списка, `source` /
`reason`, признак субагента, путь к журналу сессии и pid с временем запуска
процесса Claude. **Не сохраняются**: промпт, `tool_input`, `tool_response`,
`last_assistant_message`, текст уведомления, `error_details`.

**Usage.** Hooks токенов не сообщают. Монитор читает журнал сессии
(`transcript_path`) инкрементально и берёт из строк `"type":"assistant"` только
`message.id` и числа из `message.usage`; одно сообщение, записанное несколькими
строками, учитывается один раз. Формат журнала — внутренний, Anthropic его как
API не документирует: если он изменится, usage пропадёт (поле будет
отсутствовать), а состояния продолжат работать. Журналы субагентов в отдельных
файлах не учитываются. Проверено только на фикстурах.

**Пропавший процесс.** Хук запоминает pid и время запуска процесса Claude Code.
Если процесс исчез без `SessionEnd` (упал, убит), монитор выдаёт
`disconnected` — не `session_ended`.

### Установка и удаление hooks

- Запускается только кнопкой в настройках Sandy (или вручную). Сам хелпер и
  приложение настройки не трогают.
- Перед записью рядом кладётся `settings.json.sandy-backup-<время>` (`0600`).
- JSON разбирается целиком; нечитаемый файл, не-объект или `hooks` не того
  типа — отказ без записи.
- Чужие hooks и все прочие ключи сохраняются; повторная установка ничего не
  меняет; установка из другого места заменяет прежнюю запись Sandy.
- Записи Sandy узнаются по команде: путь, оканчивающийся на `sandy-agent`, и
  аргумент `claude-hook`. Команда:
  `[ ! -x '<путь>' ] || '<путь>' claude-hook` — если приложение удалили, не
  сняв hooks, Claude не показывает ошибку хука на каждом событии.
- Файл переписывается с отсортированными ключами (`JSONSerialization` порядок
  не хранит); содержимое то же.
- Симлинк `settings.json` (dotfiles) пишется в цель.

## Codex

**Проверено:** Codex Desktop (`ChatGPT.app`, bundle id `com.openai.codex`,
версия 26.1016.62342) со встроенным CLI 0.163.0-alpha.11.2; отдельного `codex`
в `PATH` на этой машине нет. Формат сверялся по 110 локальным rollout-ам версий
0.154–0.163 и по исходникам `codex-rs/rollout/src/policy.rs`. Платных запросов
и новых задач для проверки не запускалось.

**Почему журналы, а не API.** У Codex есть `app-server` (JSON-RPC), но он
сообщает только о нитях, которые ведёт сам; Desktop поднимает свой app-server
на stdio, и чужой клиент к нему не подключится. Есть и hooks Codex (флаг
`hooks` — stable), но они потребовали бы менять `~/.codex`, чего контракт не
предусматривает. Остаются rollout-файлы
`$CODEX_HOME/sessions/YYYY/MM/DD/rollout-*.jsonl`, которые ядро Codex пишет для
каждой локальной нити.

**Какие сессии видны.** Нити Codex Desktop (подтверждено). CLI (`codex`,
`codex exec`) и расширение IDE пишут тот же формат тем же ядром — ожидается,
что они видны так же, но на этой машине не проверено. Служебные нити
(guardian, субагенты: `source.subagent`, `thread_source` `guardian_review` /
`subagent`) пропускаются. Облачные задачи Codex не видны.

| Строка rollout-а | Событие |
|---|---|
| `session_meta` (первая строка) | `session_started`, `project_path` = `cwd` |
| `turn_context` | обновляет `project_path` |
| `event_msg` `task_started` | `working` |
| `response_item` `function_call` / `custom_tool_call` / `local_shell_call` / `web_search_call` | `working` + `operation` по имени инструмента |
| `function_call` `request_user_input` (блокирующий) | `waiting` |
| `event_msg` `task_complete` | `turn_completed` |
| `event_msg` `turn_aborted` с `reason: interrupted` | `waiting`, «Ход прерван» |
| `event_msg` `token_count` → `info.total_token_usage` | `usage` |
| файл исчез (архив, удаление) | `disconnected` |

**Чего Codex в журнал не пишет** (по `policy.rs`), и потому Sandy этого не
видит: запросы подтверждений (`ExecApprovalRequest`, `ApplyPatchApprovalRequest`,
`RequestUserInput`), ошибки (`Error`, `StreamError`), завершение процесса.
Отсюда:

- **`waiting` при запросе разрешения у Codex не приходит.** Сессия, ждущая
  подтверждения команды, выглядит как `working`.
- **`failed` у Codex на практике не приходит.** Ветка для `event_msg` `error`
  есть на случай, если Codex начнёт её сохранять; в реальных журналах её нет.
- **`session_ended` у Codex не бывает.** Закрытие окна или выход из CLI в
  журнал не попадают; тишина файла ничего не означает и ни во что не
  превращается.
- `request_user_input_async` не считается ожиданием: ответ инструмента
  приходит сразу.

**Чтение.** Полный обход дерева `sessions` — при запуске и раз в 10 опросов;
между ними — каталоги за сегодня и вчера и файлы, менявшиеся последний час.
Чтение инкрементальное, не больше 4 МиБ за порцию и 4 порций на файл за опрос.
Незавершённая последняя строка ждёт перевода строки. Строки длиннее 1 МиБ (в
журналах встречаются до 14 МиБ — вывод команд) в память целиком не попадают:
тип записи берётся из их начала. Усечение файла, замена (другой inode) или
перезапись начала обнаруживаются, файл читается заново, повторы отсекаются по
ID. Для начального снимка читается только хвост файла (512 КиБ) и первая строка.
Старые нити, продолженные в Desktop, замечаются при дописывании в их файл.

Из rollout-а читаются только типы записей, `cwd`, имена инструментов и числа
токенов. Тексты сообщений, рассуждения, аргументы и вывод команд не
извлекаются; хелпер ничего из журналов не сохраняет.

## Ресурсы

Измерено на этой машине (110 rollout-ов, сборка release): монитор ≈0,2 с CPU за
минуту простоя (≈0,3 %), 37–42 МБ RSS. Хук — ≈5 мс на вызов.

## Проверка

```sh
./Scripts/test.sh --filter AgentBridgeCoreTests   # фикстуры: обезличены, во временных папках
./Scripts/bundle.sh release                        # кладёт и подписывает Contents/Helpers/sandy-agent
build/Sandy.app/Contents/Helpers/sandy-agent --version
```

Тесты покрывают: параллельные сессии и их проекты, повторную доставку, частичную
строку, перезапуск монитора (тот же снимок с теми же ID), усечение файла,
огромные и битые строки, накопительный usage (Codex и журнал Claude), ошибку
(`StopFailure`), завершение ответа без закрытия сессии, пропавший процесс и файл,
установку/удаление hooks (резервная копия, чужие hooks, идемпотентность,
нечитаемые настройки, кавычки в пути, запуск команды через `sh -c`), отказ писать
через симлинк и отсутствие промптов и аргументов в выводе.
