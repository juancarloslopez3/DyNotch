import Foundation

/// New versions of DyNotch are GitHub releases, tagged with their version ("1.1" or "v1.1").
/// GitHub is only asked when Check for Updates is pressed in Settings › About.
nonisolated enum UpdateChecker {
    static let repository = URL(string: "https://github.com/juancarloslopez3/DyNotch")!
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/juancarloslopez3/DyNotch/releases/latest")!

    struct Release: Equatable, Sendable {
        let version: String
        /// The release's page on GitHub, with its notes.
        let page: URL
        /// The disk image attached to the release, else its page.
        let download: URL
    }

    private struct LatestRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let html_url: URL
        let assets: [Asset]
    }

    /// The latest release if it's newer than `current`, else `nil`.
    static func newerRelease(than current: String) async throws -> Release? {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: return try newerRelease(in: data, than: current)
        // GitHub answers 404 while nothing has been released yet.
        case 404: return nil
        default: throw URLError(.badServerResponse)
        }
    }

    static func newerRelease(in data: Data, than current: String) throws -> Release? {
        let latest = try JSONDecoder().decode(LatestRelease.self, from: data)
        let version = String(latest.tag_name.trimmingPrefix { $0 == "v" || $0 == "V" })
        guard isVersion(version, newerThan: current) else { return nil }
        let image = latest.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
        return Release(version: version, page: latest.html_url, download: image?.browser_download_url ?? latest.html_url)
    }

    /// Compares dotted versions part by part, so 1.10 is newer than 1.9 and 1.0 is the same as 1.
    static func isVersion(_ version: String, newerThan current: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            version.split(separator: ".").map { Int($0.prefix { $0.isASCII && $0.isNumber }) ?? 0 }
        }
        let new = parts(version), old = parts(current)
        for index in 0..<max(new.count, old.count) {
            let a = index < new.count ? new[index] : 0
            let b = index < old.count ? old[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}
