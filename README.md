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

## Packaging Locally

You can package the native macOS application bundle (`Backside.app`), DMG disk image, and ZIP archive locally using the packaging script:

```sh
# Build universal binary (arm64 + x86_64) and create Backside.app, DMG, and ZIP
./scripts/package.sh --version 1.0.0

# Or build only for the host architecture
./scripts/package.sh --version 1.0.0 --arch host
```

Artifacts are placed in `dist/`:
- `Backside.app`: macOS application bundle with embedded `Info.plist` and `AppIcon.icns`
- `Backside-1.0.0.dmg`: Installable disk image with `/Applications` shortcut
- `Backside-1.0.0.zip`: Standalone zip archive
- `Backside-1.0.0.dmg.sha256`, `Backside-1.0.0.zip.sha256`, and `checksums.txt`

## GitHub Actions & Automated Releases

Two workflows are configured in [`.github/workflows/`](.github/workflows/):

### 1. Build and Verify (`build.yml`)
- **Triggers**: On pull requests or pushes to the `main` branch.
- **Action**:
  - Compiles Backside on `macos-14` (Apple Silicon runner).
  - Builds the universal binary (`arm64` and `x86_64`).
  - Packages `Backside.app`, `.dmg`, and `.zip`.
  - Verifies code signature integrity.
  - Uploads build artifacts to GitHub Actions for easy testing and review.

### 2. Release (`release.yml`)
- **Triggers**:
  - Automatically on tag push: `git tag v1.0.0 && git push origin v1.0.0`
  - Manually via **Actions → Release → Run workflow** (with optional version input, draft, and prerelease toggles).
- **Action**:
  - Builds the universal app bundle and packages `.dmg` and `.zip`.
  - Generates SHA-256 checksums (`checksums.txt`).
  - Publishes a new GitHub Release with attached `.dmg`, `.zip`, and checksum assets.
  - Generates release notes automatically from commit logs.

#### Code Signing & Notarization (Optional)
The release workflow runs out-of-the-box with **ad-hoc code signing** without needing any secret configuration. If you have an Apple Developer account and wish to sign and notarize releases:

Configure the following GitHub Repository Secrets:
- `APPLE_CERTIFICATE`: Base64-encoded Developer ID Application `.p12` export (`base64 -i cert.p12`)
- `APPLE_CERTIFICATE_PASSWORD`: Password for the `.p12` certificate file
- `DEVELOPER_ID_APPLICATION`: Signing identity, e.g. `Developer ID Application: Your Name (TEAM_ID)`
- `APPLE_ID`: Your Apple ID email
- `APPLE_TEAM_ID`: Your 10-character Apple Developer Team ID
- `APPLE_APP_SPECIFIC_PASSWORD`: An app-specific password generated from [appleid.apple.com](https://appleid.apple.com)

