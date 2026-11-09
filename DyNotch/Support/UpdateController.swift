import AppKit
import SwiftUI

/// Looks for a new release once every 30 days and, when there is one, shows a window offering
/// to download it and restart into it. A check that finds nothing, or fails, shows nothing.
@Observable
final class UpdateController {
    static let shared = UpdateController()

    static let checkInterval: TimeInterval = 30 * 86_400

    enum Phase: Equatable {
        case available
        case downloading(Double)
        case installing
        case failed(String)
    }

    private(set) var release: UpdateChecker.Release?
    private(set) var phase = Phase.available

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

    @ObservationIgnored private var window: NSWindow?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var isChecking = false
    @ObservationIgnored private var installTask: Task<Void, Never>?

    private static let lastCheckKey = "lastUpdateCheck"

    /// When GitHub last answered a check, automatic or from Settings.
    var lastCheck: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastCheckKey) }
    }

    static func isCheckDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck, lastCheck <= now else { return true }
        return now.timeIntervalSince(lastCheck) >= checkInterval
    }

    // MARK: Automatic checks

    /// Checks shortly after launch if one is due, then every few hours for Macs that stay on for weeks.
    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            MainActor.assumeIsolated { UpdateController.shared.checkIfDue() }
        }
        Task {
            try? await Task.sleep(for: .seconds(10))
            checkIfDue()
        }
    }

    func checkIfDue() {
        let settings = AppSettings.shared
        guard settings.checkForUpdatesAutomatically,
              // Not on top of the welcome tour: the next timer tick asks again.
              settings.hasCompletedOnboarding, settings.tourStepToResume == nil,
              window?.isVisible != true, !isChecking,
              Self.isCheckDue(lastCheck: lastCheck, now: .now) else { return }
        isChecking = true
        Task {
            defer { isChecking = false }
            do {
                let found = try await UpdateChecker.newerRelease(than: currentVersion)
                lastCheck = .now
                if let found { show(found) }
            } catch {
                // A failed check stays due, so it's tried again at the next tick or launch.
            }
        }
    }

    // MARK: The window

    func show(_ release: UpdateChecker.Release) {
        if !isBusy {
            self.release = release
            phase = .available
        }
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: UpdateView.width, height: 200),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            let host = NSHostingController(rootView: UpdateView(controller: self))
            host.sizingOptions = .preferredContentSize
            window.contentViewController = host
            window.title = String(localized: "Software Update")
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = WindowDelegate.shared
            self.window = window
        }
        guard let window else { return }
        if !window.isVisible {
            window.layoutIfNeeded()
            window.center()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func close() {
        window?.close()
    }

    private var isBusy: Bool {
        switch phase {
        case .downloading, .installing: true
        default: false
        }
    }

    fileprivate func windowWillClose() {
        installTask?.cancel()
        installTask = nil
        if phase != .installing { phase = .available }
    }

    private final class WindowDelegate: NSObject, NSWindowDelegate {
        static let shared = WindowDelegate()
        func windowWillClose(_ notification: Notification) {
            UpdateController.shared.windowWillClose()
        }
    }

    // MARK: Installing

    /// Whether DyNotch can swap its own app bundle for the new one: it isn't run from a
    /// read-only or translocated copy, and the release comes as a disk image.
    var canInstallInPlace: Bool {
        guard release?.hasDiskImage == true else { return false }
        let app = Bundle.main.bundleURL
        guard !app.path.contains("/AppTranslocation/") else { return false }
        let files = FileManager.default
        return files.isWritableFile(atPath: app.path) && files.isWritableFile(atPath: app.deletingLastPathComponent().path)
    }

    func openReleasePage() {
        if let release { NSWorkspace.shared.open(release.page) }
    }

    func downloadManually() {
        if let release { NSWorkspace.shared.open(release.download) }
        close()
    }

    func installAndRestart() {
        guard let release, !isBusy else { return }
        guard canInstallInPlace else { return downloadManually() }
        phase = .downloading(0)
        installTask = Task {
            do {
                try await install(release)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed((error as? InstallError)?.message ?? String(localized: "The download didn't finish. Check your internet connection and try again."))
            }
        }
    }

    private struct InstallError: Error {
        let message: String
    }

    private func install(_ release: UpdateChecker.Release) async throws {
        let files = FileManager.default
        let app = Bundle.main.bundleURL
        // On the app's own volume, so moving the new copy into place is a rename.
        let work = try files.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true)
        var keepWork = false
        defer { if !keepWork { try? files.removeItem(at: work) } }

        let image = work.appending(path: "DyNotch.dmg")
        try await download(release.download, to: image)
        try Task.checkCancellation()

        phase = .installing
        // Not inside `work`: macOS refuses to list a volume mounted in TemporaryItems.
        let mount = files.temporaryDirectory.appending(path: "DyNotch-Update-\(UUID().uuidString)")
        try files.createDirectory(at: mount, withIntermediateDirectories: true)
        let staged = work.appending(path: app.lastPathComponent)
        let copied: Result<Void, Error>
        do {
            try await run("/usr/bin/hdiutil", ["attach", image.path, "-nobrowse", "-readonly", "-noautoopen", "-noverify", "-mountpoint", mount.path])
            let found = try files.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)
                .first { $0.pathExtension == "app" && Bundle(url: $0)?.bundleIdentifier == Bundle.main.bundleIdentifier }
            guard let found else {
                throw InstallError(message: String(localized: "The download doesn't contain DyNotch."))
            }
            try await run("/usr/bin/ditto", [found.path, staged.path])
            copied = .success(())
        } catch {
            copied = .failure(error)
        }
        try? await run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
        // Removes only an empty folder, so never the volume's contents if it's still attached.
        rmdir(mount.path)
        try copied.get()

        let version = Bundle(url: staged)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard UpdateChecker.isVersion(version, newerThan: currentVersion) else {
            throw InstallError(message: String(localized: "The download isn't a newer version of DyNotch."))
        }
        do {
            try await run("/usr/bin/codesign", ["--verify", "--deep", staged.path])
        } catch {
            throw InstallError(message: String(localized: "The download is damaged. Try again."))
        }
        try Task.checkCancellation()

        // Once DyNotch has quit, swap the bundles (putting the old one back if that fails) and open the new one.
        let script = #"""
        pid="$1"; new="$2"; app="$3"; work="$4"
        while /bin/kill -0 "$pid" 2>/dev/null; do /bin/sleep 0.2; done
        if /bin/mv "$app" "$work/Old.app"; then
            /bin/mv "$new" "$app" || /bin/mv "$work/Old.app" "$app"
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$app" 2>/dev/null
        /usr/bin/open "$app"
        /bin/rm -rf "$work"
        """#
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), staged.path, app.path, work.path]
        try process.run()
        keepWork = true
        NSApp.terminate(nil)
    }

    private func download(_ url: URL, to destination: URL) async throws {
        let delegate = DownloadDelegate(destination: destination)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: url)
        let progress = task.progress.observe(\.fractionCompleted) { progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in
                let controller = UpdateController.shared
                if case .downloading = controller.phase { controller.phase = .downloading(fraction) }
            }
        }
        defer { progress.invalidate() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                delegate.continuation = continuation
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    /// Moves the downloaded file into place before URLSession deletes it.
    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let destination: URL
        private let lock = NSLock()
        private var _continuation: CheckedContinuation<Void, Error>?
        var continuation: CheckedContinuation<Void, Error>? {
            get { lock.withLock { _continuation } }
            set { lock.withLock { _continuation = newValue } }
        }

        init(destination: URL) {
            self.destination = destination
        }

        private func finish(_ result: Result<Void, Error>) {
            let continuation = lock.withLock {
                defer { _continuation = nil }
                return _continuation
            }
            continuation?.resume(with: result)
        }

        nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            do {
                if let response = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
                    throw URLError(.badServerResponse)
                }
                try FileManager.default.moveItem(at: location, to: destination)
                finish(.success(()))
            } catch {
                finish(.failure(error))
            }
        }

        nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
            finish(.failure(error ?? URLError(.unknown)))
        }
    }

    /// Runs a tool and waits for it, throwing if it fails.
    private func run(_ tool: String, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: InstallError(message: String(localized: "DyNotch couldn't install the update. Download it and install it by hand.")))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
