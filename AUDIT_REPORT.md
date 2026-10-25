# Sandy 0.1.0 — audit report

Date: 2026-10-25. Machine: macOS 26.6.2 (arm64), Command Line Tools, Swift 6.3.3.
Scope: the working tree as it stood during the audit. It is **uncommitted** and
another agent was editing it at the same time (localizations, READMEs in new
languages, the Agents UI). Anything that changed after the commands in §4 ran
is not covered by this report.

## 1. Executive summary

The code base is small, dependency-free and careful: persistence goes through
atomic writes, three of the four stores refuse to overwrite a file they cannot
read, network access is limited to two documented https endpoints, external
processes are launched without a shell and with fixed arguments, and clipboard
history stays in memory only.

Two release blockers existed at the start of the audit, and both are fixed:

- the `sandy-agent` helper that the Agents tab depends on did not exist, and the
  package did not build;
- `THIRD_PARTY_NOTICES.md` had been deleted, which broke `bundle.sh`, CI and MIT
  attribution.

I also fixed one data-loss bug (`notes.json`) and a few P2 issues.

The automated checks now pass: 95 tests, bundle, DMG, media helper and signature
verification. I did not do the GUI part of the release checklist by hand, and I
did not run a real Claude Code session end to end. The build is ad-hoc signed,
and Gatekeeper rejects it on other Macs. Verdict: **INCONCLUSIVE** (§6).

## 2. Audit results

### P0 — release blockers (both fixed)

**P0-1. Agent helper missing; package did not build.**
- Where: `Package.swift`, `Sources/SandyAgentBridge`, `Scripts/bundle.sh`.
- What: the UI (`AgentBridgeClient`) launches
  `Contents/Helpers/sandy-agent`, but there was no such target or file. With the
  half-added targets, `swift build` failed with
  `invalid custom path 'Tests/AgentBridgeCoreTests'`.
- Impact: nothing built. Once building, Agents would show only "helper missing".
- Fix: implemented the helper (`AgentBridgeCore` + `SandyAgentBridge`,
  documented in `docs/agent-bridge.md`). `bundle.sh` now installs it with mode
  0755 and signs it before the bundle (hardened runtime with a real identity, no
  entitlements).

**P0-2. `THIRD_PARTY_NOTICES.md` deleted (uncommitted) in the working tree.**
- Where: `Scripts/bundle.sh`, CI step "Проверить, что в бандле лежит то, что нужно".
- What: `bundle.sh` copies the file under `set -e`, so the bundle failed. CI
  compares the file. README files link to it. `CONTRIBUTING.md` requires it.
  The Cyclop MIT attribution lives only there.
- Fix: restored it byte-for-byte from `HEAD`.
- Attention: the deletion was made by someone else and its intent is unknown.
  Restoring it destroys no data. If the deletion was intended, the attribution
  has to move somewhere else first.

### P1 — serious defects

**P1-1. Corrupt `notes.json` was silently replaced by an empty list (fixed).**
- Where: `Sources/Sandy/Services/NoteStore.swift`, `load()` and `persist()`.
- What: a decode failure read as "no notes", and the next keystroke wrote `[]`
  over the file. Snippets and config already guarded against this; notes did not.
- Fix: the unreadable file is moved aside as `notes.unreadable-<epoch>.json`.
  If it cannot be moved, writes are refused.
- Evidence: `Tests/SandyTests/NoteStoreTests.swift`.

No other P1 issues were confirmed.

### P2 — moderate

