#!/usr/bin/env swift
// Renders the DyNotch app icon (1024 px) and writes every size into the asset catalog.
// Usage: swift scripts/make-icon.swift
import AppKit

let size = 1024.0
let output = URL(fileURLWithPath: "DyNotch/Resources/Assets.xcassets/AppIcon.appiconset")

func render() -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.displayP3)!
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
        CGColor(colorSpace: space, components: [r, g, b, a])!
    }

    // Squircle body on the macOS icon grid (824 pt body, 100 pt margin).
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.35))
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0.1, 0.1, 0.14))
    ctx.fillPath()
    ctx.restoreGState()

    // Background: deep indigo to violet, like a wallpaper behind the notch.
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let background = CGGradient(colorsSpace: space, colors: [
        color(0.36, 0.30, 0.95), color(0.62, 0.30, 0.86), color(0.98, 0.45, 0.55),
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])

    // Soft light bloom
    let bloom = CGGradient(colorsSpace: space, colors: [color(1, 1, 1, 0.35), color(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(bloom, startCenter: CGPoint(x: 330, y: 330), startRadius: 0,
                           endCenter: CGPoint(x: 330, y: 330), endRadius: 520, options: [])

    // The island: a black capsule hanging from the top edge.
    let island = CGRect(x: 212, y: 560, width: 600, height: 196)
    let islandPath = CGPath(roundedRect: island, cornerWidth: 98, cornerHeight: 98, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: color(0.05, 0, 0.2, 0.55))
    ctx.addPath(islandPath)
    ctx.setFillColor(color(0, 0, 0))
    ctx.fillPath()
    ctx.restoreGState()

    // Glass rim on the island
    ctx.saveGState()
    ctx.addPath(islandPath)
    ctx.setLineWidth(5)
    ctx.setStrokeColor(color(1, 1, 1, 0.22))
    ctx.strokePath()
    ctx.restoreGState()

    // Album art tile
    let art = CGRect(x: 262, y: 598, width: 120, height: 120)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: art, cornerWidth: 30, cornerHeight: 30, transform: nil))
    ctx.clip()
    let artGradient = CGGradient(colorsSpace: space, colors: [color(1, 0.62, 0.2), color(1, 0.25, 0.45)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(artGradient, start: CGPoint(x: art.minX, y: art.maxY), end: CGPoint(x: art.maxX, y: art.minY), options: [])
    ctx.restoreGState()

    // Equalizer bars
    let heights: [Double] = [64, 108, 82, 124, 70]
    for (index, height) in heights.enumerated() {
        let x = 552 + Double(index) * 42
        let bar = CGRect(x: x, y: 658 - height / 2, width: 22, height: height)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 11, cornerHeight: 11, transform: nil))
        ctx.setFillColor(color(0.35, 0.95, 0.55))
        ctx.fillPath()
    }

    // Liquid Glass sheen over the whole tile
    let sheen = CGGradient(colorsSpace: space, colors: [color(1, 1, 1, 0.28), color(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 600), options: [])
    ctx.restoreGState()

    // Edge highlight
    ctx.addPath(bodyPath)
    ctx.setLineWidth(4)
    ctx.setStrokeColor(color(1, 1, 1, 0.25))
    ctx.strokePath()

    return ctx.makeImage()!
}

func write(_ image: CGImage, pixels: Int, to url: URL) {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: image.colorSpace!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
}

let image = render()
var entries: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        write(image, pixels: points * scale, to: output.appendingPathComponent(name))
        entries.append("""
            { "filename" : "\(name)", "idiom" : "mac", "scale" : "\(scale)x", "size" : "\(points)x\(points)" }
        """)
    }
}
let contents = """
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try! contents.write(to: output.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(entries.count) icon sizes")
