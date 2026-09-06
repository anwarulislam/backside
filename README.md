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

Notes and their window/app metadata are saved locally in SQLite at `~/Library/Application Support/Backside/notes.sqlite`. Use **Open Note Library** from the menu bar to browse notes by app, search their contents, pin important notes, and edit them in a dedicated window. The panel follows its target's frame, works across displays and Spaces, and is removed when the target closes.

The Option-click is intentionally passed through to the original app; the title-bar click retains normal native behavior.
