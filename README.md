# SriVibe

SriVibe is a macOS menu-bar controller for the third-generation Apple Siri Remote (A2854).

## Current V1 scope

- Uses the paired remote's HID controls: direction ring, centre, Back, TV, and Play/Pause.
- Automatically selects mappings for Terminal, Ghostty, Otty, Kitty, Chrome, Edge, ChatGPT, or a default profile.
- Provides configurable tap and hold actions, with a 300–1,500 ms hold threshold.
- Long-press TV opens the macOS application switcher; use Left/Right to
  choose, Centre to confirm, or Back to cancel.
- Shows in the Dock by default; this can be toggled from Settings → Device.
- Does not capture voice, touchpad gestures, mute, or power buttons.

## Run and build

```sh
swift run SriVibe
./scripts/build-app.sh
open dist/SriVibe.app
```

The app asks for Input Monitoring to read HID events and Accessibility to send configured keyboard actions. Pair the A2854 in System Settings before opening SriVibe.

`build-app.sh` prefers the first available local Apple Development identity, which
keeps macOS privacy grants stable across local rebuilds. If no local identity is
available it falls back to ad-hoc signing, for which macOS may request permissions
again after each rebuild. Set `SRI_VIBE_SIGNING_IDENTITY` explicitly for a chosen
identity; notarization remains a release-pipeline step.

For safe hardware calibration, launch `open dist/SriVibe.app --args --diagnose-input`.
It logs recognized button presses but never injects an action into another app.
