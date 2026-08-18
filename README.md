# OpenVale

![OpenVale icon](Packaging/AppIcon.png)

OpenVale is a small, native macOS menu-bar app that plays your own local video
files behind the desktop icons. It stays out of the Dock, can launch at login,
and can change to a different wallpaper each day.

OpenVale contains **no wallpaper videos**. Your files stay on your Mac and are
never uploaded.

## Requirements

- macOS 13 Ventura or later
- Apple silicon or Intel Mac
- Apple Command Line Tools (free)

If `swift --version` does not work, install the tools once:

```sh
xcode-select --install
```

## Install

Clone this repository, open Terminal in the repository folder, and run:

```sh
./scripts/install.sh
```

The script checks the Mac, builds OpenVale from source, installs it into
`~/Applications/OpenVale.app`, and launches it. It does not need `sudo`.

On first launch:

1. Choose **Choose Wallpapers…**.
2. Select one or more MP4, MOV, or M4V files.
3. OpenVale copies the files into
   `~/Library/Application Support/OpenVale/Wallpapers` without resizing or
   re-encoding them.
4. Use the menu-bar leaf to choose a wallpaper, enable daily rotation, pause,
   add or remove files, and control **Start at Login**.

macOS may show a background-item notification when OpenVale first registers
itself to start at login. If approval is needed, the OpenVale menu offers a
shortcut to the relevant System Settings page.

## Finding a wallpaper

[Spring Meadow in 4K on MotionBGS](https://motionbgs.com/spring-meadow) is a
good first wallpaper. Download the video yourself, check the provider's terms,
then add the local file through OpenVale. The project does not redistribute or
hotlink the video file.

The displayed quality is the quality of the selected source file. OpenVale
shows the measured pixel dimensions in its menu and labels a file “4K” only
when it is approximately 3840×2160 or larger. It never upscales or recompresses
imports.

## Everyday controls

Click the menu-bar leaf to:

- add several video wallpapers at once;
- choose a specific wallpaper or move to the next one;
- switch daily rotation on or off;
- pause and resume animation;
- reveal the current file or open the wallpaper folder;
- move an imported wallpaper to the Trash; and
- enable or disable launch at login.

Playback is muted. OpenVale pauses when the displays sleep or the user session
locks, and it restores the desktop windows after wake, unlock, display changes,
or switching Spaces.

## Update

Pull the latest source and run the installer again:

```sh
git pull
./scripts/install.sh
```

Existing wallpapers in Application Support are preserved.

## Uninstall

```sh
./scripts/uninstall.sh
```

The uninstall script removes the app and unregisters its login item, but keeps
your wallpaper videos. It prints the folder to delete manually if you also want
to remove those files.

## Build and test

OpenVale is a Swift Package Manager project with no third-party dependencies.
Packaging works with Apple Command Line Tools alone. Running the XCTest suite
requires full Xcode on toolchain installations that do not bundle XCTest.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./scripts/package.sh
```

The packaged app is written to `dist/OpenVale.app` and is ad-hoc signed because
it is built locally. A downloadable prebuilt release would require Apple
Developer ID signing and notarization; this source-first install avoids asking
users to bypass Gatekeeper for an unsigned internet download.

## Compatibility notes

OpenVale targets macOS 13 because Apple introduced the current `SMAppService`
login-item API in Ventura. The install script builds a native binary for the
Mac running it, so the same repository works on Intel and Apple-silicon Macs.
The clean-install release rehearsal is recorded in
[`docs/clean-install-rehearsal.md`](docs/clean-install-rehearsal.md).

## Media and privacy

- No analytics, accounts, network service, or automatic downloads.
- Imported videos remain local in your user Library.
- Wallpaper media is intentionally ignored by Git and excluded from builds.
- OpenVale's MIT license covers the source code and app icon, not videos that a
  user obtains from third parties.

## License

[MIT](LICENSE)
