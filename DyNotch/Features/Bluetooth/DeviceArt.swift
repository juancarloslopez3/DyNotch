import Foundation
import Observation
import OSLog

/// Apple's own pictures of AirPods and Beats, the ones the iPhone shows when they come near: a
/// video of each model turning, in each of its colors. Apple publishes them in a MobileAsset
/// catalog (`SharingDeviceAssets`). DyNotch fetches a model's clip from Apple the first time it's
/// paired or connects (~1.5 MB, out of its archive by `RemoteZip`) and keeps a turntable made from
/// it (~0.3 MB), so none of it ships in the app. One fetched while the model is on screen shows
/// straight away.
@Observable final class DeviceArt {
    static let shared = DeviceArt()

    private static let logger = Logger(subsystem: "app.dynotch", category: "DeviceArt")
    nonisolated private static let catalogURL = URL(string: "https://mesu.apple.com/assets/com_apple_MobileAsset_SharingDeviceAssets/com_apple_MobileAsset_SharingDeviceAssets.xml")!

    /// One folder per model and color ("AirPodsPro1,2-0") with its turntable; the catalog beside
    /// them.
    let directory: URL
    /// How many models were fetched since launch, for views to pick each up as it comes in.
    private(set) var fetches = 0
    /// Folders on their way, so a model is fetched once however often it's asked for.
    @ObservationIgnored private var fetching: [String: Task<Void, Never>] = [:]
    /// The fetch before the newest: fetches go one after another.
    @ObservationIgnored private var lastFetch: Task<Void, Never>?

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DyNotch/DeviceArt", isDirectory: true)) {
        self.directory = directory
    }

    // MARK: - Models

    /// A model as Apple's catalog names it, and how the color ID it reports maps to the catalog's.
    nonisolated struct Product: Equatable, Sendable {
        /// "AirPodsPro1,2".
        let type: String
        /// The color shown when the device's own isn't known or isn't in the catalog.
        var usualColor: Int? = nil
        /// The bits of the color ID that name the color (the USB-C AirPods Max set one above them).
        var colorMask = 0xFF
        var colorOverrides: [Int: Int] = [:]

        /// The catalog's color for a color ID the device reports.
        func color(for colorID: Int?) -> Int? {
            guard let colorID else { return usualColor }
            return colorOverrides[colorID] ?? colorID & colorMask
        }
    }

    /// By Bluetooth product ID (vendor 0x004C): AirBuddy's table, the newer models by the plists
    /// CoreBluetoothUI keeps beside its pictures (`AssetPaths-B788.plist` lists 0x2027) and the
    /// names in HeadphoneAssets (`B788` → `AirPodsPro1-3_translate.png`).
    nonisolated static let products: [Int: Product] = [
        0x2002: Product(type: "AirPods1,1"),
        0x2003: Product(type: "PowerBeats3,1"),
        0x2005: Product(type: "BeatsX1,1"),
        0x2006: Product(type: "BeatsSolo3,1"),
        0x2007: Product(type: "BeatsStudio3,2"),
        0x2009: Product(type: "BeatsStudio3,2"),
        // Space Gray, as macOS pictures them.
        0x200A: Product(type: "AirPodsMax1,1", usualColor: 15),
        0x200B: Product(type: "PowerbeatsPro1,1"),
        0x200C: Product(type: "BeatsSoloPro1,1"),
        0x200D: Product(type: "Powerbeats4,1"),
        0x200E: Product(type: "AirPodsPro1,1"),
        0x200F: Product(type: "AirPods1,2"),
        0x2010: Product(type: "BeatsX2,1"),
        0x2011: Product(type: "BeatsStudioBuds1,1", colorOverrides: [34: 2]),
        0x2012: Product(type: "BeatsFitPro1,1"),
        0x2013: Product(type: "AirPods1,3"),
        0x2014: Product(type: "AirPodsPro1,2"),
        0x2016: Product(type: "BeatsStudioBuds1,2"),
        0x2017: Product(type: "BeatsStudioPro1,1"),
        0x2019: Product(type: "AirPods1,4"),
        0x201A: Product(type: "BeatsPill1,2"),
        0x201B: Product(type: "AirPods1,5"),
        0x201D: Product(type: "PowerbeatsPro2,1"),
        // Starlight, as macOS pictures them.
        0x201F: Product(type: "AirPodsMax1,2", usualColor: 19, colorMask: 0x3F),
        0x2024: Product(type: "AirPodsPro1,2"),
        0x2025: Product(type: "BeatsSolo4,1"),
        0x2026: Product(type: "BeatsSoloBuds1,1"),
        0x2027: Product(type: "AirPodsPro1,3"),
        0x202D: Product(type: "AirPodsMax1,2", usualColor: 19, colorMask: 0x3F),
        0x202F: Product(type: "BeatsFitPro1,1"),
        0x2030: Product(type: "AirPods3,7"),
        0x2032: Product(type: "AirPods3,7"),
        0x2036: Product(type: "AirPods3,7"),
        0x2037: Product(type: "AirPods3,7"),
        0x2038: Product(type: "Beats3601,1"),
    ]

    // MARK: - Pictures

    /// What a model's turntable is called in its folder, after the way it's made: when that changes
    /// (2: earbuds without their case), every model is fetched again.
    nonisolated static let turntableName = "turntable-2.heic"

    /// The model turning a whole way round, in its color where that was fetched.
    func turntable(productID: Int, colorID: Int?) -> Turntable? {
        // Read, so a view without one yet looks again once a fetch comes in.
        _ = fetches
        return turntableURL(productID: productID, colorID: colorID).flatMap(Turntable.load)
    }

    /// The fetched model's turntable: in its color, else the usual one, else any.
    private func turntableURL(productID: Int, colorID: Int?) -> URL? {
        guard let product = Self.products[productID] else { return nil }
        let files = FileManager.default
        func turntable(in folder: String) -> URL? {
            let url = directory.appendingPathComponent(folder, isDirectory: true).appendingPathComponent(Self.turntableName)
            return files.fileExists(atPath: url.path) ? url : nil
        }
        for color in [product.color(for: colorID), product.usualColor].compactMap(\.self) {
            if let url = turntable(in: "\(product.type)-\(color)") { return url }
        }
        let names = (try? files.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix(product.type + "-") }.sorted().lazy.compactMap { turntable(in: $0) }.first
    }

    // MARK: - Fetching

    /// Fetches the model's turntable from Apple in the background, in its color, unless it's here
    /// already. The fetch, nil when there's nothing to fetch.
    @discardableResult
    func prepare(productID: Int, colorID: Int?) -> Task<Void, Never>? {
        guard let product = Self.products[productID] else { return nil }
        let color = product.color(for: colorID)
        let key = "\(product.type)-\(color.map(String.init) ?? "usual")"
        // Here in its color already, or in any when it doesn't say which.
        let isHere = if let color {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(product.type)-\(color)").appendingPathComponent(Self.turntableName).path)
        } else {
            turntableURL(productID: productID, colorID: nil) != nil
        }
        guard !isHere else { return nil }
        if let fetch = fetching[key] { return fetch }
        let previous = lastFetch
        let directory = directory
        let fetch = Task {
            await previous?.value
            do {
                if let name = try await Task.detached(priority: .utility, operation: {
                    try await Self.fetch(product, color: color, into: directory)
                }).value {
                    Self.logger.notice("Fetched \(name, privacy: .public)")
                    fetches += 1
                }
            } catch {
                Self.logger.error("Couldn't fetch \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            fetching[key] = nil
        }
        fetching[key] = fetch
        lastFetch = fetch
        return fetch
    }

    /// Fetches the model's turntable unless it's here, and waits for it, at most `limit`: a
    /// device seen for the first time then turns in 3D from the start. Offline the fetch fails at
    /// once; a slow one goes on after, for next time.
    func ready(productID: Int, colorID: Int?, within limit: Duration) async {
        guard let fetch = prepare(productID: productID, colorID: colorID) else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await fetch.value }
            group.addTask { try? await Task.sleep(for: limit) }
            await group.next()
            group.cancelAll()
        }
    }

    /// One of Apple's asset archives in the catalog.
    nonisolated struct Asset: Equatable, Sendable {
        let type: String
        let color: Int
        let url: URL
        /// What Apple calls the color ("Black").
        var variant: String? = nil
    }

    nonisolated static func assets(inCatalog data: Data) -> [Asset] {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entries = root["Assets"] as? [[String: Any]]
        else { return [] }
        return entries.compactMap { entry in
            // "AirPodsPro1,2-v2", the color as text ("18").
            guard let type = (entry["ProductType"] as? String)?.split(separator: "-").first,
                  let color = (entry["CL"] as? String).flatMap({ Int($0) }),
                  let base = entry["__BaseURL"] as? String, let path = entry["__RelativePath"] as? String,
                  let url = URL(string: base + path)
            else { return nil }
            return Asset(type: String(type), color: color, url: url, variant: entry["VariantName"] as? String)
        }
    }

    /// The model's archive in that color, else its usual one, else in black (as macOS pictures Beats
    /// when it doesn't know their color, so the turn matches the picture shown till it's in), else
    /// its first.
    nonisolated static func asset(for product: Product, color: Int?, in assets: [Asset]) -> Asset? {
        let ofModel = assets.filter { $0.type == product.type }.sorted { $0.color < $1.color }
        return ofModel.first { $0.color == color } ?? ofModel.first { $0.color == product.usualColor }
            ?? ofModel.first { $0.variant?.contains("Black") == true } ?? ofModel.first
    }

    /// The clip that turns the model a whole way round and back. Earbuds turn beside their case
    /// (`loop-charged`, the first AirPods' `loop`), which is cut off so only the buds turn, as in the
    /// iPhone's Dynamic Island. Headphones (and the Solo Buds, whose case doesn't charge) turn on
    /// their own (`loop`), the Studio Pro only in `connect-loop`.
    nonisolated static let turnClips = ["ProxCard_loop-charged.mov", "ProxCard_loop.mov", "ProxCard_loop-charging.mov", "ProxCard_connect-loop.mov"]

    /// The case's picture in the bundle of earbuds whose case Apple shows (the first AirPods' as
    /// it was, later ones charged).
    nonisolated static let casePictures = ["ProxCard_case-closed-charged@3x.png", "ProxCard_case-closed@3x.png"]

    /// Reads the model's clip out of its archive on Apple's server and keeps a turntable of it.
    /// Returns the folder's name, nil if the catalog has no such model.
    nonisolated private static func fetch(_ product: Product, color: Int?, into directory: URL) async throws -> String? {
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let asset = asset(for: product, color: color, in: assets(inCatalog: try await catalog(in: directory))) else { return nil }
        let name = "\(asset.type)-\(asset.color)"
        let destination = directory.appendingPathComponent(name, isDirectory: true)
        guard !files.fileExists(atPath: destination.appendingPathComponent(turntableName).path) else { return nil }

        let archive = try await RemoteZip.open(RemoteZip.reader(for: asset.url))
        func member(_ file: String) -> RemoteZip.Member? {
            archive.members.first { $0.name.hasSuffix(".devicebundle/" + file) }
        }
        guard let clip = turnClips.lazy.compactMap(member).first else { throw CocoaError(.fileNoSuchFile) }
        // Earbuds whose case Apple pictures turn beside it.
        let hasCase = casePictures.contains { member($0) != nil }

        let work = files.temporaryDirectory.appendingPathComponent("DyNotch-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: work) }
        let video = work.appendingPathComponent("clip.mov")
        try await archive.data(of: clip).write(to: video)
        let made = work.appendingPathComponent(name, isDirectory: true)
        try files.createDirectory(at: made, withIntermediateDirectories: true)
        try await Turntable.make(fromVideo: video, to: made.appendingPathComponent(turntableName), leftOfWidestGap: hasCase)
        // One made the old way.
        try? files.removeItem(at: destination)
        try files.moveItem(at: made, to: destination)
        return name
    }

    /// Apple's catalog: the copy here while it's less than a week old, else a fresh one (the
    /// old one if Apple can't be reached).
    nonisolated private static func catalog(in directory: URL) async throws -> Data {
        let saved = directory.appendingPathComponent("catalog.xml")
        let age = (try? saved.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { -$0.timeIntervalSinceNow }
        if let age, age < 7 * 24 * 3600, let data = try? Data(contentsOf: saved) { return data }
        do {
            let (data, response) = try await URLSession.shared.data(from: catalogURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200, !assets(inCatalog: data).isEmpty else { throw URLError(.badServerResponse) }
            try data.write(to: saved, options: .atomic)
            return data
        } catch {
            if let data = try? Data(contentsOf: saved) { return data }
            throw error
        }
    }
}
