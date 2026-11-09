# LoopWall

A native macOS app that plays a video as your desktop wallpaper in a seamless loop, with a Wallpaper Engine-style library. "LoopWall" is a placeholder name: change `AppConfig.appName` in `Sources/LoopWall/AppConfig.swift`.

Swift 5.9+, SwiftUI + AppKit + AVFoundation, no third-party packages. Deployment target: macOS 15.

## Build and run

Requirements: Xcode (with its command line tools) installed.

```bash
swift build -c release
swift run -c release LoopWall
```

No Apple Developer account is needed: everything runs locally from the bare executable, without signing or notarization.

The app has no Dock icon. Look for the ▶ icon in the menu bar:

- **Open Library…** opens the wallpaper grid. Drag `.mp4`, `.mov` or `.m4v` files into it (or use Import), then click a thumbnail to apply it. Right-click a thumbnail to remove it. The picker in the toolbar chooses one display or all displays.
- **Pause / Resume**, **Mute** (muted by default), **Next Wallpaper**, **Settings…**, **Quit**.
- The Dock icon appears only while the Library or Settings window is open.

The last wallpaper of each display is restored at launch.

### Build a real .app

```bash
Scripts/make-app.sh
open build/LoopWall.app
```

This builds the release binary, wraps it in `build/LoopWall.app` and signs it ad-hoc (no Apple Developer account, no notarization). Quit any running copy first (`pkill -x LoopWall`). You can drag the app to `/Applications`. If macOS blocks the first launch of a copy that was downloaded or moved from another Mac, right-click it and choose Open.

### Opening in Xcode (optional)

Run `open Package.swift`, choose the `LoopWall` scheme and press Run.

## Where data lives

`~/Library/Application Support/LoopWall/` holds `Videos/` (copies of imported files), `Thumbnails/` and `library.json`. Removing an item from the library deletes its copy there, never your original file.

## Pause rules (Settings)

Playback pauses, and resumes automatically, when:

- the wallpaper is fully covered (for example by a fullscreen app),
- Low Power Mode is on while the Mac is on battery,
- the screen is asleep or locked.

Each rule can be turned off in Settings.

## Import from Wallpaper Engine

In the Library window, click **Wallpaper Engine…** and choose a Workshop folder. The suggested default is
`~/Library/Application Support/Steam/steamapps/workshop/content/431960`.

- Only items whose `project.json` has `"type": "video"` and a playable `.mp4`, `.mov` or `.m4v` file are imported.
- `scene`, `web` and `application` items are listed as "not supported" with the reason. `.pkg` files are never parsed.
- Video items in another format (for example `.webm`) are marked "needs conversion". They can be converted to H.264 `.mp4` only if you already have `ffmpeg` installed. LoopWall never installs it.

### Download by Workshop ID (optional)

Needs `steamcmd`, installed by you (the app only looks for it with `which steamcmd` and never downloads it). Enter your Steam **username** and the Workshop ID, then click **Open Terminal**. It runs:

```
steamcmd +@sSteamCmdForcePlatformType windows +login <username> +workshop_download_item 431960 <id> +quit
```

Type your password and Steam Guard code in that Terminal window. The app never reads, stores, logs or sends them, and no Steam Web API key is used. When the download ends, scan the folder again.

Workshop content belongs to its authors and is for personal use only.

## Troubleshooting

- **Nothing appears in the menu bar:** make sure the app is still running (`pgrep -x LoopWall`) and stop old copies with `pkill -x LoopWall`.
- **Wallpaper not visible:** use Open Library… and click a thumbnail; the app starts empty. Fullscreen apps hide it by design (and pause playback).
- **"AVFoundation cannot play this file":** the file uses a codec macOS cannot decode. Use H.264 or HEVC in `.mp4`/`.mov`/`.m4v`.
- **Launch at login fails:** it uses `SMAppService.mainApp`, which needs the real `build/LoopWall.app` (run `Scripts/make-app.sh`), not a bare `swift run` executable. Settings shows the system error if it still fails. Ad-hoc signed apps may also need approval in System Settings > General > Login Items.
- **`steamcmd` not found:** the app searches a login shell's PATH (`which steamcmd`). Check it works in a fresh Terminal.
- **Build fails after an Xcode update:** run `swift package clean` and build again.
- **Debug builds use more CPU:** measure with `-c release`.
