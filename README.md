# Backside

Backside is a lightweight, native macOS scratchpad that attaches directly to another app's window. It gives you an instant, contextual notepad for any window on your Mac without cluttering your desktop or breaking your workflow.

---

## What's in Backside

- **Contextual Window Scratchpads**: Every window gets its own dedicated scratchpad.
- **Window Following**: Scratchpad panels track the target window's frame in real-time, working seamlessly across displays and macOS Spaces.
- **Native Option-Click Gesture**: Hold **Option** and click any window's title bar to reveal or hide its scratchpad. The click still passes through natively to the target application.
- **Smooth Flip Animation**: Panels animate with a 3D flip effect and dismiss cleanly when you press **Escape** or repeat the gesture.
- **Local SQLite Persistence**: Notes and window metadata (app name, bundle ID, window title, timestamps) are stored locally in SQLite at `~/Library/Application Support/Backside/notes.sqlite`.
- **Note Library**: A multi-column window to browse notes by app, search across all notes, pin important scratchpads, and edit content directly.
- **Menu Bar Accessory**: Runs unobtrusively in the menu bar with no Dock clutter.

---

## How to Use

### 1. Toggle a Scratchpad
- Hold **Option** and click any app's title bar (or unified toolbar area).
- Backside attaches to that window and reveals its scratchpad.
- Start typing immediately. Your notes are saved automatically as you type.
- Press **Escape** or **Option-click** the title bar again to dismiss.

### 2. Note Library
- Click the Backside icon in the menu bar.
- Select **Open Note Library** (or press **⌘L**).
- Filter notes by application, search through note contents, pin critical notes to the top, and edit notes in place.

### 3. Menu Bar Controls
- **Open Note Library**: View and search all captured notes.
- **Hide All Scratchpads**: Instantly dismiss all open panels.
- **Grant Accessibility Access…**: Quick shortcut to macOS privacy settings.
- **Quit Backside**: Terminate the application.

---

## Accessibility Permission

Backside requires macOS Accessibility access to detect window frames and monitor title bar clicks.

When launching Backside for the first time:
1. macOS will prompt you to grant Accessibility access.
2. If prompted, open **System Settings → Privacy & Security → Accessibility**.
3. Toggle the switch next to **Backside** (or your terminal application if running via command line).

---

## Running Locally

### Requirements
- macOS 14.0 (Sonoma) or newer
- Xcode 15.4+ or Swift 5.10+

### Quick Run
Run the app directly using the Swift Package Manager:

```sh
swift run Backside
```

### Build as a Native macOS Application
To build and launch the standalone application bundle (`Backside.app`):

```sh
# Package Backside.app, DMG, and ZIP in dist/
./scripts/package.sh

# Launch the built app
open dist/Backside.app
```
