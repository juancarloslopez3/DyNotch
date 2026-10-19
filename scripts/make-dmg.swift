#!/usr/bin/env swift
// Lays out the DyNotch disk image window: renders its background (1x and 2x in one TIFF) and writes
// the .DS_Store that gives Finder the window size, icon spots and background picture, so the image
// is laid out without scripting Finder. Run by scripts/make-dmg.sh on the mounted read-write image.
// Usage: swift scripts/make-dmg.swift <volume> <app name>
import AppKit

let volume = URL(fileURLWithPath: CommandLine.arguments[1])
let appName = CommandLine.arguments[2]

// Finder window content, in points (top-left origin, like Finder's icon spots). Finder's window
// bounds include the title bar, and a user's "Show Path Bar" covers the bottom 28 points.
let width = 660.0, height = 400.0, titleBar = 32.0
let iconSize = 128.0
let appSpot = CGPoint(x: 170, y: 184), applicationsSpot = CGPoint(x: 490, y: 184)
let windowOrigin = CGPoint(x: 400, y: 260)  // bottom-left, in screen points

// MARK: - Background

func renderBackground(scale: Double) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.displayP3)!
    let ctx = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8,
                        bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.translateBy(x: 0, y: height * scale)
    ctx.scaleBy(x: scale, y: -scale)
    func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
        CGColor(colorSpace: space, components: [r, g, b, a])!
    }
    func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
        CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
    }

    // The app icon's indigo-to-rose wallpaper. It stays mid-dark where Finder writes the icon names,
    // so they read both in black (light mode) and in white (dark mode).
    ctx.drawLinearGradient(gradient([color(0.34, 0.30, 0.92), color(0.56, 0.30, 0.86), color(0.86, 0.38, 0.60)], [0, 0.5, 1]),
                           start: .zero, end: CGPoint(x: width, y: height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    let bloom = gradient([color(1, 1, 1, 0.22), color(1, 1, 1, 0)], [0, 1])
    ctx.drawRadialGradient(bloom, startCenter: CGPoint(x: 110, y: 40), startRadius: 0,
                           endCenter: CGPoint(x: 110, y: 40), endRadius: 460, options: [])
    let dusk = gradient([color(0.08, 0.02, 0.2, 0), color(0.08, 0.02, 0.2, 0.28)], [0, 1])
    ctx.drawLinearGradient(dusk, start: CGPoint(x: 0, y: 300), end: CGPoint(x: 0, y: height), options: [.drawsAfterEndLocation])

    // A dusky pool behind each icon, so the purple app icon doesn't sink into the matching wallpaper.
    // It fades out before the icon names.
    for spot in [appSpot, applicationsSpot] {
        let center = CGPoint(x: spot.x, y: spot.y + 6)
        let pool = gradient([color(0.10, 0.03, 0.30, 0.42), color(0.10, 0.03, 0.30, 0.18), color(0.10, 0.03, 0.30, 0)], [0, 0.55, 1])
        ctx.drawRadialGradient(pool, startCenter: center, startRadius: 0, endCenter: center, endRadius: 96, options: [])
    }

    // Chevrons from the app to Applications, brightening toward the drop.
    ctx.setLineWidth(4)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    for (index, alpha) in [0.35, 0.6, 0.9].enumerated() {
        let x = 306 + Double(index) * 24
        ctx.move(to: CGPoint(x: x, y: appSpot.y - 13))
        ctx.addLine(to: CGPoint(x: x + 12, y: appSpot.y))
        ctx.addLine(to: CGPoint(x: x, y: appSpot.y + 13))
        ctx.setStrokeColor(color(1, 1, 1, alpha))
        ctx.strokePath()
    }

    // The island hanging from the title bar, with the instruction inside.
    let island = CGRect(x: (width - 300) / 2, y: 0, width: 300, height: 40)
    let ear = 10.0, corner = 18.0
    let shape = CGMutablePath()
    shape.move(to: CGPoint(x: island.minX - ear, y: 0))
    shape.addQuadCurve(to: CGPoint(x: island.minX, y: ear), control: CGPoint(x: island.minX, y: 0))
    shape.addLine(to: CGPoint(x: island.minX, y: island.maxY - corner))
    shape.addQuadCurve(to: CGPoint(x: island.minX + corner, y: island.maxY), control: CGPoint(x: island.minX, y: island.maxY))
    shape.addLine(to: CGPoint(x: island.maxX - corner, y: island.maxY))
    shape.addQuadCurve(to: CGPoint(x: island.maxX, y: island.maxY - corner), control: CGPoint(x: island.maxX, y: island.maxY))
    shape.addLine(to: CGPoint(x: island.maxX, y: ear))
    shape.addQuadCurve(to: CGPoint(x: island.maxX + ear, y: 0), control: CGPoint(x: island.maxX, y: 0))
    shape.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 18, color: color(0.05, 0, 0.2, 0.45))
    ctx.addPath(shape)
    ctx.setFillColor(color(0, 0, 0))
    ctx.fillPath()
    ctx.restoreGState()

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    func draw(_ parts: [(String, NSFont.Weight)], size: Double, alpha: Double, centerY: Double) {
        let text = NSMutableAttributedString()
        for (string, weight) in parts {
            text.append(NSAttributedString(string: string, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: NSColor(white: 1, alpha: alpha),
            ]))
        }
        let bounds = text.size()
        text.draw(at: CGPoint(x: (width - bounds.width) / 2, y: centerY - bounds.height / 2))
    }
    draw([("Drag DyNotch to Applications", .semibold)], size: 13, alpha: 1, centerY: island.midY + 1)
    draw([("First launch blocked?  ", .semibold), ("System Settings › Privacy & Security › Open Anyway", .regular)],
         size: 11, alpha: 0.82, centerY: 340)
    NSGraphicsContext.restoreGraphicsState()

    return ctx.makeImage()!
}

