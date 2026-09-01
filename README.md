# Keymote

Keymote is a macOS menu-bar app that maps the third-generation Apple Siri
Remote (A2854) to keyboard and system actions.

## Features

- Configurable tap and long-press actions for the directional clickpad, Back,
  TV, Play/Pause, Mute, volume, and Siri buttons.
- An interactive Apple Siri Remote layout for selecting and editing a button.
- App-specific profiles for Terminal, Ghostty, Otty, Kitty, Chrome, Edge, and
  ChatGPT, plus a default profile. Profiles can inherit an action from the
  default profile.
- Volume buttons switch tabs in supported profiles; long-press continues to
  adjust system volume. The default profile keeps normal system-volume control.
- TV can open a user-selected application. Long-press TV opens the macOS
  application switcher; use Left/Right to select, Centre to confirm, or Back
  to cancel.
- Chinese and English interfaces, light/dark/system appearance options, and a
  Dock visibility setting.

## Run and build

```sh
swift run Keymote
./scripts/build-app.sh
open dist/Keymote.app
```

Keymote requests Input Monitoring permission to receive paired Siri Remote HID
events and Accessibility permission to send configured keyboard actions. Pair
the A2854 in System Settings before opening Keymote.

`build-app.sh` prefers the first local Apple Development identity so macOS
privacy grants stay stable across local rebuilds. Set
`KEYMOTE_SIGNING_IDENTITY` to choose one explicitly. The legacy
`SRI_VIBE_SIGNING_IDENTITY` name remains supported for existing local setups.

## Diagnose remote input

For safe hardware calibration, run:

```sh
open dist/Keymote.app --args --diagnose-input
```

Diagnostic mode logs recognized button presses and never sends actions to
another app.
