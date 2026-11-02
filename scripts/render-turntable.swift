#!/usr/bin/env swift
// Renders a 3D model turning a whole way round into square frames, 12 to a row, starting face on
// (DyNotch/Resources/*.turntable.heic). The AirPods connecting animation plays it. A grid, not one
// long strip: HEIC decodes in square tiles, and a strip 120 frames long took ten times as long.
// Usage: swift scripts/render-turntable.swift <model.fbx|.blend|.obj> <out.heic>
//            (--base <png> [--normal <png>] [--roughness <png>] [--metallic <png>] [--opacity <png>]
//             | --material "<name> base=… roughness=… …" …)
//            [--keep <object>,…] [--up z] [--turn "<object> z<degrees> y<degrees> …" …]
//            [--move "<object> x,y,z" …]
//            [--frames 120] [--size 72] [--elevation 8] [--yaw 0]
//            [--cups #RRGGBB --cushions #RRGGBB --top #RRGGBB [--split 0.5]]
// FBX and Blender files go through `assimp export` first (brew install assimp). --size is each
// frame's side in pixels; --yaw turns the model until it faces the camera at frame 0.
// --keep renders only those objects (OBJ groups), leaving out the rest, e.g. the AirPods' case;
// --up z stands up a model made Z-up, as Blender makes them. --turn, once per object, turns it
// about its own centre by each of its steps in order ("y-20" is 20° clockwise seen from above);
// --move, once per object, then shifts it by x,y,z. Both are in the model's units and axes after
// --up: x right, y up, z towards the camera at frame 0.
// --material, once per material of the model (scripts/render-pro.sh), sets it from the keys base,
// metallic, roughness, normal, emission and occlusion: each a texture's path (no spaces), a
// number, or a #RRGGBB color. Materials not named render plain white.
// --cups/--cushions/--top paint the model in another color (scripts/render-max-colors.sh): the
// tinted metal and the tinted fabric below --split (a fraction of the height) take --cups and
// --cushions, everything tinted above it --top. Untinted parts (steel, black) stay as they are.
import AppKit
import Metal
import ModelIO
import SceneKit
import SceneKit.ModelIO

var options: [String: String] = [:]
/// Every value of the options given more than once (--material, --turn, --move).
var repeated: [String: [String]] = [:]
var positional: [String] = []
var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    if argument.hasPrefix("--") {
        let name = String(argument.dropFirst(2))
        options[name] = arguments.next()
        repeated[name, default: []].append(options[name]!)
    } else {
        positional.append(argument)
    }
}
let materialSpecs = repeated["material"] ?? []
guard positional.count == 2, options["base"] != nil || !materialSpecs.isEmpty else {
    print("Usage: swift scripts/render-turntable.swift <model.fbx|.blend|.obj> <out.heic> (--base <png> [--normal …] [--roughness …] [--metallic …] [--opacity …] | --material \"<name> base=… …\" …) [--keep <object>,…] [--turn \"<object> z<degrees> …\" …] [--move \"<object> x,y,z\" …] [--up z] [--frames 120] [--size 72] [--elevation 8] [--yaw 0]")
    exit(1)
}
let frames = Int(options["frames"] ?? "120")!
let size = Int(options["size"] ?? "72")!
/// Frames to a row, as `Turntable` reads them.
let across = 12
guard frames % across == 0 else { print("--frames has to be a multiple of \(across)"); exit(1) }
let elevation = Double(options["elevation"] ?? "8")! * .pi / 180
let yaw = Double(options["yaw"] ?? "0")!
/// Rendered this many times larger, then scaled down, for clean edges.
let supersample = 4

var modelURL = URL(fileURLWithPath: positional[0])
let temporary = FileManager.default.temporaryDirectory.appending(path: "turntable-\(ProcessInfo.processInfo.processIdentifier)")
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }
if modelURL.pathExtension.lowercased() != "obj" {
    let obj = temporary.appending(path: "model.obj")
    let assimp = Process()
    assimp.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    assimp.arguments = ["assimp", "export", modelURL.path, obj.path]
    assimp.standardOutput = FileHandle.nullDevice
    try assimp.run()
    assimp.waitUntilExit()
    guard assimp.terminationStatus == 0 else { print("assimp couldn't convert \(modelURL.path)"); exit(1) }
    modelURL = obj
}