let background = volume.appendingPathComponent(".background/background.tiff")
try FileManager.default.createDirectory(at: background.deletingLastPathComponent(), withIntermediateDirectories: true)
let destination = CGImageDestinationCreateWithURL(background as CFURL, "public.tiff" as CFString, 2, nil)!
for scale in [1.0, 2.0] {
    CGImageDestinationAddImage(destination, renderBackground(scale: scale), [
        kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale,
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5],  // LZW
    ] as CFDictionary)
}
guard CGImageDestinationFinalize(destination) else { fatalError("Couldn't write \(background.path)") }

// MARK: - .DS_Store

extension Data {
    mutating func u16(_ value: UInt16) { append(contentsOf: [UInt8(value >> 8), UInt8(value & 0xFF)]) }
    mutating func u32(_ value: UInt32) { u16(UInt16(value >> 16)); u16(UInt16(value & 0xFFFF)) }
    mutating func u64(_ value: UInt64) { u32(UInt32(value >> 32)); u32(UInt32(value & 0xFFFF_FFFF)) }
    mutating func code(_ fourCC: String) { append(contentsOf: Array(fourCC.utf8)) }
    mutating func pascal(_ string: String, field: Int) {
        let bytes = Array(string.utf8.prefix(field - 1))
        append(UInt8(bytes.count))
        append(contentsOf: bytes + Array(repeating: 0, count: field - 1 - bytes.count))
    }
}

func fileID(_ url: URL) -> (id: UInt32, parent: UInt32, created: Date) {
    var info = stat(), parent = stat()
    guard stat(url.path, &info) == 0, stat(url.deletingLastPathComponent().path, &parent) == 0 else { fatalError("stat \(url.path)") }
    let created = Date(timeIntervalSince1970: Double(info.st_birthtimespec.tv_sec))
    return (UInt32(info.st_ino), UInt32(parent.st_ino), created)
}

/// A classic (version 2) alias record, the form Finder reads for `backgroundImageAlias`. Same fields
/// as the `mac_alias` package that dmgbuild uses; the CNIDs and dates survive `hdiutil convert`.
func aliasRecord(for file: URL) throws -> Data {
    let values = try file.resourceValues(forKeys: [.volumeURLKey, .volumeNameKey])
    let root = values.volume!, volumeName = values.volumeName!
    let volumeCreated = try root.resourceValues(forKeys: [.creationDateKey]).creationDate!
    let target = fileID(file), folder = file.deletingLastPathComponent()
    let posixPath = String(file.path.dropFirst(root.path.count))
    func hfsSeconds(_ date: Date) -> Double { date.timeIntervalSince1970 + 2_082_844_800 }  // since 1904

    var record = Data()
    record.u32(0)  // creator app
    record.u16(0)  // record length, patched below
    record.u16(2)  // version
    record.u16(0)  // kind: file
    record.pascal(volumeName, field: 28)
    record.u32(UInt32(hfsSeconds(volumeCreated)))
    record.code("H+")
    record.u16(0)  // fixed disk
    record.u32(target.parent)
    record.pascal(file.lastPathComponent, field: 64)
    record.u32(target.id)
    record.u32(UInt32(hfsSeconds(target.created)))
    record.u32(0); record.u32(0)  // creator and type codes
    record.u16(0xFFFF); record.u16(0xFFFF)  // levels from / to
    record.u32(0); record.u16(0)  // volume attributes, file system ID
    record.append(Data(count: 10))

    func tag(_ tag: Int16, _ payload: Data) {
        record.u16(UInt16(bitPattern: tag))
        record.u16(UInt16(payload.count))
        record.append(payload)
        if payload.count % 2 == 1 { record.append(0) }
    }
    func utf16(_ string: String) -> Data {
        var data = Data()
        data.u16(UInt16(string.utf16.count))
        for unit in string.utf16 { data.u16(unit) }
        return data
    }
    func highRes(_ date: Date) -> Data { var data = Data(); data.u64(UInt64(hfsSeconds(date) * 65536)); return data }
    let ancestors = posixPath.split(separator: "/").dropLast().map(String.init)
    var cnidPath = Data()
    for depth in stride(from: ancestors.count, to: 0, by: -1) {
        cnidPath.u32(fileID(root.appendingPathComponent(ancestors.prefix(depth).joined(separator: "/"))).id)
    }

    tag(0, Data(folder.lastPathComponent.utf8))
    tag(16, highRes(volumeCreated))
    tag(17, highRes(target.created))
    tag(1, cnidPath)
    tag(2, Data(([volumeName] + ancestors + [file.lastPathComponent]).joined(separator: ":").utf8))
    tag(14, utf16(file.lastPathComponent))
    tag(15, utf16(volumeName))
    tag(18, Data(posixPath.utf8))
    tag(19, Data(root.path.utf8))
    record.u16(0xFFFF); record.u16(0)  // end of tags

    let length = UInt16(record.count)
    record.replaceSubrange(4..<6, with: [UInt8(length >> 8), UInt8(length & 0xFF)])
    return record
}

