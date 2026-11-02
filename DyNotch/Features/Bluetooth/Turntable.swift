import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A model turning a whole way round, one frame every few degrees, so AirPods can turn into view
/// in 3D as they connect: rendered from a 3D model (`scripts/render-turntable.swift`), or made from
/// Apple's own video of the model turning (`make(fromVideo:to:)`, for `DeviceArt`).
nonisolated struct Turntable: Sendable {
    /// Face on first, then on round, cropped to where the model reaches in any of them: a pair of
    /// AirPods Pro side by side is much wider than tall.
    let frames: [CGImage]

    /// Each frame's size in pixels.
    var size: CGSize { CGSize(width: frames[0].width, height: frames[0].height) }

    /// The frames either side of `degrees` of turn, and how far it is from the first to the second
    /// (0 to 1), to blend them for a slow turn.
    func frames(around degrees: Double) -> (first: CGImage, second: CGImage, fraction: Double) {
        let position = degrees / 360 * Double(frames.count)
        let index = Int(position.rounded(.down))
        func wrapped(_ index: Int) -> CGImage { frames[(index % frames.count + frames.count) % frames.count] }
        return (wrapped(index), wrapped(index + 1), position - position.rounded(.down))
    }

    @MainActor private static var loaded: [URL: Turntable] = [:]

    /// Frames to a row in the picture, as the script lays them out.
    private static let across = 12

    /// `<name>.turntable.heic` in the app.
    @MainActor static func named(_ name: String) -> Turntable? {
        Bundle.main.url(forResource: name, withExtension: "turntable.heic").flatMap(load)
    }

    /// A picture of square frames, 12 to a row, top row first.
    @MainActor static func load(_ url: URL) -> Turntable? {
        if let turntable = loaded[url] { return turntable }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let grid = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        let side = grid.width / across
        guard side > 0, grid.height >= side else { return nil }
        let count = across * (grid.height / side)
        let reach = reach(of: grid, side: side) ?? CGRect(x: 0, y: 0, width: side, height: side)
        let frames = (0..<count).compactMap {
            grid.cropping(to: reach.offsetBy(dx: CGFloat($0 % across * side), dy: CGFloat($0 / across * side)))
        }
        guard frames.count == count else { return nil }
        let turntable = Turntable(frames: frames)
        loaded[url] = turntable
        return turntable
    }

    /// Where anything shows in any of the frames, within a frame (top-left origin).
    private static func reach(of grid: CGImage, side: Int) -> CGRect? {
        Coverage(of: [grid], tile: side)?.reach()
    }

    /// Which pixels of a tile show anything in any of the images, each one tile or a grid of them.
    /// Faint alpha left in the empty parts by the compression doesn't count.
    nonisolated private struct Coverage {
        let width: Int
        let height: Int
        private var covered: [Bool]

        init?(of images: [CGImage], tile: Int? = nil) {
            guard let first = images.first else { return nil }
            width = tile ?? first.width
            height = tile ?? first.height
            covered = Array(repeating: false, count: width * height)
            for image in images {
                let imageWidth = image.width, imageHeight = image.height
                guard let context = CGContext(data: nil, width: imageWidth, height: imageHeight, bitsPerComponent: 8, bytesPerRow: imageWidth * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                      let pixels = context.data?.assumingMemoryBound(to: UInt8.self)
                else { return nil }
                context.draw(image, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
                for y in 0..<imageHeight {
                    for x in 0..<imageWidth where pixels[(y * imageWidth + x) * 4 + 3] > 8 {
                        covered[y % height * width + x % width] = true
                    }
                }
            }
        }

        /// Where anything shows (top-left origin), in those columns.
        func reach(in columns: Range<Int>? = nil) -> CGRect? {
            var left = Int.max, right = -1, top = Int.max, bottom = -1
            for y in 0..<height {
                for x in columns ?? 0..<width where covered[y * width + x] {
                    left = min(left, x)
                    right = max(right, x)
                    top = min(top, y)
                    bottom = max(bottom, y)
                }
            }
            guard right >= left, bottom >= top else { return nil }
            return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
        }

        /// The columns left of the widest empty gap across it. Two buds can have a narrow one
        /// between them (Beats Fit Pro), the case beside them a much wider one.
        func columnsLeftOfWidestGap() -> Range<Int> {
            var runs: [Range<Int>] = []
            var start: Int?
            for x in 0...width {
                let isCovered = x < width && (0..<height).contains { covered[$0 * width + x] }
                if isCovered, start == nil { start = x }
                if !isCovered, let begin = start {
                    runs.append(begin..<x)
                    start = nil
                }
            }
            let gaps = zip(runs, runs.dropFirst()).map { $1.lowerBound - $0.upperBound }
            guard let widest = gaps.indices.max(by: { gaps[$0] < gaps[$1] }) else { return 0..<width }
            return runs[0].lowerBound..<runs[widest].upperBound
        }
    }

    /// Lays a video of something turning a whole way round, and back to where it started, out as
    /// a turntable picture: `count` frames evenly through it, cropped to where it reaches in any of
    /// them and fitted into square tiles of `side` pixels (about the most a wing shows of one, on a Retina screen).
    /// With `leftOfWidestGap`, only what's left of the widest empty gap across the frames: the buds,
    /// where Apple's clip turns them beside their case.
    static func make(fromVideo video: URL, to output: URL, count: Int = 120, side: Int = 80, leftOfWidestGap: Bool = false) async throws {
        let asset = AVURLAsset(url: video)
        let duration = try await asset.load(.duration)
        let generator = AVAssetImageGenerator(asset: asset)
        // Plenty for a tile, and far quicker to go through than Apple's ~1200 pixels.
        generator.maximumSize = CGSize(width: side * 5, height: side * 5)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let times = (0..<count).map { CMTimeMultiplyByRatio(duration, multiplier: Int32($0), divisor: Int32(count)) }
        var frames = [CGImage?](repeating: nil, count: count)
        for await result in generator.images(for: times) {
            guard let index = times.firstIndex(of: result.requestedTime) else { continue }
            frames[index] = try result.image
        }
        let images = frames.compactMap { $0 }
        guard images.count == count, let coverage = Coverage(of: images),
              let reach = coverage.reach(in: leftOfWidestGap ? coverage.columnsLeftOfWidestGap() : nil)
        else { throw CocoaError(.fileReadCorruptFile) }

        let rows = (count + across - 1) / across
        guard let grid = CGContext(data: nil, width: across * side, height: rows * side, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CocoaError(.fileWriteUnknown) }
        grid.interpolationQuality = .high
        let scale = CGFloat(side) / max(reach.width, reach.height)
        let fitted = CGSize(width: reach.width * scale, height: reach.height * scale)
        for (index, image) in images.enumerated() {
            guard let cropped = image.cropping(to: reach) else { continue }
            let tile = CGPoint(x: index % across * side, y: (rows - 1 - index / across) * side)
            grid.draw(cropped, in: CGRect(
                x: tile.x + (CGFloat(side) - fitted.width) / 2,
                y: tile.y + (CGFloat(side) - fitted.height) / 2,
                width: fitted.width, height: fitted.height
            ))
        }
        guard let picture = grid.makeImage(),
              let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.heic.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, picture, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
