# MENACE for macOS

Build a macOS app from **your own Windows or Steam copy** of [MENACE](https://store.steampowered.com/app/2432860/MENACE/).

**No game files are included or uploaded.** The generated app stays on your Mac.

## You need

- Apple Silicon Mac
- macOS 13 or newer
- Rosetta 2
- Your own MENACE copy or Steam license
- Internet for the first build
- 50 GB free for a local app + DMG

## Local copy

Download `MENACE-for-macOS.zip` from [Releases](../../releases/latest), unzip it, then run:

```bash
cd ~/Downloads/MENACE-for-macOS
./menace-macos build "/absolute/path/to/MENACE.rar"
```

Accepted inputs: RAR, 7Z, ZIP, an extracted game folder, or `Menace.exe`.

No path handy? This opens a Finder picker:

```bash
./menace-macos build
```

## Steam copy

```bash
cd ~/Downloads/MENACE-for-macOS
./menace-macos steam
```

Then:

1. Open the DMG on your Desktop.
2. Drag `MENACE.app` to Applications.
3. Open it. The official Windows Steam client installs.
4. Sign in and install MENACE.
5. Open `MENACE.app` again to play.

Steam credentials stay inside Valve's client. This tool never asks for them.

## Output

```text
Desktop/MENACE macOS/
|-- MENACE.app
|-- MENACE-macOS-v0.7.2.dmg
`-- BUILD-REPORT.txt
```

Steam mode creates `MENACE-Steam-macOS.dmg` instead.

## First launch

If macOS blocks the generated app, right-click `MENACE.app`, choose **Open**, then confirm **Open**.

## Tested

- Local MENACE v0.7.2 reached the title screen on an Apple M3 Mac.
- The wrapper forces Direct3D 11 through DXMT, matching MENACE's working configuration.
- Steam bootstrap, installer checksum, app ID `2432860`, install-manifest detection, and launch arguments have automated coverage.
- A full Steam download still requires an account that owns the game, so that last ownership-dependent step was not run here.

## Stuck?

```bash
./menace-macos doctor
./menace-macos build "/path/to/MENACE.rar" --verbose
```

Game log:

```text
MENACE.app/Contents/SharedSupport/prefix/drive_c/users/<you>/AppData/LocalLow/Overhype Studios/Menace/Player.log
```

## Important

- Steam mode downloads MENACE from Steam after ownership verification. It does not bypass Steam.
- Local mode rejects incomplete game folders and unsafe archive paths.
- Dependencies are pinned and SHA-256 checked. See [`Dependencies.lock.json`](Dependencies.lock.json).
- The generated local DMG contains your game copy. Do not redistribute it.
- This is an unofficial compatibility tool, not a native port and not affiliated with Overhype Studios or Hooded Horse.

## Build from source

Requires Xcode Command Line Tools:

```bash
swift test
swift build -c release
.build/release/menace-macos build "/path/to/MENACE.rar"
```

The wrapper code is MIT licensed. Downloaded components keep their own licenses; see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