| # | Finding | Status |
|---|---|---|
| P2-1 | `AgentMonitorStore.checkpoint` rewrote the whole `history.json` (up to 2,000 sessions) every 20 s while monitoring, even with nothing working. | **Fixed.** Writes only when an observed working interval is open. |
| P2-2 | CI did not check that the helper is in the bundle. A missing helper would have shipped green. | **Fixed.** `build.yml` now runs `test -x`, `codesign --verify` and `--version`. |
| P2-3 | `SECURITY.md` said "screenshots" are saved to `~/Pictures/Sandy`. In fact every PNG/TIFF on the pasteboard is saved, e.g. an image copied in a browser (`ClipboardStore.poll`). The feature is on by default (`saveClipboardImages = true`). | **Doc fixed.** The default needs a product decision (see §5). README files still say "Clipboard screenshots". |
| P2-4 | Codex records no approval requests, errors or exits in its rollout logs (`codex-rs/rollout/src/policy.rs`). Codex sessions therefore never show `waiting` for an approval, `failed` or `session_ended`; a session waiting for approval looks `working`. | **Documented limitation.** No reliable source exists; nothing is inferred from silence. |
| P2-5 | A Claude hook left behind after Sandy.app was deleted would print a hook error on every Claude event. | **Fixed.** The command is `[ ! -x '<path>' ] \|\| '<path>' claude-hook` (tested through `sh -c`). |
| P2-6 | Idle helper used about 1 % CPU (full scan of `~/.codex/sessions` every second). | **Fixed.** Now about 0.3 %: full scan every 10 polls, otherwise today/yesterday folders and files touched in the last hour. Measured. |
| P2-7 | Now Playing loads a private framework through `/usr/bin/perl`. | Known and documented. It can break with any macOS update; `test-helper.sh` passes on 26.6.2. |
| P2-8 | During the audit every README linked to `README.zh-Hans.md` before it existed. | Resolved by the parallel work: the file now exists. Recheck links before release. |
| P2-9 | When "Install Claude Hooks" runs from the app, `CLAUDE_CONFIG_DIR` from a shell is not visible to a Finder-launched app. Hooks then go to `~/.claude/settings.json`. | Documented. |

### P3 — minor (not fixed)

- `PlayerBridge.artwork`: Spotify artwork download has no size cap. https only;
  the URL comes from Spotify's scripting dictionary.
- `ShelfStore.copy` reads a whole image synchronously on the main thread.
- `TeleprompterStore`: a non-UTF-8 `teleprompter.txt` loads as empty and is
  overwritten on the next edit. Sandy itself only ever writes UTF-8.
- The app discards the helper's stderr, so the backup path printed by
  install/uninstall is never shown. The file sits next to `settings.json`.
- `AgentSessionLedger` turns a replayed `working` event older than 120 s into
  `disconnected`. After Sandy restarts, a long-running tool call shows
  "disconnected" until the next event. Conservative, not wrong.
- The local `.build` once failed to link with `Undefined symbol
  AgentMonitorPreferences.init()`. A clean build passed, and later incremental
  builds passed too. Stale objects, not a code defect.
- A bug in the new helper code: event timestamps were truncated (`.122` instead
  of `.123`). Found by a test and fixed before release.

### Checked and found sound

- **Process execution.** All launches use `Process` with fixed executables and
  argument arrays: the agent helper, `/usr/bin/perl` with the dylib path as
  `$ARGV[0]`. AppleScript bodies use constant bundle ids and integers only.
- **Helper hook path.** It never writes to stdout. It always exits 0 (also on
  garbage input, no stdin, or a 40 MB payload). The payload is reduced to an
  allowlist; prompt, `tool_input` and responses are dropped (tested). Spool
  files are written with `O_NOFOLLOW` (tested against a symlink), mode 0600 in a
  0700 directory, and rotated at 1 MiB.
- **Settings installer.** Backs up before writing. Refuses unreadable or
  wrongly-typed JSON. Keeps foreign hooks and other keys (including `env`).
  Idempotent. Uninstall removes only Sandy entries. Never run on the real
  `~/.claude`.
- **Agent history.** Bounded (30 days, 2,000 sessions, 5,000 IDs), mode 0600,
  not overwritten when corrupt. Notification text contains only the event type
  and the source.
- **Clipboard.** Concealed, Transient and AutoGenerated types are excluded
  before any read. History is in memory and capped at 40 items.
- **Network.** Only currency rates (two hosts, ephemeral session, no cache) and
  Spotify artwork. The helper makes no network access.
- **Keyboard lock.** Releases automatically after 60 s. Refuses or ends when
  secure input is active. The tap is torn down on release; no second tap.