/// `obj` with only the faces of the groups in `keep` (all of them if nil), and only the vertices
/// those use, numbered afresh; Z-up turned Y-up if `zUp`, then each group in `turns` turned about
/// its centre and each in `moves` moved by its offset. Faces only: lines and points go.
func trimmed(_ obj: URL, keeping keep: Set<String>?, zUp: Bool, turns: [String: [(axis: Int, degrees: Double)]], moves: [String: [Double]]) throws -> URL {
    var kept = ""
    var lists: [String: [Substring]] = ["v": [], "vt": [], "vn": []]
    var used: [String: [Int: Int]] = ["v": [:], "vt": [:], "vn": [:]]
    var output: [String: [Substring]] = ["v": [], "vt": [], "vn": []]
    /// The group each vertex and normal in `output` is first used by.
    var groups: [String: [String]] = ["v": [], "vt": [], "vn": []]
    var faces: [String] = []
    var group = ""
    for line in try String(contentsOf: obj, encoding: .utf8).split(separator: "\n") {
        let words = line.split(separator: " ")
        guard let key = words.first.map(String.init) else { continue }
        switch key {
        case "v", "vt", "vn":
            lists[key]!.append(line)
        case "mtllib":
            // Beside the new file, for the materials' names.
            let library = words.dropFirst().joined(separator: " ")
            let source = obj.deletingLastPathComponent().appending(path: library)
            if source.deletingLastPathComponent().standardizedFileURL != temporary.standardizedFileURL {
                try? FileManager.default.copyItem(at: source, to: temporary.appending(path: library))
            }
            kept += line + "\n"
        case "g":
            group = words.dropFirst().joined(separator: " ")
        case "usemtl":
            if keep?.contains(group) ?? true { faces.append(String(line)) }
        case "f" where keep?.contains(group) ?? true:
            let corners = words.dropFirst().map { corner in
                zip(["v", "vt", "vn"], corner.split(separator: "/", omittingEmptySubsequences: false)).map { kind, index -> String in
                    guard let old = Int(index) else { return "" }
                    if let new = used[kind]![old] { return String(new) }
                    output[kind]!.append(lists[kind]![old - 1])
                    groups[kind]!.append(group)
                    used[kind]![old] = output[kind]!.count
                    return String(output[kind]!.count)
                }.joined(separator: "/")
            }
            faces.append("f " + corners.joined(separator: " "))
        default:
            break
        }
    }
    // (x, y, z) → (x, z, -y): what faced -Y in Blender faces the camera.
    func standing(_ line: Substring) -> [Double] {
        let xyz = line.split(separator: " ").dropFirst().map { Double($0)! }
        return zUp ? [xyz[0], xyz[2], -xyz[1]] : xyz
    }
    /// `xyz` turned about the origin by each turn in order, anticlockwise looking down its axis.
    func turned(_ xyz: [Double], by turns: [(axis: Int, degrees: Double)]) -> [Double] {
        turns.reduce(xyz) { xyz, turn in
            let (a, b) = [(1, 2), (2, 0), (0, 1)][turn.axis]
            let cos = cos(turn.degrees * .pi / 180), sin = sin(turn.degrees * .pi / 180)
            var result = xyz
            result[a] = xyz[a] * cos - xyz[b] * sin
            result[b] = xyz[a] * sin + xyz[b] * cos
            return result
        }
    }
    var centres: [String: [Double]] = [:]
    for name in turns.keys {
        let points = zip(output["v"]!, groups["v"]!).filter { $0.1 == name }.map { standing($0.0) }
        centres[name] = (0..<3).map { axis in (points.map { $0[axis] }.min()! + points.map { $0[axis] }.max()!) / 2 }
    }
    for kind in ["v", "vt", "vn"] {
        for (index, line) in output[kind]!.enumerated() {
            guard kind != "vt", zUp || !turns.isEmpty || !moves.isEmpty else { kept += line + "\n"; continue }
            var xyz = standing(line)
            if let turn = turns[groups[kind]![index]] {
                // Normals only turn; vertices turn about the group's centre.
                let centre = kind == "v" ? centres[groups[kind]![index]]! : [0, 0, 0]
                xyz = zip(turned(zip(xyz, centre).map(-), by: turn), centre).map(+)
            }
            if kind == "v", let offset = moves[groups[kind]![index]] { xyz = zip(xyz, offset).map(+) }
            kept += "\(kind) \(xyz[0]) \(xyz[1]) \(xyz[2])\n"
        }
    }
    let url = temporary.appending(path: "trimmed.obj")
    try (kept + faces.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    return url
}
let keep = options["keep"].map { Set($0.split(separator: ",").map(String.init)) }
let turns = Dictionary(uniqueKeysWithValues: (repeated["turn"] ?? []).map { turn in
    let words = turn.split(separator: " ")
    return (String(words[0]), words.dropFirst().map { (axis: ["x": 0, "y": 1, "z": 2][$0.first!]!, degrees: Double($0.dropFirst())!) })
})
let moves = Dictionary(uniqueKeysWithValues: (repeated["move"] ?? []).map { move in
    let words = move.split(separator: " ")
    return (String(words[0]), words[1].split(separator: ",").map { Double($0)! })
})
if keep != nil || options["up"] == "z" || !turns.isEmpty || !moves.isEmpty {
    modelURL = try trimmed(modelURL, keeping: keep, zUp: options["up"] == "z", turns: turns, moves: moves)
}

func image(_ option: String) -> NSImage? {
    options[option].map { NSImage(contentsOf: URL(fileURLWithPath: $0))! }
}

let model = SCNNode()
SCNScene(mdlAsset: MDLAsset(url: modelURL)).rootNode.childNodes.forEach { model.addChildNode($0) }

// MARK: Recoloring

/// An RGBA8 copy of an image at `side` × `side`.
func pixels(_ image: CGImage, side: Int) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: side * side * 4)
    let context = CGContext(data: &data, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    return data
}

