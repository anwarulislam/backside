# Backside

Backside is a lightweight, native macOS scratchpad that is attached to another app's window.

## Run

```sh
swift run Backside
```

Grant Accessibility access when macOS asks (or enable the terminal / built app in **System Settings → Privacy & Security → Accessibility**). Backside stays in the menu bar.

## MVP interaction

1. Hold **Option** and click another app's title bar.
2. Backside finds that Accessibility window and reveals its attached scratchpad.
3. Repeat the gesture, or press **Escape**, to hide it.

Notes are saved in `UserDefaults` by the target window identifier. The panel follows its target's frame, works across displays and Spaces, and is removed when the target closes.

The Option-click is intentionally passed through to the original app; the title-bar click retains normal native behavior.