/// Writes a one-node .DS_Store: the "Bud1" buddy-allocated file holding a B-tree whose single leaf
/// has every record. Layout (offsets count from byte 4): header 0+32, DSDB 32+32, allocator info
/// 2048+2048, leaf 4096+4096; every other buddy is listed free.
struct DSStore {
    enum Value { case long(UInt32), type(String), blob(Data) }
    var records: [(name: String, code: String, value: Value)] = []

    func data() -> Data {
        let sorted = records.sorted { ($0.name.lowercased(), $0.code) < ($1.name.lowercased(), $1.code) }
        var leaf = Data()
        leaf.u32(0)  // no children: a leaf
        leaf.u32(UInt32(sorted.count))
        for record in sorted {
            leaf.u32(UInt32(record.name.utf16.count))
            for unit in record.name.utf16 { leaf.u16(unit) }
            leaf.code(record.code)
            switch record.value {
            case .long(let value): leaf.code("long"); leaf.u32(value)
            case .type(let value): leaf.code("type"); leaf.code(value)
            case .blob(let value): leaf.code("blob"); leaf.u32(UInt32(value.count)); leaf.append(value)
            }
        }
        precondition(leaf.count <= 4096, ".DS_Store records outgrew one node")

        var info = Data()
        info.u32(3); info.u32(0)
        for (offset, width) in [(2048, 11), (32, 5), (4096, 12)] { info.u32(UInt32(offset | width)) }  // blocks 0, 1, 2
        info.append(Data(count: (256 - 3) * 4))
        info.u32(1)
        info.append(4); info.code("DSDB"); info.u32(1)
        for width in 0..<32 {
            let free = (6...10).contains(width) || (13...30).contains(width)
            info.u32(free ? 1 : 0)
            if free { info.u32(1 << width) }
        }

        var file = Data()
        file.u32(1); file.code("Bud1")
        file.u32(2048); file.u32(2048); file.u32(2048)
        file.append(contentsOf: [0, 0, 0x10, 0x0C, 0, 0, 0, 0x87, 0, 0, 0x20, 0x0B, 0, 0, 0, 0])
        file.u32(2)  // DSDB: root node, levels, records, nodes, page size
        file.u32(0)
        file.u32(UInt32(sorted.count))
        file.u32(1)
        file.u32(4096)
        func place(_ block: Data, at offset: Int, size: Int) {
            file.append(Data(count: 4 + offset - file.count))
            file.append(block)
            file.append(Data(count: size - block.count))
        }
        place(info, at: 2048, size: 2048)
        place(leaf, at: 4096, size: 4096)
        return file
    }
}

func plist(_ object: [String: Any]) -> Data {
    try! PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
}
func spot(_ point: CGPoint) -> Data {
    var data = Data()
    data.u32(UInt32(point.x)); data.u32(UInt32(point.y))
    data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0])
    return data
}

var store = DSStore()
store.records.append((".", "bwsp", .blob(plist([
    "WindowBounds": "{{\(Int(windowOrigin.x)), \(Int(windowOrigin.y))}, {\(Int(width)), \(Int(height + titleBar))}}",
    "ShowToolbar": false, "ShowTabView": false, "ShowStatusBar": false, "ShowPathbar": false,
    "ShowSidebar": false, "ContainerShowSidebar": false, "PreviewPaneVisibility": false, "SidebarWidth": 0,
]))))
store.records.append((".", "icvp", .blob(plist([
    "viewOptionsVersion": 1, "arrangeBy": "none", "iconSize": iconSize, "textSize": 13.0,
    "labelOnBottom": true, "showIconPreview": true, "showItemInfo": false,
    "gridSpacing": 100.0, "gridOffsetX": 0.0, "gridOffsetY": 0.0, "scrollPositionX": 0.0, "scrollPositionY": 0.0,
    "backgroundType": 2, "backgroundImageAlias": try aliasRecord(for: background),
    "backgroundColorRed": 1.0, "backgroundColorGreen": 1.0, "backgroundColorBlue": 1.0,
]))))
store.records.append((".", "vSrn", .long(1)))
store.records.append((".", "vstl", .type("icnv")))
store.records.append((appName, "Iloc", .blob(spot(appSpot))))
store.records.append(("Applications", "Iloc", .blob(spot(applicationsSpot))))
try store.data().write(to: volume.appendingPathComponent(".DS_Store"))
print("Laid out \(volume.path)")
