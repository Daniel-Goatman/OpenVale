import AppKit
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum DefaultsKey {
        static let rotationMode = "rotationMode"
        static let manualWallpaperID = "manualWallpaperID"
        static let didConfigureLoginItem = "didConfigureLoginItem"
        static let didOfferInitialImport = "didOfferInitialImport"
    }

    private let library = WallpaperLibrary()
    private let wallpaperController = WallpaperController()
    private var wallpapers: [Wallpaper] = []
    private var statusItem: NSStatusItem!
    private var midnightTimer: Timer?
    private var currentWallpaper: Wallpaper?

    private var rotationMode: RotationMode {
        get {
            guard
                let rawValue = UserDefaults.standard.string(forKey: DefaultsKey.rotationMode),
                let mode = RotationMode(rawValue: rawValue)
            else {
                return .daily
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: DefaultsKey.rotationMode)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        wallpaperController.onPlaybackStateChanged = { [weak self] in
            self?.updateStatusItem()
        }

        do {
            try library.prepare()
        } catch {
            presentErrorAlert(
                title: "Couldn’t Prepare OpenVale",
                message: error.localizedDescription
            )
        }

        configureStatusItem()
        scheduleNextDailyRefresh()
        configureLaunchAtLoginOnFirstRun()
        installWorkspaceObservers()

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.reloadLibraryAndApplySelection(force: true)
            if self.wallpapers.isEmpty,
               !UserDefaults.standard.bool(forKey: DefaultsKey.didOfferInitialImport) {
                UserDefaults.standard.set(true, forKey: DefaultsKey.didOfferInitialImport)
                self.presentFirstLaunchFlow()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        midnightTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func installWorkspaceObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    private func configureStatusItem() {
        let autosaveName: NSStatusItem.AutosaveName = "OpenValeStatusItem"
        UserDefaults.standard.register(defaults: [
            "NSStatusItem Preferred Position \(autosaveName)": 40
        ])

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = autosaveName
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusItem()
    }

    private func updateStatusItem() {
        let symbol: String
        if currentWallpaper == nil {
            symbol = "leaf"
        } else {
            symbol = wallpaperController.isPlaying ? "leaf.fill" : "pause.circle.fill"
        }

        statusItem?.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "OpenVale"
        )
        statusItem?.button?.toolTip = currentWallpaper.map {
            "OpenVale — \($0.title)"
        } ?? "OpenVale — Add a wallpaper"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let currentTitle = currentWallpaper.map {
            "Now Playing: \($0.title) (\($0.resolutionLabel))"
        } ?? "No Wallpapers Added"
        let currentItem = NSMenuItem(title: currentTitle, action: nil, keyEquivalent: "")
        currentItem.isEnabled = false
        menu.addItem(currentItem)
        menu.addItem(.separator())

        addMenuItem(
            menu,
            title: "Add Wallpapers…",
            action: #selector(addWallpapers),
            keyEquivalent: "o"
        )

        let wallpaperMenu = NSMenu(title: "Choose Wallpaper")
        if wallpapers.isEmpty {
            let emptyItem = NSMenuItem(title: "Add an MP4, MOV, or M4V file first", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            wallpaperMenu.addItem(emptyItem)
        } else {
            for wallpaper in wallpapers {
                let item = NSMenuItem(
                    title: "\(wallpaper.title) — \(wallpaper.resolutionLabel)",
                    action: #selector(selectWallpaper(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = wallpaper.id
                item.state = wallpaper.id == currentWallpaper?.id ? .on : .off
                wallpaperMenu.addItem(item)
            }
        }

        let wallpaperParentItem = NSMenuItem(title: "Choose Wallpaper", action: nil, keyEquivalent: "")
        wallpaperParentItem.submenu = wallpaperMenu
        menu.addItem(wallpaperParentItem)

        let automaticItem = NSMenuItem(
            title: "Change Wallpaper Daily",
            action: #selector(toggleAutomaticRotation),
            keyEquivalent: ""
        )
        automaticItem.target = self
        automaticItem.state = rotationMode == .daily ? .on : .off
        automaticItem.isEnabled = !wallpapers.isEmpty
        menu.addItem(automaticItem)

        let nextItem = addMenuItem(
            menu,
            title: "Next Wallpaper",
            action: #selector(nextWallpaper),
            keyEquivalent: "n"
        )
        nextItem.isEnabled = wallpapers.count > 1

        menu.addItem(.separator())

        let playbackTitle = wallpaperController.isManuallyPaused ? "Resume Animation" : "Pause Animation"
        let playbackItem = addMenuItem(
            menu,
            title: playbackTitle,
            action: #selector(togglePlayback),
            keyEquivalent: "p"
        )
        playbackItem.isEnabled = currentWallpaper != nil

        let revealItem = addMenuItem(
            menu,
            title: "Reveal Current Wallpaper in Finder",
            action: #selector(revealCurrentWallpaper),
            keyEquivalent: ""
        )
        revealItem.isEnabled = currentWallpaper != nil

        addMenuItem(
            menu,
            title: "Open Wallpapers Folder",
            action: #selector(openWallpapersFolder),
            keyEquivalent: ""
        )

        let removeItem = addMenuItem(
            menu,
            title: "Remove Current Wallpaper…",
            action: #selector(removeCurrentWallpaper),
            keyEquivalent: ""
        )
        removeItem.isEnabled = currentWallpaper != nil

        menu.addItem(.separator())

        addMenuItem(
            menu,
            title: "Get Spring Meadow in 4K…",
            action: #selector(openSpringMeadowPage),
            keyEquivalent: ""
        )

        let loginItem = NSMenuItem(
            title: LoginItemController.requiresApproval ? "Start at Login (Approval Required)" : "Start at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = LoginItemController.isEnabled ? .on : .off
        menu.addItem(loginItem)

        if LoginItemController.requiresApproval {
            addMenuItem(
                menu,
                title: "Open Login Item Settings…",
                action: #selector(openLoginItemSettings),
                keyEquivalent: ""
            )
        }

        menu.addItem(.separator())
        addMenuItem(menu, title: "Quit OpenVale", action: #selector(quit), keyEquivalent: "q")
    }

    @discardableResult
    private func addMenuItem(
        _ menu: NSMenu,
        title: String,
        action: Selector,
        keyEquivalent: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        menu.addItem(item)
        return item
    }

    private func reloadLibraryAndApplySelection(force: Bool = false) async {
        wallpapers = await library.wallpapers()
        applyScheduledWallpaper(force: force)
    }

    private func applyScheduledWallpaper(force: Bool = false) {
        guard !wallpapers.isEmpty else {
            currentWallpaper = nil
            wallpaperController.stopAndClear()
            updateStatusItem()
            return
        }

        let wallpaper: Wallpaper
        switch rotationMode {
        case .daily:
            let index = WallpaperSchedule.dailyIndex(for: Date(), count: wallpapers.count)
            wallpaper = wallpapers[index]
        case .manual:
            let savedID = UserDefaults.standard.string(forKey: DefaultsKey.manualWallpaperID)
            wallpaper = wallpapers.first(where: { $0.id == savedID }) ?? wallpapers[0]
        }

        if !force, wallpaper == currentWallpaper { return }
        apply(wallpaper)
    }

    private func apply(_ wallpaper: Wallpaper) {
        currentWallpaper = wallpaper
        wallpaperController.display(videoAt: wallpaper.url)
        updateStatusItem()
    }

    private func scheduleNextDailyRefresh() {
        midnightTimer?.invalidate()
        let nextMidnight = WallpaperSchedule.nextMidnight(after: Date())
        let interval = max(1, nextMidnight.timeIntervalSinceNow + 1)
        midnightTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.rotationMode == .daily {
                    self.applyScheduledWallpaper(force: true)
                }
                self.scheduleNextDailyRefresh()
            }
        }
    }

    private func configureLaunchAtLoginOnFirstRun() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: DefaultsKey.didConfigureLoginItem) else { return }
        defaults.set(true, forKey: DefaultsKey.didConfigureLoginItem)

        do {
            try LoginItemController.setEnabled(true)
        } catch {
            NSLog("OpenVale could not register as a login item: \(error)")
        }
    }

    private func presentFirstLaunchFlow() {
        // LSUIElement apps normally stay out of the Dock and do not take focus.
        // Temporarily act like a regular app so the one-time setup cannot hide
        // behind another application's windows, then return to menu-bar mode.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer {
            NSApp.setActivationPolicy(.accessory)
        }

        let alert = NSAlert()
        alert.messageText = "Welcome to OpenVale"
        alert.informativeText = "Choose one or more MP4, MOV, or M4V videos. OpenVale copies them into its private wallpaper folder without resizing or re-encoding them."
        alert.addButton(withTitle: "Choose Wallpapers…")
        alert.addButton(withTitle: "Not Now")
        prepareModalWindow(alert.window)
        if alert.runModal() == .alertFirstButtonReturn {
            presentWallpaperPanel()
        }
    }

    private func presentWallpaperPanel() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Add Wallpapers to OpenVale"
        panel.message = "Select one or more local video files. The originals are copied without re-encoding."
        panel.prompt = "Add Wallpapers"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, .movie]
        prepareModalWindow(panel)

        guard panel.runModal() == .OK else { return }
        let selectedURLs = panel.urls
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let wasEmpty = self.wallpapers.isEmpty
            let result = await self.library.importFiles(selectedURLs)
            self.wallpapers = await self.library.wallpapers()

            if let selected = result.imported.first {
                if wasEmpty {
                    self.apply(selected)
                } else {
                    self.applyScheduledWallpaper(force: true)
                }
            } else {
                self.applyScheduledWallpaper(force: true)
            }

            if !result.failures.isEmpty {
                self.presentErrorAlert(
                    title: "Some Wallpapers Weren’t Added",
                    message: result.failures.joined(separator: "\n")
                )
            } else if result.duplicateCount > 0 {
                self.presentInformationAlert(
                    title: "Already Added",
                    message: result.duplicateCount == 1
                        ? "That wallpaper was already in OpenVale."
                        : "\(result.duplicateCount) wallpapers were already in OpenVale."
                )
            }
        }
    }

    @objc private func addWallpapers() {
        presentWallpaperPanel()
    }

    @objc private func toggleAutomaticRotation() {
        rotationMode = rotationMode == .daily ? .manual : .daily
        if rotationMode == .manual, let currentWallpaper = currentWallpaper {
            UserDefaults.standard.set(currentWallpaper.id, forKey: DefaultsKey.manualWallpaperID)
        }
        applyScheduledWallpaper(force: true)
    }

    @objc private func selectWallpaper(_ sender: NSMenuItem) {
        guard
            let id = sender.representedObject as? String,
            let wallpaper = wallpapers.first(where: { $0.id == id })
        else { return }

        rotationMode = .manual
        UserDefaults.standard.set(wallpaper.id, forKey: DefaultsKey.manualWallpaperID)
        apply(wallpaper)
    }

    @objc private func nextWallpaper() {
        guard !wallpapers.isEmpty else { return }
        let currentIndex = currentWallpaper.flatMap { wallpapers.firstIndex(of: $0) } ?? -1
        let nextIndex = (currentIndex + 1) % wallpapers.count
        let wallpaper = wallpapers[nextIndex]

        rotationMode = .manual
        UserDefaults.standard.set(wallpaper.id, forKey: DefaultsKey.manualWallpaperID)
        apply(wallpaper)
    }

    @objc private func togglePlayback() {
        wallpaperController.toggleManualPause()
    }

    @objc private func revealCurrentWallpaper() {
        guard let wallpaper = currentWallpaper else { return }
        NSWorkspace.shared.activateFileViewerSelecting([wallpaper.url])
    }

    @objc private func openWallpapersFolder() {
        do {
            try library.prepare()
            NSWorkspace.shared.open(library.directoryURL)
        } catch {
            presentErrorAlert(title: "Couldn’t Open Wallpapers", message: error.localizedDescription)
        }
    }

    @objc private func removeCurrentWallpaper() {
        guard let wallpaper = currentWallpaper else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Remove \(wallpaper.title)?"
        alert.informativeText = "The video will be moved to the Trash, where it can be recovered."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        prepareModalWindow(alert.window)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try library.moveToTrash(wallpaper)
            currentWallpaper = nil
            Task { @MainActor [weak self] in
                await self?.reloadLibraryAndApplySelection(force: true)
            }
        } catch {
            presentErrorAlert(title: "Couldn’t Remove Wallpaper", message: error.localizedDescription)
        }
    }

    @objc private func openSpringMeadowPage() {
        guard let url = URL(string: "https://motionbgs.com/spring-meadow") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LoginItemController.setEnabled(!LoginItemController.isEnabled)
        } catch {
            presentErrorAlert(
                title: "Couldn’t Update Login Setting",
                message: error.localizedDescription
            )
        }
    }

    @objc private func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    @objc private func systemDidWake() {
        if rotationMode == .daily {
            applyScheduledWallpaper(force: true)
        }
        scheduleNextDailyRefresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func presentInformationAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        prepareModalWindow(alert.window)
        alert.runModal()
    }

    private func presentErrorAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        prepareModalWindow(alert.window)
        alert.runModal()
    }

    private func prepareModalWindow(_ window: NSWindow) {
        NSRunningApplication.current.activate(options: [
            .activateAllWindows,
            .activateIgnoringOtherApps
        ])
        window.level = .floating
        window.collectionBehavior.insert(.canJoinAllSpaces)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