- **Repository.** No secrets, keys or local paths in tracked files. `build/` and
  `.build/` are ignored.

## 3. Changes made

| File | Why |
|---|---|
| `Sources/AgentBridgeCore/*` (new) | Helper core: event model, bounded JSONL tail reader, Codex rollout adapter and monitor, Claude hook record, spool, transcript usage, monitor, settings installer, process identity. |
| `Sources/SandyAgentBridge/main.swift` (new) | CLI: `monitor`, `claude-hook`, `install-claude-hooks`, `uninstall-claude-hooks`. Single thread; kqueue for signals. |
| `Tests/AgentBridgeCoreTests/*` (new) | 36 tests on anonymized fixtures. |
| `Package.swift` | New library, executable product `sandy-agent`, test target. |
| `Scripts/bundle.sh` | Install and sign `Contents/Helpers/sandy-agent`. |
| `.github/workflows/build.yml` | Verify the helper inside the bundle. |
| `THIRD_PARTY_NOTICES.md` | Restored from `HEAD` (P0-2). |
| `Sources/Sandy/Services/NoteStore.swift`, `Tests/SandyTests/NoteStoreTests.swift` (new) | P1-1. |
| `Sources/Sandy/Services/AgentMonitorStore.swift` | P2-1, a 3-line guard. |
| `SECURITY.md` | P2-3 wording; what the helper reads and stores. |
| `docs/agent-bridge.md` (new), `docs/release-checklist.md` | Helper contract and limits; manual checks for Agents. |

Post-audit fixes (user-reported, verified after the report above was written):

| File | Why |
|---|---|
| `Sources/Sandy/UI/SnippetsPane.swift` | Focus race when opening the add-snippet editor: the search field it replaces could be holding the caret, and SwiftUI's cleanup for a dying focused view could land after the plain `.onAppear` set and clear it — an editor on screen that accepts no typing. The request is now deferred one run-loop pass, the same workaround the notes editor already uses and documents. The search row's own `.onAppear` got the same defer for the return trip. |
| `Sources/Sandy/UI/CurrencyPane.swift` | Same dying-focused-field race when the currency picker replaces the amount field and back: deferred focus sets on picker open, picker close, and picker `onAppear`. |
| `Sources/Sandy/UI/TeleprompterPane.swift` | Same class: the ✎ edit path sets `editing` and `wantsKeyboard` in one pass while the editor mounts and the panel is still taking key status — the focus request is now deferred like the empty-script path already was. |
| `Sources/Sandy/Services/ClipboardStore.swift` | A pasteboard item carrying both an image and a string kept only the image; the text was dropped. Text is now recorded alongside the image (and in the delayed-arrival path). |

Nothing was committed, pushed or tagged. The real `~/.claude` and `~/.codex`
were only read, never written.

## 4. Verification (commands actually run)

| Command | Result |
|---|---|
| `./Scripts/test.sh` (also with a clean `--scratch-path`) | 95 tests in 13 suites passed; localization check passed |
| `./Scripts/bundle.sh release` | Built; helper in `Contents/Helpers` with mode 0755; ad-hoc signed |
| `codesign --verify --strict --deep build/Sandy.app` | OK; helper identifier `com.abdirakhym.sandy.agent` |
| `./Scripts/test-helper.sh` | Media helper answered with a snapshot |
| `./Scripts/dmg.sh` | `build/Sandy-0.1.0.dmg` (1.9 MB); version inside 0.1.0; mounted image contains the helper; signature verifies |
| `spctl -a -vv build/Sandy.app` | **rejected** (expected for ad-hoc) |
| Bundle id / version | `com.abdirakhym.sandy` / `0.1.0`, matches `Scripts/version` |
| Helper end to end (temp dirs) | hook: no stdout, exit 0, prompt absent from spool; monitor: live events, exit 0 on SIGTERM, 64 on bad args; install/uninstall on a temp `settings.json` with backup |
| Helper on the real `~/.codex` (read-only, 110 rollouts) | 9 sessions in the snapshot; only metadata fields in the output; 0.19 s CPU per 60 s idle; 39 MB RSS |
| App launched with `HOME`/`CFFIXED_USER_HOME` in a temp dir | Ran for 60 s with 0.15 s CPU and about 47 MB RSS. No `sandy-agent` process (monitoring is off by default). Nothing created in the real home. perl child exited with the app. |