func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
func encoded(_ value: Double) -> Double { value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055 }
func luminance(_ rgb: [Double]) -> Double { 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2] }

func color(_ option: String) -> [Double]? {
    guard let hex = options[option].map({ $0.trimmingCharacters(in: CharacterSet(charactersIn: "#")) }), let value = Int(hex, radix: 16) else { return nil }
    return [value >> 16, value >> 8 & 0xFF, value & 0xFF].map { linear(Double($0) / 255) }
}

/// The base texture with its tinted metal painted `metal` and its tinted fabric `fabric` (linear
/// RGB), keeping the texture's own light and shade.
func recolored(metal: [Double], fabric: [Double]) -> CGImage {
    let side = 1024
    let cgBase = image("base")!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let cgMetallic = image("metallic")!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    var data = pixels(cgBase, side: side)
    let metallic = pixels(cgMetallic, side: side)
    var kinds = [UInt8](repeating: 0, count: side * side)
    var lumas: [[Double]] = [[], [], []]
    for i in 0..<side * side {
        let rgb = (0..<3).map { Double(data[i * 4 + $0]) }
        let high = rgb.max()!, low = rgb.min()!
        guard high > 8, (high - low) / high > 0.15 else { continue }
        kinds[i] = metallic[i * 4] > 128 ? 1 : 2
        lumas[Int(kinds[i])].append(luminance(rgb.map { linear($0 / 255) }))
    }
    let reference = lumas.map { $0.isEmpty ? 1 : $0.sorted()[$0.count / 2] }
    for i in 0..<side * side where kinds[i] != 0 {
        let target = kinds[i] == 1 ? metal : fabric
        let shade = luminance((0..<3).map { linear(Double(data[i * 4 + $0]) / 255) }) / reference[Int(kinds[i])]
        for c in 0..<3 {
            data[i * 4 + c] = UInt8((encoded(min(target[c] * shade, 1)) * 255).rounded())
        }
    }
    let context = CGContext(data: &data, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return context.makeImage()!
}

/// Splits each geometry in two at `fraction` of its height: the triangles below, then those above.
func splitAtHeight(_ fraction: Double) {
    model.enumerateHierarchy { node, _ in
        guard let geometry = node.geometry, let source = geometry.sources(for: .vertex).first else { return }
        let positions: [Double] = source.data.withUnsafeBytes { raw in
            (0..<source.vectorCount).map { raw.load(fromByteOffset: source.dataOffset + $0 * source.dataStride + 4, as: Float.self) }.map(Double.init)
        }
        let split = positions.min()! + (positions.max()! - positions.min()!) * fraction
        var below: [UInt32] = [], above: [UInt32] = []
        for element in geometry.elements where element.primitiveType == .triangles {
            let indices: [UInt32] = element.data.withUnsafeBytes { raw in
                (0..<element.primitiveCount * 3).map {
                    element.bytesPerIndex == 2 ? UInt32(raw.load(fromByteOffset: $0 * 2, as: UInt16.self)) : raw.load(fromByteOffset: $0 * 4, as: UInt32.self)
                }
            }
            for t in stride(from: 0, to: indices.count, by: 3) {
                let height = (positions[Int(indices[t])] + positions[Int(indices[t + 1])] + positions[Int(indices[t + 2])]) / 3
                (height > split ? { above += indices[t...t + 2] } : { below += indices[t...t + 2] })()
            }
        }
        node.geometry = SCNGeometry(sources: geometry.sources, elements: [below, above].map { SCNGeometryElement(indices: $0, primitiveType: .triangles) })
    }
}

let material = SCNMaterial()
material.lightingModel = .physicallyBased
material.diffuse.contents = image("base")
material.normal.contents = image("normal")
material.roughness.contents = image("roughness") ?? 0.5
material.metalness.contents = image("metallic") ?? 0
if let opacity = image("opacity")?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    // The map is white where opaque; SceneKit reads that from an alpha channel.
    let w = opacity.width, h = opacity.height
    let gray = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    gray.draw(opacity, in: CGRect(x: 0, y: 0, width: w, height: h))
    let mask = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    mask.clip(to: CGRect(x: 0, y: 0, width: w, height: h), mask: gray.makeImage()!)
    mask.setFillColor(.white)
    mask.fill(CGRect(x: 0, y: 0, width: w, height: h))
    material.transparent.contents = mask.makeImage()
    material.transparencyMode = .aOne
}
material.isDoubleSided = true
var materials = [material]
if let cups = color("cups"), let cushions = color("cushions"), let top = color("top") {
    splitAtHeight(Double(options["split"] ?? "0.5")!)
    let upper = material.copy() as! SCNMaterial
    material.diffuse.contents = recolored(metal: cups, fabric: cushions)
    upper.diffuse.contents = recolored(metal: top, fabric: top)
    materials.append(upper)
}

