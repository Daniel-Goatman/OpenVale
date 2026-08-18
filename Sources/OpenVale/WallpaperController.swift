import AppKit
import AVFoundation

@MainActor
final class WallpaperController {
    @MainActor
    private final class PlaybackSurface {
        let window: NSWindow
        let player: AVQueuePlayer
        let looper: AVPlayerLooper

        init(window: NSWindow, player: AVQueuePlayer, looper: AVPlayerLooper) {
            self.window = window
            self.player = player
            self.looper = looper
        }

        func stop() {
            player.pause()
            looper.disableLooping()
            window.orderOut(nil)
        }
    }

    private var surfaces: [PlaybackSurface] = []
    private var currentVideoURL: URL?
    private var screensAreAsleep = false
    private var sessionIsLocked = false
    private(set) var isManuallyPaused = false

    var onPlaybackStateChanged: (() -> Void)?

    init() {
        installObservers()
    }

    var isPlaying: Bool {
        currentVideoURL != nil && !isManuallyPaused && !screensAreAsleep && !sessionIsLocked
    }

    func display(videoAt url: URL) {
        if currentVideoURL != url || surfaces.count != NSScreen.screens.count {
            currentVideoURL = url
            rebuildDesktopSurfaces()
        }
        updatePlaybackState()
    }

    func stopAndClear() {
        currentVideoURL = nil
        isManuallyPaused = false
        clearSurfaces()
        onPlaybackStateChanged?()
    }

    func toggleManualPause() {
        isManuallyPaused.toggle()
        updatePlaybackState()
    }

    private func rebuildDesktopSurfaces() {
        clearSurfaces()
        guard let url = currentVideoURL else { return }

        for screen in NSScreen.screens {
            let player = AVQueuePlayer()
            player.isMuted = true
            player.volume = 0
            player.preventsDisplaySleepDuringVideoPlayback = false
            player.automaticallyWaitsToMinimizeStalling = false

            let item = AVPlayerItem(url: url)
            let looper = AVPlayerLooper(player: player, templateItem: item)
            let window = makeDesktopWindow(for: screen)
            let contentView = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = NSColor.black.cgColor
            contentView.layer?.contentsScale = screen.backingScaleFactor

            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.frame = contentView.bounds
            playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.contentsScale = screen.backingScaleFactor
            contentView.layer?.addSublayer(playerLayer)

            window.contentView = contentView
            window.orderFrontRegardless()
            surfaces.append(PlaybackSurface(window: window, player: player, looper: looper))
        }
    }

    private func clearSurfaces() {
        surfaces.forEach { $0.stop() }
        surfaces.removeAll()
    }

    private func makeDesktopWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = .black
        window.animationBehavior = .none
        window.canHide = false
        window.isExcludedFromWindowsMenu = true
        window.isReleasedWhenClosed = false
        return window
    }

    private func installObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(screensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(screensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(sessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        let distributedCenter = DistributedNotificationCenter.default()
        distributedCenter.addObserver(
            self,
            selector: #selector(screenWasLocked),
            name: Notification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        distributedCenter.addObserver(
            self,
            selector: #selector(screenWasUnlocked),
            name: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
    }

    @objc private func screensDidSleep() {
        screensAreAsleep = true
        updatePlaybackState()
    }

    @objc private func screensDidWake() {
        screensAreAsleep = false
        restoreDesktopWindowsIfNeeded()
        updatePlaybackState()
    }

    @objc private func sessionDidBecomeActive() {
        restoreDesktopWindowsIfNeeded()
        updatePlaybackState()
    }

    @objc private func screenWasLocked() {
        sessionIsLocked = true
        updatePlaybackState()
    }

    @objc private func screenWasUnlocked() {
        sessionIsLocked = false
        restoreDesktopWindowsIfNeeded()
        updatePlaybackState()
    }

    @objc private func screenConfigurationChanged() {
        rebuildDesktopSurfaces()
        updatePlaybackState()
    }

    private func restoreDesktopWindowsIfNeeded() {
        guard currentVideoURL != nil else { return }
        if surfaces.count != NSScreen.screens.count {
            rebuildDesktopSurfaces()
        } else {
            surfaces.forEach { $0.window.orderFrontRegardless() }
        }
    }

    private func updatePlaybackState() {
        if isPlaying {
            surfaces.forEach { $0.player.play() }
        } else {
            surfaces.forEach { $0.player.pause() }
        }
        onPlaybackStateChanged?()
    }
}
