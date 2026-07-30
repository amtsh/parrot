# parrot

A minimal macOS dictation daemon. Push-to-talk, on-device transcription, text inserted at the cursor.

## Install

```sh
curl -fsSL https://amtsh.github.io/parrot/scripts/install.sh | sh
parrot setup                       # grants mic + accessibility, downloads the model
parrot install --launch-at-login   # optional — runs in the background on login
```

**Requires:** macOS 14+ on Apple Silicon (M1 or newer). Transcription runs on the Apple Neural Engine via CoreML — so the installer refuses to run on Intel.

The installer drops the binary in `/usr/local/bin/parrot`. Builds are unsigned for now, so the installer strips the quarantine xattr — once you've inspected the script you'll see exactly what it does.

## How to use

1. **Run it.** `parrot` in any terminal tab — it detaches to the background immediately and frees the terminal. (Or `parrot install --launch-at-login` to also have it start automatically at login.)
2. **First run only:** the bird icon appears in the menu bar right away with a **Setup** section showing what's missing. Click "Grant Accessibility…" and "Grant Microphone…" there — parrot picks up the grants automatically (accessibility needs one relaunch, which parrot does for you) and starts dictating without any extra steps.
3. **Click into the text field you want to dictate into** — Messages, the address bar, a Slack thread, anywhere a cursor blinks.
4. **Hold the `fn` key, speak, release.** A small pill appears at the bottom of the screen while the mic is hot.
5. **The transcript types itself in at the cursor** when you release. Usually within 200-300ms.

That's it. There is no record button, no stop button, no "send" — `fn` is the whole interface.

Once everything's granted, the bird icon in the menu bar gives you: a **Model** submenu to switch transcription models on the fly, checkboxes for the recording overlay / hotkey-debug logging / last-recording capture, a **Start at Login** toggle, and **Quit**.

> **Note:** on most modern Macs the `fn` key is the bottom-left key. If yours is set to "Change input source" or "Show emoji & symbols," the menu bar's Setup section will flag it — click through to Keyboard Settings to flip it back to plain `fn`. (`parrot setup` still exists as a terminal-only walkthrough if you prefer it.)

## CLI

```sh
parrot                                 # run detached in the background (frees the terminal)
parrot --foreground                    # stay attached to the terminal instead (^C to quit)
parrot setup                           # one-time setup: permissions + model download
parrot install --launch-at-login       # register a LaunchAgent (background daemon)
parrot install --uninstall             # remove the LaunchAgent
parrot doctor                          # check permissions + fn key setting
parrot models list                     # list available models
parrot models download <id>            # pre-download a model
parrot --model whisper-large-v3-turbo  # bigger, multilingual, slower first-run
parrot --no-overlay                    # disable the bottom-of-screen pill
```

## Stack

- **Swift** — single SPM executable target
- **WhisperKit** — Whisper inference via CoreML, ANE-accelerated
- **AVAudioEngine** — mic capture
- **CGEventTap** — global hotkey
- **CGEvent** — text injection at cursor
- **NSWindow** (borderless, click-through) — recording-indicator pill

See [docs/architecture.md](docs/architecture.md) for design notes.

## Build from source

```sh
swift build -c release
.build/release/parrot --help
```
