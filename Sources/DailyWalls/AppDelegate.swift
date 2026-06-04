import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var bingMenuItem: NSMenuItem!
    private var spotlightMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.log("DailyWalls started.")

        setupStatusItem()
        registerSystemObservers()
        // Trigger a check on launch (e.g. if the app was manually re-opened)
        WallpaperManager.shared.refreshIfNeeded()
    }

    // MARK: - Menu Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            // Try bundled icon first, fall back to SF Symbol
            if let iconImage = loadMenuBarIcon() {
                button.image = iconImage
            } else {
                button.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "Wallpaper Rotation")
            }
            button.image?.isTemplate = true  // Adapts to dark/light menu bar automatically
            button.toolTip = "DailyWalls"
        }

        statusItem.menu = buildMenu()
    }

    private func loadMenuBarIcon() -> NSImage? {
        guard let url = Bundle.module.url(forResource: "menubar_icon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        // Scale to standard menu bar height (18pt)
        let size = NSSize(width: 18, height: 18)
        let resized = NSImage(size: size)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver, fraction: 1.0)
        resized.unlockFocus()
        return resized
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Source selection — mutually exclusive
        bingMenuItem = NSMenuItem(
            title: "Bing",
            action: #selector(selectBing),
            keyEquivalent: ""
        )
        bingMenuItem.target = self

        spotlightMenuItem = NSMenuItem(
            title: "Spotlight",
            action: #selector(selectSpotlight),
            keyEquivalent: ""
        )
        spotlightMenuItem.target = self

        updateSourceCheckmarks()

        menu.addItem(bingMenuItem)
        menu.addItem(spotlightMenuItem)
        menu.addItem(NSMenuItem.separator())

        // Refresh Now
        let refreshItem = NSMenuItem(
            title: "Refresh Now",
            action: #selector(refreshNow),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        // Exit
        let exitItem = NSMenuItem(
            title: "Exit",
            action: #selector(exitApp),
            keyEquivalent: "q"
        )
        exitItem.target = self
        menu.addItem(exitItem)

        return menu
    }

    private func updateSourceCheckmarks() {
        let current = Preferences.shared.source
        bingMenuItem.state = (current == .bing) ? .on : .off
        spotlightMenuItem.state = (current == .spotlight) ? .on : .off
    }

    // MARK: - Menu Actions

    @objc private func selectBing() {
        Logger.shared.log("Source switched to Bing.")
        Preferences.shared.source = .bing
        Preferences.shared.lastAppliedDate = nil  // Force re-download with new source
        updateSourceCheckmarks()
        WallpaperManager.shared.forceRefresh()
    }

    @objc private func selectSpotlight() {
        Logger.shared.log("Source switched to Spotlight.")
        Preferences.shared.source = .spotlight
        Preferences.shared.lastAppliedDate = nil
        updateSourceCheckmarks()
        WallpaperManager.shared.forceRefresh()
    }

    @objc private func refreshNow() {
        Logger.shared.log("Refresh Now clicked.")
        WallpaperManager.shared.forceRefresh()
    }

    @objc private func exitApp() {
        Logger.shared.log("DailyWalls exiting.")
        NSApplication.shared.terminate(nil)
    }

    // MARK: - System Notifications

    private func registerSystemObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter

        // System wake from sleep
        wsCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        // Screen unlock (e.g. after password prompt)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenDidUnlock),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
    }

    @objc private func systemDidWake(_ notification: Notification) {
        Logger.shared.log("System woke from sleep.")
        WallpaperManager.shared.refreshIfNeeded()
    }

    @objc private func screenDidUnlock(_ notification: Notification) {
        Logger.shared.log("Screen unlocked.")
        WallpaperManager.shared.refreshIfNeeded()
    }

}
