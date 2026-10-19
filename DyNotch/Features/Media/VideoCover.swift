import AppKit

/// Covers for videos that play without one. Safari hands Now Playing a YouTube video's title
/// and channel but never its artwork (measured on macOS 27, normal and private windows alike),
/// so the player showed the plain music note. The page's address names the video, and YouTube
/// serves a thumbnail for every video.
nonisolated enum VideoCover {
    /// Apps whose windows are read for the page that's playing.
    static let browsers: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]

    /// The page title can follow the Now Playing title a moment later when the next video
    /// opens, so the windows are read again a few times before giving up.
    private static let attempts: [Duration] = [.zero, .milliseconds(500), .seconds(1), .seconds(2)]

    /// No cookies, nothing left on disk: the video may be playing in a private window.
    private static let session = URLSession(configuration: .ephemeral)

    /// The thumbnail of the video titled `title` that plays in `app`, if one of its windows
    /// shows the video's page.
    static func find(title: String, app: String) async -> Data? {
        for delay in attempts {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return nil }
            let pages = await Task.detached { BrowserPages.frontPages(of: app) }.value
            if let page = BrowserPages.page(playing: title, among: pages), let url = thumbnailURL(forPage: page.url) {
                return await download(url)
            }
        }
        return nil
    }

    /// The thumbnail for a video page, or `nil` if the page isn't one.
    static func thumbnailURL(forPage page: URL) -> URL? {
        // 320×180 without letterboxing, made for every video. The largest cover is 58 points.
        youTubeID(in: page).flatMap { URL(string: "https://i.ytimg.com/vi/\($0)/mqdefault.jpg") }
    }

    static func youTubeID(in url: URL) -> String? {
        guard let host = url.host()?.lowercased() else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        let id: String?
        if host == "youtu.be" {
            id = path.first
        } else if ["youtube.com", "youtube-nocookie.com"].contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            if path.first == "watch" {
                id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value
            } else if path.count >= 2, ["shorts", "live", "embed"].contains(path[0]) {
                id = path[1]
            } else {
                id = nil
            }
        } else {
            id = nil
        }
        guard let id, id.count == 11,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return nil }
        return id
    }

    private static func download(_ url: URL) async -> Data? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }
}

/// The pages a browser's windows show, read over Accessibility. Only the tab in front of each
/// window has its address there; the tab bar names the others without one.
nonisolated enum BrowserPages {
    nonisolated struct Page: Equatable, Sendable {
        var windowTitle: String
        var title: String
        var url: URL
    }

    /// The page playing a video titled `title`. A private window reports the title blank, and
    /// adds to the page title in its window's (", Private Browsing"), so then the video is the
    /// one in a private window, as long as only one shows a video.
    static func page(playing title: String, among pages: [Page]) -> Page? {
        if !title.isEmpty {
            return pages.first { $0.title.contains(title) }
        }
        let candidates = pages.filter { page in
            !page.title.isEmpty && page.windowTitle.count > page.title.count && page.windowTitle.hasPrefix(page.title)
                && VideoCover.thumbnailURL(forPage: page.url) != nil
        }
        return candidates.count == 1 ? candidates.first : nil
    }

    /// The page in front in each of `bundleIdentifier`'s windows.
    static func frontPages(of bundleIdentifier: String) -> [Page] {
        guard AXIsProcessTrusted(),
              let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first?.processIdentifier
        else { return [] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        let windows: [AXUIElement] = app.attribute(kAXWindowsAttribute) ?? []
        return windows.compactMap { window in
            guard let area = webArea(in: window), let url: URL = area.attribute(kAXURLAttribute) else { return nil }
            let windowTitle: String = window.attribute(kAXTitleAttribute) ?? ""
            let title: String = area.attribute(kAXDescriptionAttribute) ?? ""
            return Page(windowTitle: windowTitle, title: title.isEmpty ? windowTitle : title, url: url)
        }
    }

    /// Containers on the way down to the page; the toolbar, tab bar and sidebar are skipped.
    private static let containers: Set<String> = [kAXSplitGroupRole, kAXTabGroupRole, kAXGroupRole, kAXScrollAreaRole]

    /// The page in front: Safari's sits six levels below its window.
    private static func webArea(in window: AXUIElement) -> AXUIElement? {
        var level = [window]
        for _ in 0..<8 {
            var next: [AXUIElement] = []
            for element in level {
                for child in element.attribute(kAXChildrenAttribute) as [AXUIElement]? ?? [] {
                    guard let role: String = child.attribute(kAXRoleAttribute) else { continue }
                    if role == "AXWebArea" { return child }
                    if containers.contains(role) { next.append(child) }
                }
            }
            level = next
        }
        return nil
    }
}
