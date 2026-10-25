# Sandy

<img src="Resources/AppIcon.png" alt="Sandy app icon" width="160">

[English](README.md) · [Русский](README.ru.md) · [Қазақша](README.kk.md) · [Deutsch](README.de.md) · [Français](README.fr.md) · [Español](README.es.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md)

**A small workspace at the top of your Mac.**

Sandy is a native macOS utility for music, files, clipboard history, notes and local
AI agent monitoring. Hover over the MacBook notch or press **⌃⌥Space** to open the
panel. Displays without a notch use a strip at the top of the screen.

Developed by Abdirakhym, based on the MIT-licensed
[Cyclop](https://github.com/akalikbergenov/cyclop) project. Sandy's adaptations,
localizations and agent integration live in this repository.
[Third-party notices](THIRD_PARTY_NOTICES.md) preserve source attribution.

**Status:** version **0.1.0**, built from source. Phone access is planned; the
current app sends agent notifications on the Mac only.

## Features

| Feature | What you can do |
|---|---|
| Music | See the current track and control supported players through macOS Now Playing; Apple Music and Spotify have a fallback integration. |
| File shelf | Keep file references, drag files between apps and copy a selection. Quick Look previews, on-device OCR on images, send .txt to the teleprompter. Removing a card leaves the original file in place. |
| Clipboard | Find recently copied text, files and image markers; history is searchable. Size is configurable (40–500), persistence between launches is opt-in and chosen apps can be excluded. |
| Snippets | Save reusable text such as an address, template or command and copy it when needed. |
| Calendar | View upcoming meetings from calendars available on this Mac, open supported meeting links, and optionally get reminded 1–10 minutes before one starts. |
| Translate | Translate on-device using downloaded macOS language packs; pick a pair in Settings or let the text script route English ↔ Russian automatically. |
| Currency | Convert currencies using public exchange rates; refreshing rates requires an internet connection. |
| Agents | Follow supported local Claude Code and Codex sessions, their latest operation, state and available usage statistics. The notch flashes when an answer is ready (can be disabled); a session's project opens in Terminal or an editor. |
| Notes | Keep short notes without opening another window. |
| Teleprompter | Read a scrolling script near the camera while recording a demo, presenting or taking a call. |
| Utilities | Use a timer, keep the Mac awake, or temporarily lock the keyboard for cleaning with Accessibility access. |
| Settings | Switch among eight interface languages, choose a panel shortcut, hide tabs and configure displays or login launch. |

Agent monitoring is passive: it does not start model requests or approve actions.
Coverage depends on the source. Codex permission prompts and errors are not
reliably present in its local logs. Saved history contains session metadata and
totals, rather than a complete recording of every action.
[Read the integration limits](docs/agent-bridge.md).

## Install on a Mac

You need **macOS 15 or later**, **Swift 6 or later** and **Python 3** for the
localization check. A current Xcode Command Line Tools installation is sufficient;
the full Xcode app and a MacBook notch are optional.

### 1. Install the developer tools

Open **Terminal** from Applications → Utilities and run:

```sh
xcode-select --install
```

Complete the macOS installer. If the tools are already installed, continue. Check:

```sh
swift --version
python3 --version
```

The Swift version must start with 6 or later. Update the tools or select a current
installed Xcode toolchain if an older compiler is selected.

### 2. Get the source

On this repository's GitHub page, choose **Code → Download ZIP**, unzip it and open
the resulting folder in Finder. A Git clone works too if you already use Git.

In Terminal, type `cd ` with a trailing space, drag the project folder from Finder
into Terminal and press Return. It must contain `Package.swift`, `Sources` and
`Scripts`.

### 3. Build and open Sandy

```sh
./Scripts/bundle.sh
```

Wait for successful completion. This builds the release app and its helpers,
copies eight localizations and verifies the signature. The result is
**`build/Sandy.app`**. Open the folder:

```sh
open build
```

Drag **Sandy.app** into **Applications** and launch it from there. Choose a stable
location before enabling login launch or installing Claude hooks: hooks refer to
the helper inside this particular app bundle. For a development run, use:

```sh
open build/Sandy.app
```

Sandy is a menu bar application with no regular Dock window. Hover at the top
center, use the menu bar icon or press **Control + Option + Space**.

The default build uses ad-hoc signing. A public release with Developer ID and
notarization requires the maintainer's Apple Developer credentials;
see [signing](docs/signing.md). This README does not advertise a published DMG
or App Store listing. If macOS blocks an unnotarized build you trust, follow
[Apple's opening instructions](https://support.apple.com/en-us/102445): after the
first launch attempt, System Settings → Privacy & Security may offer **Open Anyway**.
Keep macOS security protections enabled.

## First setup

1. Open **Settings → General → Language**. Choose English, Russian, Kazakh, German,
   French, Spanish, Simplified Chinese or Japanese. The panel changes immediately;
   native permission dialogs use the choice after restarting Sandy.
   **System Language** follows macOS preferences.
2. Keep **Control + Option + Space**, or choose **Control + Shift + Space**,
   **Command + Shift + Space**, or **Control + Option + S**. Choose another if a
   combination is unavailable. Press it again or Esc to close; an active editor
   may handle Esc first. The shortcut does not need Accessibility access.
3. Under **Show in Panel**, keep the tabs you use. Under **Displays**, configure
   multiple displays and the top strip on screens without a cutout.
4. Enable **Launch at Login** if wanted. If you hide the menu bar icon, reopen
   Sandy from Applications to restore it.
5. Review **Screenshots → Save Clipboard Screenshots**. It is on by default and
   saves **any PNG/TIFF image copied to the clipboard**, including browser images,
   to `~/Pictures/Sandy`. Turn it off if unwanted. Watching a screenshots folder
   is a separate optional setting with a folder picker.

### Connect Claude Code and Codex

The agents must already be installed and running locally. Sandy does not install
them or supply a subscription or API key.

1. Under **Settings → Agent Monitoring**, enable **Monitoring** and your sources.
2. For Claude Code, click **Install Claude Hooks**. This explicit action merges
   Sandy's hooks into Claude settings and backs up the previous file; existing
   hooks are retained. Start or resume a local session.
3. For Codex, the helper observes supported local rollout logs. Cloud sessions
   are outside the current integration.
4. Enable **Agent Notifications** and allow notifications in macOS when prompted.
   Supported transitions can notify you when an answer is ready, input is needed
   or an error occurs. Source limitations still apply.
5. Open **Agents** for sessions and per-project statistics. If the helper
   disconnects, use **Retry**. Offline work is not reported as completed work.

If you move the app, remove its old Claude hooks and install them again from the
final location. Details and supported versions: [agent monitoring](docs/agent-monitor.md)
and [the helper protocol](docs/agent-bridge.md).

### Translation and permissions

The **Translate** tab defaults to **English ↔ Russian**, independently of the
interface language. Under **Settings → Translate**, choose explicit source and
target languages if needed. Availability depends on macOS and installed packs.
Use **Translation Languages…** to open macOS Language & Region settings, download
the required packs, then return and choose **Retry**. Translation runs on-device.

**Calendar** requests access when you press its access button. Choose the calendars
to display. Keyboard cleaning requests Accessibility access when you use it.
Player fallback integration can also require Automation or Accessibility access.
Screen Recording is not required.

## Phone access and long tasks

**Not implemented in Sandy 0.1.0.** There is no Sandy phone app, remote push channel,
pairing flow or approval endpoint. Mac notifications do not automatically become
iPhone or Android notifications.

The proposed scope is:

- **iPhone and Android:** session state, recent activity, elapsed time and alerts
  for completion, failure or input requests, even on a different network.
- **iPhone:** Lock Screen Live Activities and Dynamic Island on compatible models.
- **Action confirmation:** explicit Allow/Deny for a particular pending request,
  after phone authentication, with a short expiry and one-time application on Mac.
- **Security:** revocable device pairing, encrypted transport and an activity log
  with sensitive data minimized. No unconditional auto-approval.

[The Coucou study and security plan](docs/mobile-security-review.ru.md) explains
platform differences, missing Sandy components and the checks required before
shipping. The Mac must remain awake and connected to publish new activity.
This section describes planned work, not steps to enable an existing feature.

## Data and privacy

| Data | Location and behavior |
|---|---|
| Settings | `~/Library/Application Support/Sandy/config.json`; language and some Mac-specific settings also use app preferences. |
| Notes, snippets, teleprompter | Files in `~/Library/Application Support/Sandy`; readable local content, not an encrypted vault. |
| Clipboard history | In memory by default. Settings → Clipboard can enable saving text and file references to `clipboard.json`; persistence defaults to off. |
| Clipboard images | `~/Pictures/Sandy`; separate from text history. Files remain until cleared. |
| File shelf | References to original files; removing a card does not delete the original. |
| Agent history | `~/Library/Application Support/Sandy/Agents/history.json`; up to 30 days and 2,000 sessions. Prompts, replies and raw command output are omitted. |

The panel's privacy cover hides on-screen content; it does not encrypt local files.
Sandy has no telemetry, automatic updater or phone server. Currency refreshes
fetch public rates; Spotify's fallback may download artwork.
[SECURITY.md](SECURITY.md) describes permissions, storage and network behavior.

## Troubleshooting

| Symptom | What to check |
|---|---|
| No window or Dock icon | Use the menu bar icon, hover at the top center or press ⌃⌥Space. |
| Shortcut does nothing | Enable it in General settings; try another preset if registration failed. |
| No agent sessions | Enable the tab, Monitoring and a source; explicitly install Claude hooks; check helper status. |
| No Mac notifications | Enable Agent Notifications, allow Sandy in macOS Notifications and check Focus. Not every source emits every state. |
| Translator asks for a pack | Download packs for the selected pair and retry; available pairs depend on macOS, independently of UI languages. |
| No current track | Start playback in a supported player; Now Playing depends on private macOS behavior. |
| Build fails | Check macOS, Swift and Python versions, work from the project folder and keep the full Terminal error. |
| Nothing reaches the phone | Phone access is not part of the current build. See the plan above. |

To update a local installation, quit Sandy, rebuild, replace the app in the same
Applications location and reopen it. To uninstall, first **Remove Claude Hooks**,
disable login launch, quit Sandy and remove the app. Delete its support folder
and `~/Pictures/Sandy` separately only if you want to erase saved data and images.

## Development and checks

```sh
python3 Scripts/check-localizations.py  # Check UI and permission strings
./Scripts/test.sh                      # Store, integration and protocol tests
./Scripts/bundle.sh                    # Build and verify Sandy.app
./Scripts/test-helper.sh               # Exercise the bundled media helper
./Scripts/dmg.sh                       # Rebuild and package Sandy-0.1.0.dmg
```

Automated checks do not cover all pointer interactions, drag and drop, actual
playback, real calendar accounts or phone delivery. Recorded results and remaining
manual checks: [functional check](docs/functional-check.md),
[release checklist](docs/release-checklist.md).

Stack: SwiftUI, AppKit and Swift Package Manager. Main code: `Sources/Sandy`;
agent helper: `Sources/SandyAgentBridge` and `Sources/AgentBridgeCore`;
media helper: `Sources/SandyMediaHelper`; translations: `Resources/*.lproj`.
Versioning lives in `Scripts/version`. Now Playing uses a private macOS framework
and a system Perl helper; future macOS updates may require changes and the current
integration is unsuitable for the App Store.

The app artwork is `Resources/AppIcon.png`. `Scripts/make-icon.swift` packages it
at standard macOS sizes; `bundle.sh` generates the bundled ICNS automatically.

Further reading: [architecture](docs/architecture.md), [contributing](CONTRIBUTING.md),
[signing](docs/signing.md), [Russian Mac guide](docs/installation.ru.md),
[Threads / LinkedIn drafts](docs/social-posts.md).

## License and credits

[MIT](LICENSE). Sandy incorporates Cyclop source at revision
`125eb02fbd28b443fe922334ae09823d4ad38df6`, © 2026 akalikbergenov.
Keep the license and [third-party notices](THIRD_PARTY_NOTICES.md) in distributions;
the bundle includes both. Coucou is a research reference for future mobile work;
its branding, character and sounds are not included in Sandy.