/// A `--material`: "<name> key=value …".
func named(_ spec: String) -> (String, SCNMaterial) {
    var words = spec.split(separator: " ")
    let name = String(words.removeFirst())
    let material = SCNMaterial()
    material.lightingModel = .physicallyBased
    material.isDoubleSided = true
    for word in words {
        let pair = word.split(separator: "=", maxSplits: 1).map(String.init)
        let property: SCNMaterialProperty = switch pair[0] {
        case "base": material.diffuse
        case "metallic": material.metalness
        case "roughness": material.roughness
        case "normal": material.normal
        case "emission": material.emission
        case "occlusion": material.ambientOcclusion
        default: fatalError("No material key \(pair[0])")
        }
        if pair[1].hasPrefix("#"), let hex = Int(pair[1].dropFirst(), radix: 16) {
            property.contents = NSColor(srgbRed: CGFloat(hex >> 16) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        } else if let number = Double(pair[1]) {
            property.contents = number
        } else {
            property.contents = NSImage(contentsOf: URL(fileURLWithPath: pair[1]))!
        }
    }
    return (name, material)
}
if materialSpecs.isEmpty {
    model.enumerateHierarchy { node, _ in node.geometry?.materials = materials }
} else {
    let byName = Dictionary(uniqueKeysWithValues: materialSpecs.map(named))
    let plain = named("plain base=#FFFFFF").1
    model.enumerateHierarchy { node, _ in
        node.geometry?.materials = node.geometry!.materials.map { byName[$0.name ?? ""] ?? plain }
    }
}

// Turn about the model's own centre.
let (low, high) = model.boundingBox
let extent = SCNVector3(high.x - low.x, high.y - low.y, high.z - low.z)
model.position = SCNVector3(-(low.x + high.x) / 2, -(low.y + high.y) / 2, -(low.z + high.z) / 2)
let turntable = SCNNode()
turntable.addChildNode(model)
let scene = SCNScene()
scene.rootNode.addChildNode(turntable)
scene.background.contents = NSColor.clear

// A bright studio, so it stands out on the black notch: light from above, a soft box front
// left and another behind right, a grey floor.
let studio = CGContext(data: nil, width: 1024, height: 512, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
    CGColor(gray: 1, alpha: 1), CGColor(gray: 0.8, alpha: 1), CGColor(gray: 0.45, alpha: 1), CGColor(gray: 0.25, alpha: 1),
] as CFArray, locations: [0, 0.4, 0.55, 1])!
studio.drawLinearGradient(sky, start: CGPoint(x: 0, y: 512), end: .zero, options: [])
studio.setFillColor(.white)
studio.fillEllipse(in: CGRect(x: 384, y: 320, width: 146, height: 102))
studio.fillEllipse(in: CGRect(x: 856, y: 256, width: 102, height: 85))
scene.lightingEnvironment.contents = studio.makeImage()
scene.lightingEnvironment.intensity = 2.2

