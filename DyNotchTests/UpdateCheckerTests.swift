import Foundation
import Testing

@testable import DyNotch

struct UpdateCheckerTests {
    @Test func comparesVersionsPartByPart() {
        #expect(UpdateChecker.isVersion("1.1", newerThan: "1.0"))
        #expect(UpdateChecker.isVersion("1.10", newerThan: "1.9"))
        #expect(UpdateChecker.isVersion("2", newerThan: "1.9.9"))
        #expect(UpdateChecker.isVersion("1.0.1", newerThan: "1"))
        #expect(!UpdateChecker.isVersion("1.0", newerThan: "1"))
        #expect(!UpdateChecker.isVersion("1.0", newerThan: "1.0"))
        #expect(!UpdateChecker.isVersion("0.9", newerThan: "1.0"))
    }

    @Test func findsNewerReleaseAndItsDiskImage() throws {
        let json = """
        {
          "tag_name": "v1.2",
          "html_url": "https://github.com/juancarloslopez3/DyNotch/releases/tag/v1.2",
          "assets": [
            {"name": "notes.txt", "browser_download_url": "https://example.com/notes.txt"},
            {"name": "DyNotch-1.2.dmg", "browser_download_url": "https://example.com/DyNotch-1.2.dmg"}
          ]
        }
        """
        let release = try #require(try UpdateChecker.newerRelease(in: Data(json.utf8), than: "1.0"))
        #expect(release.version == "1.2")
        #expect(release.download.lastPathComponent == "DyNotch-1.2.dmg")
        #expect(release.hasDiskImage)
        #expect(release.notes.isEmpty)
        #expect(try UpdateChecker.newerRelease(in: Data(json.utf8), than: "1.2") == nil)
    }

    @Test func fallsBackToReleasePageWithoutDiskImage() throws {
        let json = """
        {"tag_name": "1.1", "html_url": "https://github.com/juancarloslopez3/DyNotch/releases/tag/1.1", "assets": []}
        """
        let release = try #require(try UpdateChecker.newerRelease(in: Data(json.utf8), than: "1.0"))
        #expect(release.download == release.page)
        #expect(!release.hasDiskImage)
    }

    @Test func readsReleaseNotes() throws {
        let json = """
        {"tag_name": "v1.2", "html_url": "https://example.com/1.2", "body": "Enhancements:\\r\\n\\r\\n- Notch rim.\\r\\n", "assets": []}
        """
        let release = try #require(try UpdateChecker.newerRelease(in: Data(json.utf8), than: "1.1"))
        #expect(release.notes == "Enhancements:\r\n\r\n- Notch rim.")
    }

    @Test func checksAgainAfterThirtyDays() {
        let now = Date()
        #expect(UpdateController.isCheckDue(lastCheck: nil, now: now))
        #expect(!UpdateController.isCheckDue(lastCheck: now.addingTimeInterval(-29 * 86_400), now: now))
        #expect(UpdateController.isCheckDue(lastCheck: now.addingTimeInterval(-30 * 86_400), now: now))
        // A clock set back doesn't put the next check off for good.
        #expect(UpdateController.isCheckDue(lastCheck: now.addingTimeInterval(86_400), now: now))
    }
}
