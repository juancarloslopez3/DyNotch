import AppKit

/// The pictures macOS shows of Apple's Bluetooth accessories (System Settings › Bluetooth): a 3D
/// render of each model in each of its colors, kept in the private CoreBluetoothUI framework with
/// plists that name the file for each product and color ID. Nil wherever a later macOS moves or
/// drops one, so callers keep a symbol to fall back on.
enum ProductRender {
    private static let resources = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/CoreBluetoothUI.framework/Resources")
    private static var images: [String: NSImage] = [:]

    static func image(productID: Int, colorID: Int?) -> NSImage? {
        guard let name = imageName(productID: productID, colorID: colorID) else { return nil }
        if let image = images[name] { return image }
        let image = NSImage(contentsOf: resources.appending(path: name))
        images[name] = image
        return image
    }

    /// The file for the product in that color, else in its usual one.
    static func imageName(productID: Int, colorID: Int?) -> String? {
        guard let entry = entries[productID] else { return nil }
        if let colorID, let colors = entry["Color"] as? [String: String],
           let colored = colors.first(where: { hex($0.key) == colorID })?.value {
            return colored
        }
        return entry["ImageName"] as? String
    }

    /// Each product's entry by its ID ("0x2024"): AssetPaths.plist, then the newer models' own
    /// AssetPaths-<model>.plist, which also redo some older entries (the USB-C AirPods Max's colors).
    private static let entries: [Int: [String: Any]] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: resources.path)) ?? []
        let lists = ["AssetPaths.plist"] + files.filter { $0.hasPrefix("AssetPaths-") && $0.hasSuffix(".plist") }.sorted()
        var entries: [Int: [String: Any]] = [:]
        for list in lists {
            guard let plist = NSDictionary(contentsOf: resources.appending(path: list)) as? [String: Any] else { continue }
            for case let (key, entry as [String: Any]) in plist {
                if let id = hex(key) { entries[id] = entry }
            }
        }
        return entries
    }()

    private static func hex(_ string: String) -> Int? {
        string.hasPrefix("0x") ? Int(string.dropFirst(2), radix: 16) : nil
    }
}
