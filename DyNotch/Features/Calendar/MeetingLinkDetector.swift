import Foundation

/// Finds online-meeting links (Zoom, Meet, Teams, Webex, FaceTime) in calendar event fields.
nonisolated enum MeetingLinkDetector {
    enum Service: String, Sendable {
        case zoom = "Zoom"
        case meet = "Google Meet"
        case teams = "Microsoft Teams"
        case webex = "Webex"
        case faceTime = "FaceTime"
    }

    private static let patterns: [(Service, String)] = [
        (.zoom, #"https://(?:[\w-]+\.)*zoom\.us/(?:j|my|w|s)/[^\s<>"')\]]+"#),
        (.meet, #"https://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}[^\s<>"')\]]*"#),
        (.teams, #"https://teams\.(?:microsoft|live)\.com/(?:l/meetup-join|meet)/[^\s<>"')\]]+"#),
        (.webex, #"https://(?:[\w-]+\.)*webex\.com/(?:meet|join|[\w-]+/j\.php)[^\s<>"')\]]*"#),
        (.faceTime, #"https://facetime\.apple\.com/join[^\s<>"')\]]+"#),
    ]

    /// Checks fields in order (event URL, location, notes) and returns the first meeting link.
    static func find(in fields: [String?]) -> (service: Service, url: URL)? {
        for field in fields.compactMap({ $0 }) where !field.isEmpty {
            for (service, pattern) in patterns {
                guard let range = field.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
                var link = String(field[range])
                // Trailing punctuation from prose ("join here: https://...zoom.us/j/123.")
                while let last = link.last, ".,;:".contains(last) { link.removeLast() }
                if let url = URL(string: link) { return (service, url) }
            }
        }
        return nil
    }
}
