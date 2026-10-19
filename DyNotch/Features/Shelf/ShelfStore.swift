import AppKit
import CoreTransferable
import Observation
import UniformTypeIdentifiers

nonisolated struct ShelfItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var bookmark: Data
    var name: String
    var addedAt: Date
    /// Files DyNotch created itself (dropped images/text); deleted when removed.
    var isOwnedCopy: Bool
}

/// A shelf item dragged out: a reference to the file itself, so Finder copies the original.
nonisolated struct ShelfFile: Transferable, Identifiable, Sendable {
    let id: UUID
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.url)
    }
}

/// Files parked in the notch. Stores bookmarks so items survive renames and relaunches.
@Observable
final class ShelfStore {
    private(set) var items: [ShelfItem] = []

    @ObservationIgnored private var urlCache: [UUID: URL] = [:]
    /// What was added last, and when: the Shelf selects it as it opens.
    @ObservationIgnored private var recentlyAdded: (ids: [UUID], at: Date) = ([], .distantPast)

    /// Where the shelf keeps its list and the files it saved itself.
    private let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("shelf.json") }
    private var ownedFilesDirectory: URL { directory.appendingPathComponent("Shelf", isDirectory: true) }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DyNotch", isDirectory: true)
    }

    static let acceptedTypes: [UTType] = [.fileURL, .image, .plainText, .url]

    init(directory: URL = ShelfStore.defaultDirectory) {
        self.directory = directory
        load()
    }

    func url(for item: ShelfItem) -> URL? {
        if let cached = urlCache[item.id] { return cached }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: item.bookmark, options: [.withoutUI], bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        urlCache[item.id] = url
        return url
    }

    var urls: [URL] { items.compactMap(url(for:)) }

    /// The files of the items with `ids`, in that order, skipping any that are gone.
    func urls(for ids: [UUID]) -> [URL] {
        ids.compactMap { id in items.first { $0.id == id }.flatMap(url(for:)) }
    }

    /// Adds files that aren't on the shelf yet, before the item at `index` (at the end by default).
    @discardableResult
    func add(_ urls: [URL], owned: Bool = false, at index: Int? = nil) -> [UUID] {
        let existing = Set(self.urls.map(\.standardizedFileURL))
        let new = urls
            .filter { !existing.contains($0.standardizedFileURL) }
            .compactMap { url -> ShelfItem? in
                guard let bookmark = try? url.bookmarkData() else { return nil }
                return ShelfItem(id: UUID(), bookmark: bookmark, name: url.lastPathComponent, addedAt: .now, isOwnedCopy: owned)
            }
        guard !new.isEmpty else { return [] }
        items.insert(contentsOf: new, at: min(index ?? items.count, items.count))
        recentlyAdded = (new.map(\.id), .now)
        save()
        return new.map(\.id)
    }

    /// The items added in the last few seconds that are still here, once: the Shelf selects
    /// them as it opens, as Finder selects what was just copied in.
    func takeRecentlyAdded() -> [UUID] {
        defer { recentlyAdded = ([], .distantPast) }
        guard Date.now.timeIntervalSince(recentlyAdded.at) < 5 else { return [] }
        return items.map(\.id).filter(recentlyAdded.ids.contains)
    }

    /// Adds whatever was dropped: files, images or text (saved as files), before the item at
    /// `index` (at the end by default).
    func add(providers: [NSItemProvider], at index: Int? = nil) async {
        var files: [URL] = []
        var owned: [URL] = []
        for provider in providers {
            if let url = await Self.fileURL(from: provider) {
                files.append(url)
            } else if let url = await saveDroppedContent(from: provider) {
                owned.append(url)
            }
        }
        // Files the shelf already holds are skipped, so count only the new ones for the owned copies.
        let before = items.count
        let added = add(files, at: index)
        let saved = add(owned, owned: true, at: index.map { $0 + items.count - before })
        recentlyAdded = (added + saved, .now)
    }

    /// Moves the items with `ids`, keeping their order, so they sit before the item now at
    /// `index` (`items.count` for the end).
    func move(_ ids: Set<UUID>, to index: Int) {
        let moving = items.filter { ids.contains($0.id) }
        guard !moving.isEmpty else { return }
        var rest = items.filter { !ids.contains($0.id) }
        let position = items.prefix(max(0, index)).filter { !ids.contains($0.id) }.count
        rest.insert(contentsOf: moving, at: position)
        guard rest.map(\.id) != items.map(\.id) else { return }
        items = rest
        save()
    }

    func remove(_ ids: Set<UUID>) {
        for item in items where ids.contains(item.id) {
            if item.isOwnedCopy, let url = url(for: item) {
                try? FileManager.default.removeItem(at: url)
            }
            urlCache[item.id] = nil
        }
        items.removeAll { ids.contains($0.id) }
        save()
    }

    func removeAll() {
        items.forEach { if $0.isOwnedCopy, let url = url(for: $0) { try? FileManager.default.removeItem(at: url) } }
        items = []
        urlCache = [:]
        save()
    }

    /// Drops items whose files were deleted.
    func prune() {
        let before = items.count
        items.removeAll { url(for: $0) == nil }
        if items.count != before { save() }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([ShelfItem].self, from: data)
        else { return }
        items = decoded
        prune()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    // MARK: - Item providers

    private static func data(from provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: type) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    static func fileURL(from provider: NSItemProvider) async -> URL? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let data = await data(from: provider, type: .fileURL),
           let url = URL(dataRepresentation: data, relativeTo: nil),
           url.isFileURL {
            return url
        }
        // Files dragged from Finder arrive as an open-in-place representation of the
        // file's own type (e.g. net.daringfireball.markdown), without public.file-url.
        for type in provider.registeredContentTypesForOpenInPlace {
            if let url = await inPlaceFileURL(from: provider, type: type) { return url }
        }
        return nil
    }

    /// The files among `providers`, skipping anything that isn't one.
    static func fileURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let url = await fileURL(from: provider) { urls.append(url) }
        }
        return urls
    }

    /// The original file's URL, or nil when the provider could only hand over a temporary copy.
    private static func inPlaceFileURL(from provider: NSItemProvider, type: UTType) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(for: type, openInPlace: true) { url, isInPlace, _ in
                continuation.resume(returning: isInPlace ? url : nil)
            }
        }
    }

    private func saveDroppedContent(from provider: NSItemProvider) async -> URL? {
        try? FileManager.default.createDirectory(at: ownedFilesDirectory, withIntermediateDirectories: true)
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: ".")

        if let imageType = provider.registeredContentTypes.first(where: { $0.conforms(to: .image) }),
           let data = await Self.data(from: provider, type: imageType) {
            let url = ownedFilesDirectory.appendingPathComponent(String(localized: "Image \(stamp)", comment: "Name of an image file dropped on the Shelf") + ".\(imageType.preferredFilenameExtension ?? "png")")
            return (try? data.write(to: url)) != nil ? url : nil
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let data = await Self.data(from: provider, type: .url),
           let link = URL(dataRepresentation: data, relativeTo: nil) {
            let url = ownedFilesDirectory.appendingPathComponent(String(localized: "Link \(stamp)", comment: "Name of a link file dropped on the Shelf") + ".webloc")
            let plist = try? PropertyListSerialization.data(fromPropertyList: ["URL": link.absoluteString], format: .xml, options: 0)
            return (try? plist?.write(to: url)) != nil ? url : nil
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let data = await Self.data(from: provider, type: .plainText) {
            let url = ownedFilesDirectory.appendingPathComponent(String(localized: "Text \(stamp)", comment: "Name of a text file dropped on the Shelf") + ".txt")
            return (try? data.write(to: url)) != nil ? url : nil
        }
        return nil
    }
}

enum AirDropService {
    static var isAvailable: Bool { NSSharingService(named: .sendViaAirDrop) != nil }

    static func send(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        ShelfSharing.shared.perform(service, with: urls)
    }

    /// Resolves dropped providers to file URLs (saving non-file content first) and sends them.
    static func send(providers: [NSItemProvider], store: ShelfStore) async {
        send(await ShelfStore.fileURLs(from: providers))
    }
}