## 5. Remaining risks

- **Not tested by hand:** hover and rails, media controls, shelf drag and drop,
  calendar permission flow, translation, currency offline behaviour, keyboard
  lock, notifications (permission prompt and click-through), the Agents UI, and
  the Install/Remove hook buttons in the app.
- **Not tested end to end:** a real Claude Code session. Claude Code 2.1.144 is
  installed but has never been used here. Hook semantics come from the official
  docs. Claude usage depends on the undocumented transcript format.
- **Not observed:** Codex CLI/IDE sessions (only Codex Desktop 0.163 was
  present). Intel Macs, macOS 15.x and Xcode toolchains were not run.
- **Product decision:** saving every copied image to `~/Pictures/Sandy` is on by
  default. Consider off by default, or a first-run notice.
- **Distribution:** ad-hoc only. A public download needs a Developer ID
  signature and notarization (`docs/signing.md`); ad-hoc is not equivalent.
- **Process:** `release.sh` requires a clean tree and a green CI run. No remote
  exists, so CI has not run on these changes.

## 6. Release verdict

**INCONCLUSIVE.**

The confirmed blockers are fixed and every automated check passes. Still, the
manual half of the release checklist was not done, the Agents feature was not
exercised in the GUI or with a live Claude session, and the tree was being
edited in parallel during the audit.

To reach **READY WITH WARNINGS** (local / source release):
1. Commit the tree, including the restored notices.
2. Recheck README links in all languages.
3. Get a green CI run.
4. Go through `docs/release-checklist.md`, including the new Agents section.

A public binary release additionally needs Developer ID signing and
notarization.

---

## Addendum — work after the audit (2026-10-26)

### Changes made
- **Bug fixes**: SwiftUI focus races in snippets, currency picker, teleprompter (dropped input — deferred focus requests); clipboard text dropped when an item carried both image and text.
- **New features**: Utilities timer (5/10/25 min, notification on finish) and keep-awake (`caffeinate`); shelf OCR («Copy Text», Vision, on-device), Quick Look, «Send to Teleprompter»; clipboard search, image markers, size limit (40/200/500), opt-in persistence (`clipboard.json`, 0600, deleted when disabled), per-app exclusions; meeting reminders (1/5/10 min, permission on toggle only); agent completion glow (notch flash on `ready`, off-switch); session «Open in Terminal/Editor»; translation pair picker; «Remove Only Listed Files» scope for screenshot cleanup.
- **Mobile layer (parallel work, reviewed cursorily)**: `SandyMobileCore` (HPKE-encrypted relay envelopes), `MobileLinkStore`, `mobile-approval` Claude hook, `Mobile/` gateway + iOS/Android clients. Push credentials come from env (`APNS_KEY_FILE`, `FCM_KEY_FILE`); no keys in the tree.

### Verification after the audit
- `Scripts/test.sh`: **122 tests, all passing**; `check-localizations.py`: 226 keys × 8 languages.
- `bundle.sh`: clean release build, ad-hoc sign OK.
- **Live E2E on the real build**: `pbcopy` → `clipboard.json` written correctly; `claude-hook` (SessionStart → PostToolUse → Stop) → session reached `ready` in `Agents/history.json` with project path and operation count — the completion-glow path fired. `install/uninstall-mobile-approvals` on a temp settings file: adds only its own `PermissionRequest` hook (silent if helper missing), removes only its own entry, preserves foreign hooks.
- **Not verified manually**: timer/keep-awake UI, OCR and Quick Look menus, meeting reminders with real calendar access, glow visuals, mobile pairing end-to-end, snippet field focus.

### Verdict (unchanged): INCONCLUSIVE → trending READY WITH WARNINGS
Automated checks and live smoke tests pass; the remaining gap is a manual UX pass on the new features and the standard release-checklist items (CI run, real Claude session, notarization).
