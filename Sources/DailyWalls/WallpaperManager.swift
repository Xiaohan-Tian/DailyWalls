import AppKit
import Foundation

/// Handles downloading wallpaper images and applying them across all screens and spaces.
final class WallpaperManager {
    static let shared = WallpaperManager()

    private let fileManager = FileManager.default
    private let picturesDir: URL
    private var isRefreshing = false

    private init() {
        let home = fileManager.homeDirectoryForCurrentUser
        picturesDir = home.appendingPathComponent("Pictures/ms-wallpapers")
    }

    // MARK: - Public API

    /// Refreshes wallpaper only if today's hasn't been applied yet.
    func refreshIfNeeded() {
        guard !Preferences.shared.isUpToDateForToday else {
            Logger.shared.log("Wallpaper already up to date for today (\(Preferences.shared.todayString())), skipping.")
            return
        }
        Logger.shared.log("Triggering wallpaper refresh (daily check).")
        Task { await performRefresh() }
    }

    /// Always downloads and applies the wallpaper, regardless of cache state.
    func forceRefresh() {
        Logger.shared.log("Force refresh requested.")
        Task { await performRefresh() }
    }

    // MARK: - Core Logic

    @MainActor
    private func performRefresh() async {
        guard !isRefreshing else {
            Logger.shared.log("Refresh already in progress, skipping duplicate trigger.")
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        let source = Preferences.shared.source
        let sourceName = source == .spotlight ? "Microsoft Spotlight" : "Bing (official)"
        Logger.shared.log("Fetching \(sourceName) wallpaper...")

        do {
            let image = try await WallpaperAPI.shared.fetchTodayImage(source: source)
            let credit = image.copyright.map { " — \($0)" } ?? ""
            Logger.shared.log("Got image for \(image.date): \(image.title ?? "(no title)")\(credit)")

            // 2. Download image file
            let localURL = try await downloadImage(image: image, source: source)
            Logger.shared.log("Image saved to \(localURL.path)")

            // 3. Apply to all screens + spaces
            try applyWallpaper(fileURL: localURL)
            Logger.shared.log("Wallpaper applied successfully to all screens.")

            // 4. Record date
            Preferences.shared.lastAppliedDate = Preferences.shared.todayString()

        } catch {

            Logger.shared.log("ERROR: \(error.localizedDescription)")
        }
    }

    // MARK: - Download

    private func downloadImage(image: WallpaperImage, source: WallpaperSource) async throws -> URL {
        guard let remoteURL = URL(string: image.imageUrl) else {
            throw WallpaperError.invalidImageURL(image.imageUrl)
        }

        // Determine file extension
        let ext = remoteURL.pathExtension.isEmpty ? "jpg" : remoteURL.pathExtension

        // Build save path: ~/Pictures/ms-wallpapers/{bing|spotlight}/{yyyy-mm-dd}.{ext}
        let destDir = picturesDir.appendingPathComponent(source.rawValue)
        try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
        let destFile = destDir.appendingPathComponent("\(image.date).\(ext)")

        // Return cached file if already downloaded today
        if fileManager.fileExists(atPath: destFile.path) {
            Logger.shared.log("Using cached image at \(destFile.path)")
            return destFile
        }

        Logger.shared.log("Downloading from \(remoteURL.absoluteString)")
        let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw WallpaperError.downloadFailed("HTTP \(httpResponse.statusCode)")
        }

        // Move from temp to destination
        if fileManager.fileExists(atPath: destFile.path) {
            try fileManager.removeItem(at: destFile)
        }
        try fileManager.moveItem(at: tempURL, to: destFile)

        return destFile
    }

    // MARK: - Apply Wallpaper

    private func applyWallpaper(fileURL: URL) throws {
        let workspace = NSWorkspace.shared
        var errors: [Error] = []

        // Apply to every connected screen (covers the active space on each display)
        for screen in NSScreen.screens {
            do {
                // Using empty options dict — NSWorkspace will use the existing display options
                try workspace.setDesktopImageURL(fileURL, for: screen, options: [:])
            } catch {
                errors.append(error)
                Logger.shared.log("Warning: failed to set wallpaper on screen '\(screen.localizedName)': \(error.localizedDescription)")
            }
        }

        // Also use osascript as a belt-and-suspenders approach to cover all Spaces
        applyViaAppleScript(fileURL: fileURL)

        if errors.count == NSScreen.screens.count {
            throw WallpaperError.allScreensFailed
        }
    }

    /// Uses AppleScript to set the wallpaper on every desktop/space (works across inactive spaces).
    private func applyViaAppleScript(fileURL: URL) {
        let posixPath = fileURL.path
        let script = """
        tell application "System Events"
            set theDesktops to every desktop
            repeat with aDesktop in theDesktops
                set picture of aDesktop to "\(posixPath.replacingOccurrences(of: "\"", with: "\\\""))"
            end repeat
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let err = error {
                Logger.shared.log("AppleScript warning: \(err)")
            }
        }
    }
}

enum WallpaperError: LocalizedError {
    case invalidImageURL(String)
    case downloadFailed(String)
    case allScreensFailed

    var errorDescription: String? {
        switch self {
        case .invalidImageURL(let url): return "Invalid image URL: \(url)"
        case .downloadFailed(let reason): return "Download failed: \(reason)"
        case .allScreensFailed: return "Failed to set wallpaper on any screen"
        }
    }
}