func light(intensity: CGFloat, pitch: CGFloat, yaw: CGFloat) {
    let node = SCNNode()
    node.light = SCNLight()
    node.light!.type = .directional
    node.light!.intensity = intensity
    node.eulerAngles = SCNVector3(pitch, yaw, 0)
    scene.rootNode.addChildNode(node)
}
light(intensity: 1500, pitch: -0.7, yaw: -0.5)
// From behind, to pick the edges out of the black.
light(intensity: 1200, pitch: -0.4, yaw: .pi * 0.85)

// How far the model reaches from the axis it turns about: its widest in the turn.
var reach = 0.0
model.enumerateHierarchy { node, _ in
    guard let source = node.geometry?.sources(for: .vertex).first else { return }
    source.data.withUnsafeBytes { raw in
        for i in 0..<source.vectorCount {
            let offset = source.dataOffset + i * source.dataStride
            let xyz = (0..<3).map { CGFloat(raw.load(fromByteOffset: offset + $0 * 4, as: Float.self)) }
            let point = node.convertPosition(SCNVector3(xyz[0], xyz[1], xyz[2]), to: turntable)
            reach = max(reach, hypot(Double(point.x), Double(point.z)))
        }
    }
}

// A long lens, far enough back for the widest view in the turn to fit.
let camera = SCNNode()
camera.camera = SCNCamera()
camera.camera!.fieldOfView = 14
let radius = max(Double(extent.y) / 2, reach) * 1.06
let distance = radius / tan(7 * .pi / 180)
camera.position = SCNVector3(0, distance * sin(elevation), distance * cos(elevation))
camera.eulerAngles = SCNVector3(-elevation, 0, 0)
camera.camera!.zFar = distance * 3
scene.rootNode.addChildNode(camera)

let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice()!, options: nil)
renderer.scene = scene
renderer.pointOfView = camera

let rows = frames / across
let grid = CGContext(data: nil, width: size * across, height: size * rows, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
grid.interpolationQuality = .high
for frame in 0..<frames {
    turntable.eulerAngles.y = CGFloat((Double(frame) * 360 / Double(frames) + yaw) * .pi / 180)
    let shot = renderer.snapshot(atTime: 0, with: CGSize(width: size * supersample, height: size * supersample), antialiasingMode: .multisampling4X)
    // Left to right, top row first (the context's origin is bottom left).
    let place = CGRect(x: frame % across * size, y: (rows - 1 - frame / across) * size, width: size, height: size)
    grid.draw(shot.cgImage(forProposedRect: nil, context: nil, hints: nil)!, in: place)
}

let output = URL(fileURLWithPath: positional[1])
let type = output.pathExtension.lowercased() == "png" ? "public.png" : "public.heic"
let destination = CGImageDestinationCreateWithURL(output as CFURL, type as CFString, 1, nil)!
CGImageDestinationAddImage(destination, grid.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
guard CGImageDestinationFinalize(destination) else { print("Couldn't write \(output.path)"); exit(1) }
print("\(frames) frames of \(size) px → \(output.path)")
