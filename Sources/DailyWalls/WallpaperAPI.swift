import Foundation

/// A normalised daily wallpaper entry (source-independent)
struct WallpaperImage {
    let date: String       // yyyy-MM-dd
    let imageUrl: String   // Direct, full image URL
    let title: String?
    let copyright: String?
}

// MARK: - Bing HPImageArchive models

private struct BingArchiveResponse: Decodable {
    let images: [BingImage]
}

private struct BingImage: Decodable {
    let startdate: String   // "20260603"
    let urlbase: String     // "/th?id=OHR.SomeName_EN-US1234567890"
    let title: String?
    let copyright: String?
}

// MARK: - Microsoft Spotlight (arc.msn.com) models

private struct SpotlightResponse: Decodable {
    let batchrsp: SpotlightBatch
}

private struct SpotlightBatch: Decodable {
    let items: [SpotlightItem]
}

private struct SpotlightItem: Decodable {
    let item: String   // JSON string — must be decoded again
}

private struct SpotlightAd: Decodable {
    let ad: [String: SpotlightAsset]
}

private struct SpotlightAsset: Decodable {
    let t: String    // "img" | "txt"
    let u: String?   // URL (images only)
    let tx: String?  // Text value (text assets only)
}

// MARK: - Unified API client

/// Fetches today's wallpaper metadata from official Microsoft/Bing sources only.
/// • Bing:      www.bing.com/HPImageArchive.aspx  (official, no bot protection)
/// • Spotlight: arc.msn.com/v3/Delivery/Placement (official Windows lock-screen endpoint)
final class WallpaperAPI {
    static let shared = WallpaperAPI()
    private init() {}

    // MARK: - Locale helpers

    /// Bing market identifier, e.g. "en-US", "zh-CN", "de-DE"
    private var bingMarket: String {
        let lang   = Locale.current.language.languageCode?.identifier ?? "en"
        let region = Locale.current.region?.identifier ?? "US"
        return "\(lang)-\(region)"
    }

    /// Returns (locale string, country code) for Spotlight, e.g. ("en-US", "US")
    private var spotlightLocale: (String, String) {
        let lang   = Locale.current.language.languageCode?.identifier ?? "en"
        let region = Locale.current.region?.identifier ?? "US"
        return ("\(lang)-\(region)", region)
    }

    // MARK: - Public API

    func fetchTodayImage(source: WallpaperSource) async throws -> WallpaperImage {
        switch source {
        case .bing:      return try await fetchBing()
        case .spotlight: return try await fetchSpotlight()
        }
    }

    // MARK: - Bing via HPImageArchive (official)

    /// Uses the same JSON endpoint that Bing.com itself uses to populate its homepage.
    /// • idx=0  → today's image
    /// • n=1    → one image
    /// • mkt=   → locale market (e.g. en-US)
    /// Image URL is constructed from `urlbase` + "_UHD.jpg" for maximum resolution.
    private func fetchBing() async throws -> WallpaperImage {
        let market = bingMarket
        let urlString = "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=\(market)"
        guard let url = URL(string: urlString) else {
            throw WallpaperAPIError.invalidURL(urlString)
        }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.setValue("DailyWalls/1.0 (macOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTP(response, source: "Bing HPImageArchive")

        let archive = try JSONDecoder().decode(BingArchiveResponse.self, from: data)
        guard let first = archive.images.first else {
            throw WallpaperAPIError.emptyFeed("Bing HPImageArchive")
        }

        // urlbase is a relative path like "/th?id=OHR.SomeName_EN-US1234"
        // Append "_UHD.jpg" for the highest available resolution (up to 3840×2160)
        let imageUrl = "https://www.bing.com\(first.urlbase)_UHD.jpg"

        // Convert startdate "20260603" → "2026-06-03"
        let date = formatBingDate(first.startdate)

        return WallpaperImage(date: date, imageUrl: imageUrl, title: first.title, copyright: first.copyright)
    }

    /// Converts Bing's compact date format "20260603" to "2026-06-03"
    private func formatBingDate(_ raw: String) -> String {
        guard raw.count == 8 else { return raw }
        let y = raw.prefix(4)
        let m = raw.dropFirst(4).prefix(2)
        let d = raw.dropFirst(6).prefix(2)
        return "\(y)-\(m)-\(d)"
    }

    // MARK: - Spotlight via arc.msn.com (official)

    /// Official Windows Spotlight delivery endpoint.
    /// pid=338387 is the landscape lock-screen placement.
    /// lo=80217, disphorzres/vertres=9999 are required for the server to return content.
    private func fetchSpotlight() async throws -> WallpaperImage {
        let (locale, country) = spotlightLocale
        let now = ISO8601DateFormatter().string(from: Date())
        let urlString = "https://arc.msn.com/v3/Delivery/Placement"
            + "?pid=338387&fmt=json&rafb=0&ua=WindowsShellClient%2F0"
            + "&cdm=1&disphorzres=9999&dispvertres=9999&lo=80217"
            + "&pl=\(locale)&lc=\(locale)&ctry=\(country)"
            + "&time=\(now)"
        guard let url = URL(string: urlString) else {
            throw WallpaperAPIError.invalidURL(urlString)
        }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.setValue("WindowsShellClient/0 (Windows)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTP(response, source: "Microsoft Spotlight")

        // items[].item is itself a JSON-encoded string — decode twice
        let outer = try JSONDecoder().decode(SpotlightResponse.self, from: data)
        guard let firstItem = outer.batchrsp.items.first else {
            throw WallpaperAPIError.emptyFeed("Microsoft Spotlight")
        }
        guard let innerData = firstItem.item.data(using: .utf8) else {
            throw WallpaperAPIError.malformedData("Spotlight inner JSON is not valid UTF-8")
        }
        let ad = try JSONDecoder().decode(SpotlightAd.self, from: innerData)

        guard let landscapeAsset = ad.ad["image_fullscreen_001_landscape"],
              landscapeAsset.t == "img",
              let imageUrl = landscapeAsset.u else {
            throw WallpaperAPIError.malformedData("No landscape image asset in Spotlight response")
        }

        let title = ad.ad["hs1_title_text"]?.tx
        let today = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date()) }()

        return WallpaperImage(date: today, imageUrl: imageUrl, title: title, copyright: nil)
    }

    // MARK: - Helpers

    private func validateHTTP(_ response: URLResponse, source: String) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode != 200 else { return }
        throw WallpaperAPIError.httpError(http.statusCode, source)
    }
}

// MARK: - Errors

enum WallpaperAPIError: LocalizedError {
    case invalidURL(String)
    case httpError(Int, String)
    case emptyFeed(String)
    case malformedData(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):        return "Invalid URL: \(url)"
        case .httpError(let c, let s):    return "HTTP \(c) from \(s)"
        case .emptyFeed(let s):           return "\(s) returned an empty feed"
        case .malformedData(let msg):     return "Malformed response: \(msg)"
        }
    }
}
