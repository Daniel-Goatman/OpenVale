# Clean-install rehearsal

This document records the release rehearsal performed before the first public
GitHub publication. It is intended to make installation problems visible rather
than imply compatibility from a successful compile alone.

## Target flow

1. Start from the exact files tracked by Git, with no `.build`, `dist`, app,
   preferences, Application Support folder, or imported media.
2. Run `./scripts/install.sh` as an ordinary user.
3. Confirm installation in `~/Applications` and first-launch guidance.
4. Import local MP4 and MOV videos through the system file picker.
5. Confirm the imported bytes match the source files.
6. Confirm measured 4K/HD labels, playback, looping, pause/resume, manual
   selection, daily mode, persistence after relaunch, and the menu-bar icon.
7. Confirm login-item registration status and clean uninstallation behavior.

## Environment

The rehearsal used an Apple-silicon Mac running macOS 15.7.5. The end-user
install ran with Apple Swift 6.1.2 from Command Line Tools; the XCTest suite and
Intel cross-build used full Xcode 26.3. OpenVale's deployment target remains
macOS 13, and the package manifest uses Swift tools 5.9 for compatibility with
older toolchains.

## Results

### Issues found before the clean run

- A verification command was initially written as if it ran from the parent
  directory, but was invoked from inside the repository. The release commands
  and README now consistently assume the repository root.
- The sandboxed development environment could not use Swift's normal compiler
  cache. This is specific to the test harness, not the end-user shell, and the
  rehearsal uses an explicitly writable module cache where required.
- The standalone Command Line Tools installed on the rehearsal Mac can build
  OpenVale but do not include XCTest. This does not affect installation; full
  Xcode is used for the contributor test suite and the README now says so.
- Apple's `iconutil` rejected a complete ten-size iconset on the rehearsal Mac
  and also failed to round-trip an Apple system icon. To remove that tool from
  the user path, the validated `OpenVale.icns` is checked into the repository;
  install and packaging scripts only copy it.
- The first installed build registered its login item and launched, but its
  one-time welcome alert did not come to the front because OpenVale is an
  accessory (`LSUIElement`) app. First-launch setup now temporarily adopts the
  regular activation policy while the welcome alert and file picker are open,
  then returns to menu-bar-only mode. The empty-state status icon was also
  changed from a generic photo symbol to the promised leaf.
- The welcome alert became visible on the second run, but could still sit below
  windows from the currently active app. All OpenVale modal windows now activate
  the running application, join the current Space, and use floating window level
  while awaiting user input.
- The installer initially copied a new bundle over an existing bundle. Although
  that works for the current three-file app, it could leave obsolete files after
  a future update. The installer now stops OpenVale, removes only the existing
  `~/Applications/OpenVale.app`, and installs a clean bundle. Wallpapers live in
  Application Support and are unaffected.
- The first release build launched correctly with an empty library but crashed
  after real videos were restored. The crash report showed `NSWindow`
  construction on a Swift concurrency worker thread after asynchronous metadata
  loading. `AppDelegate`, `WallpaperController`, playback surfaces, and timer
  callbacks now have explicit main-actor ownership. This was retested with the
  real library and through a quit/relaunch cycle.

### Final clean run — 18 August 2026

- Saved the existing wallpaper collection outside the repository before any
  uninstall. The backup contains 13 files (about 215 MB): five original
  downloads, five enhanced copies previously used by the old app, one Backdrop
  cache video, the old preference file, and a backup note. `diff -qr` verified
  every restored enhanced file byte-for-byte against that backup.
- Removed the old `Daily Backdrop.app` and its preferences. The unrelated
  third-party `Backdrop.app` was deliberately left untouched.
- Exported the exact staged Git tree (`dbfaa4f28bd9d189139319aee7ef382d1cb0b173`)
  into an empty temporary directory. The export contained no `.git`, `.build`,
  `dist`, preferences, Application Support data, or wallpaper media.
- Cleared OpenVale's installed bundle, preferences, and Application Support
  folder, then ran only `./scripts/install.sh` from that export. The native
  Apple-silicon build, ad-hoc signing, installation, and launch completed in
  44.53 seconds without `sudo`.
- The welcome dialog appeared on-screen at floating level with the approved app
  icon, **Choose Wallpapers…**, and **Not Now**. A prior clean run also confirmed
  that **Choose Wallpapers…** opens the native multi-select picker filtered to
  MP4, MOV, and M4V files.
- This test harness did not have Accessibility permission, so it did not send
  synthetic clicks into the picker. Import behavior was instead exercised by an
  XCTest integration test using a generated real MOV: the imported bytes matched
  the source, a repeat import was detected as a duplicate, and an invalid MP4
  was rejected without residue.
- Restored the five private videos after onboarding and relaunched. OpenVale
  remained running; no new crash report appeared. Core Graphics reported an
  on-screen 1512×982 desktop-level window plus the 38×37 menu-bar status item.
  Retina capture produced a 3024×1964 frame. Two captures two seconds apart had
  different SHA-256 hashes, confirming active animation.
- Media inspection reported four H.264 sources at 3840×2160 and one H.264
  forest source at 1920×1080. The app correctly labels the latter as HD rather
  than claiming it is 4K.
- macOS Background Task Management reported OpenVale as `enabled`, `allowed`,
  `visible`, and `notified`, pointing to `~/Applications/OpenVale.app`.
- A quit/relaunch cycle recreated both the desktop window and status item with
  the saved library. The nine-test XCTest suite passed after the concurrency
  fix.
- Release builds succeeded for native `arm64` and cross-compiled `x86_64`.
  `vtool` confirmed a macOS 13.0 minimum deployment target for both. The
  installed app is 2.6 MB, contains only its executable, Info.plist, icon, and
  signature, and passes strict code-signature verification.

## Compatibility conclusion

The source-first flow is verified on macOS 15.7.5 and compiles for Intel and
Apple silicon with a macOS 13 deployment target. It has not been runtime-tested
on physical Intel hardware or on every macOS 13/14 release, so CI covers current
macOS 14 and 15 runners while the native API choices remain available from
macOS 13 onward.

The app uses Apple's `SMAppService.mainApp` for launch-at-login and
`AVPlayerLooper` with a muted `AVQueuePlayer` per display. No helper daemon,
privileged installer, third-party package, analytics service, or bundled
wallpaper media is involved.
