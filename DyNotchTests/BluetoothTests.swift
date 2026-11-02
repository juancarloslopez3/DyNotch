import AppKit
import AVFoundation
import Testing

@testable import DyNotch

struct BluetoothTests {
    @Test func parsesAirPodsBatteryFromSystemProfiler() throws {
        let json = """
        {"SPBluetoothDataType":[{"device_connected":[
          {"AirPods Pro":{"device_address":"AA:BB:CC:DD:EE:FF","device_batteryLevelLeft":"90 %","device_batteryLevelRight":"85 %","device_batteryLevelCase":"40 %"}},
          {"Magic Mouse":{"device_address":"11:22:33:44:55:66","device_batteryLevelMain":"70 %"}}
        ]}]}
        """
        let battery = try #require(BluetoothMonitor.parseSystemProfiler(Data(json.utf8), address: "AABBCCDDEEFF"))
        #expect(battery.left == 90)
        #expect(battery.right == 85)
        #expect(battery.caseLevel == 40)
        #expect(battery.summary == 85)
        #expect(BluetoothMonitor.parseSystemProfiler(Data(json.utf8), address: BluetoothMonitor.normalize("11-22-33-44-55-66"))?.main == 70)
    }

    @Test func picksSymbolsByName() {
        #expect(BluetoothMonitor.symbol(name: "Jane's AirPods Pro", major: 0x04, minor: 0) == "airpods.pro")
        #expect(BluetoothMonitor.symbol(name: "Headset", major: 0x04, minor: 0) == "headphones")
        #expect(BluetoothMonitor.symbol(name: "Magic Keyboard", major: 0x05, minor: 0x10) == "keyboard.fill")
        // iPhones, iPads and Apple Watches by name (on Bluetooth LE they have no class), else by class.
        #expect(BluetoothMonitor.symbol(name: "iPhone 15 Pro Max de Carlos", major: 0, minor: 0) == "iphone")
        #expect(BluetoothMonitor.symbol(name: "iPad Pro M4 de Carlos", major: 0, minor: 0) == "ipad")
        #expect(BluetoothMonitor.symbol(name: "Apple\u{A0}Watch de Carlos", major: 0, minor: 0) == "applewatch")
        #expect(BluetoothMonitor.symbol(name: "Tablet", major: 0x01, minor: 0x07) == "ipad")
        #expect(BluetoothMonitor.symbol(name: "Watch", major: 0x07, minor: 0x01) == "applewatch")
        #expect(BluetoothMonitor.symbol(name: "Pixel 8", major: 0x02, minor: 0x03) == "smartphone")
        #expect(BluetoothMonitor.symbol(name: "MacBook Pro", major: 0x01, minor: 0x03) == "dot.radiowaves.left.and.right")
    }

    @Test func knowsPhonesTabletsAndWatchesByClassAndName() {
        #expect(BluetoothMonitor.isPhoneTabletOrWatch(name: "Carlos’s Phone", major: 0x02, minor: 0x03))
        #expect(BluetoothMonitor.isPhoneTabletOrWatch(name: "Tablet", major: 0x01, minor: 0x07))
        #expect(BluetoothMonitor.isPhoneTabletOrWatch(name: "Watch", major: 0x07, minor: 0x01))
        // Over Bluetooth LE there's no device class, only the name macOS gave them.
        #expect(BluetoothMonitor.isPhoneTabletOrWatch(name: "iPhone 15 Pro Max de Carlos", major: 0, minor: 0))
        #expect(BluetoothMonitor.isPhoneTabletOrWatch(name: "iPad Pro M4 de Carlos", major: 0, minor: 0))
        #expect(BluetoothMonitor.isPhoneTabletOrWatch(name: "Apple\u{A0}Watch de Carlos", major: 0, minor: 0))
        #expect(BluetoothMonitor.isPhoneTabletOrWatch(name: "Jane’s Apple Watch", major: 0, minor: 0))
        #expect(!BluetoothMonitor.isPhoneTabletOrWatch(name: "AirPods Pro 2 de Carlos", major: 0x04, minor: 0x06))
        #expect(!BluetoothMonitor.isPhoneTabletOrWatch(name: "MacBook Pro", major: 0x01, minor: 0x03))
        #expect(!BluetoothMonitor.isPhoneTabletOrWatch(name: "Magic Mouse", major: 0x05, minor: 0x20))
    }

    @Test func knowsAirPodsByProductIDAndName() {
        #expect(AirPodsModel(productID: 0x2024) == .airPodsPro)
        #expect(AirPodsModel(productID: 0x201F) == .airPodsMax)
        #expect(AirPodsModel(productID: 0x200A) == .airPodsMax)
        #expect(AirPodsModel(productID: 0x2019) == .airPods4)
        #expect(AirPodsModel(productID: 0x2027) == .airPodsPro)
        #expect(AirPodsModel(productID: 0x202D) == .airPodsMax)
        #expect(AirPodsModel(productID: 0x9999) == nil)
        #expect(AirPodsModel(name: "AirPods Max de Carlos") == .airPodsMax)
        #expect(AirPodsModel(name: "Jane’s AirPods Pro") == .airPodsPro)
        #expect(AirPodsModel(name: "AirPods 4") == .airPods4)
        #expect(AirPodsModel(name: "Carlos’s AirPods") == .airPods)
        #expect(AirPodsModel(name: "Magic Mouse") == nil)
        #expect(AirPodsModel(productID: AirPodsModel.airPodsPro.typicalProductID) == .airPodsPro)
        #expect(AirPodsModel(productID: AirPodsModel.airPodsMax.typicalProductID) == .airPodsMax)
    }

    @Test func knowsBeatsByProductID() throws {
        let fitPro = try #require(AirPodsModel(productID: 0x2012))
        #expect(fitPro == .beats(productID: 0x2012))
        #expect(fitPro.name == "Beats Fit Pro")
        #expect(fitPro.symbol == "beats.fitpro")
        #expect(fitPro.typicalProductID == 0x2012)
        #expect(AirPodsModel(productID: 0x2009) == .beats(productID: 0x2009))
        // Beats only go by product ID: a name says too little.
        #expect(AirPodsModel(name: "Beats Studio Pro de Carlos") == nil)
        for (_, beats) in AirPodsModel.beats {
            #expect(NSImage(systemSymbolName: beats.symbol, accessibilityDescription: nil) != nil, "\(beats.symbol)")
        }
    }

    @Test func everyAnimatedModelHasApplesPictures() {
        for productID in AirPodsModel.beats.keys {
            #expect(DeviceArt.products[productID] != nil, "\(String(productID, radix: 16))")
        }
        for model in [AirPodsModel.airPods, .airPods3, .airPods4, .airPodsPro, .airPodsMax] {
            #expect(DeviceArt.products[model.typicalProductID] != nil, "\(model)")
        }
        #expect(DeviceArt.products[0x2024]?.type == "AirPodsPro1,2")
        #expect(DeviceArt.products[0x201F]?.type == "AirPodsMax1,2")
    }

    @Test func mapsColorIDsToTheCatalogsColors() throws {
        let max = try #require(DeviceArt.products[0x201F])
        // Midnight, whether or not the flag above the color is set; Starlight when not known.
        #expect(max.color(for: 0x12) == 18)
        #expect(max.color(for: 0x52) == 18)
        #expect(max.color(for: nil) == 19)
        #expect(DeviceArt.products[0x200A]?.color(for: nil) == 15)
        #expect(DeviceArt.products[0x2011]?.color(for: 34) == 2)
        #expect(DeviceArt.products[0x202F]?.color(for: 0x0A) == 10)
        #expect(DeviceArt.products[0x2024]?.color(for: nil) == nil)
    }

    @Test func readsApplesCatalog() throws {
        func entry(_ type: String, _ color: String, _ variant: String) -> [String: Any] {
            ["ProductType": type, "CL": color, "VariantName": variant, "__BaseURL": "https://updates.cdn-apple.com/a/", "__RelativePath": "\(type)-\(color).zip"]
        }
        let catalog = ["Assets": [
            entry("AirPodsMax1,2-v2", "18", "Black"), entry("AirPodsMax1,2-v2", "19", "Silver"), entry("AirPodsMax1,2-v2", "20", "Blue"),
            entry("BeatsFitPro1,1-v2", "2", "Stone Purple"), entry("BeatsFitPro1,1-v2", "1", "Black"), entry("BeatsFitPro1,1-v2", "0", "White"),
            entry("AirPods1,4-v2", "0", "White"), ["ProductType": "Broken"],
        ]]
        let data = try PropertyListSerialization.data(fromPropertyList: catalog, format: .xml, options: 0)
        let assets = DeviceArt.assets(inCatalog: data)
        #expect(assets.count == 7)
        #expect(assets[0] == DeviceArt.Asset(type: "AirPodsMax1,2", color: 18, url: URL(string: "https://updates.cdn-apple.com/a/AirPodsMax1,2-v2-18.zip")!, variant: "Black"))
        let max = try #require(DeviceArt.products[0x201F])
        #expect(DeviceArt.asset(for: max, color: max.color(for: 0x14), in: assets)?.color == 20)
        // A color the catalog doesn't have: the usual one, else the first.
        #expect(DeviceArt.asset(for: max, color: 0, in: assets)?.color == 19)
        // Beats in a color it doesn't have, or none: black, as macOS pictures them.
        let fitPro = try #require(DeviceArt.products[0x2012])
        #expect(DeviceArt.asset(for: fitPro, color: 7, in: assets)?.color == 1)
        #expect(DeviceArt.asset(for: fitPro, color: nil, in: assets)?.color == 1)
        #expect(DeviceArt.asset(for: fitPro, color: 2, in: assets)?.color == 2)
        #expect(DeviceArt.asset(for: try #require(DeviceArt.products[0x2019]), color: nil, in: assets)?.color == 0)
        #expect(DeviceArt.asset(for: try #require(DeviceArt.products[0x2024]), color: nil, in: assets) == nil)
        #expect(DeviceArt.assets(inCatalog: Data("not a plist".utf8)).isEmpty)
    }

    @Test func readsOneMemberOfAZipWithoutTheRest() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RemoteZipTests-\(UUID().uuidString)")
        let bundle = directory.appendingPathComponent("AssetData/Test.devicebundle")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // A clip that compresses (deflated) and one that doesn't (stored).
        let clip = Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0 / 7) })
        let noise = Data((0..<300_000).map { _ in UInt8.random(in: 0...255) })
        try clip.write(to: bundle.appendingPathComponent("ProxCard_loop.mov"))
        try noise.write(to: bundle.appendingPathComponent("ProxCard_features.mov"))
        // The clip deflated, the noise stored.
        for arguments in [["-q", "-r", "asset.zip", "AssetData", "-x", "*features*"], ["-q", "-0", "asset.zip", "AssetData/Test.devicebundle/ProxCard_features.mov"]] {
            let zip = Process()
            zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            zip.currentDirectoryURL = directory
            zip.arguments = arguments
            try zip.run()
            zip.waitUntilExit()
        }
        let archive = try Data(contentsOf: directory.appendingPathComponent("asset.zip"))

        let tally = ByteTally()
        let remote = try await RemoteZip.open { bytes in
            let data = RemoteZip.slice(archive, bytes)
            await tally.add(data.count)
            return data
        }
        let loop = try #require(remote.members.first { $0.name == "AssetData/Test.devicebundle/ProxCard_loop.mov" })
        let features = try #require(remote.members.first { $0.name.hasSuffix("/ProxCard_features.mov") })
        #expect(loop.method == 8 && features.method == 0)
        #expect(try await remote.data(of: loop) == clip)
        // The index and that clip, not the other one.
        #expect(await tally.bytes < archive.count - noise.count / 2)
        #expect(try await remote.data(of: features) == noise)

        // A byte off in the clip.
        var damage = archive
        damage[loop.offset + 30 + loop.name.utf8.count + 64] ^= 0xFF
        let broken = damage
        let damaged = try await RemoteZip.open { RemoteZip.slice(broken, $0) }
        await #expect(throws: (any Error).self) { try await damaged.data(of: loop) }
        #expect(RemoteZip.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(RemoteZip.endOfIndex(in: Data(count: 100)) == nil)
    }

    @Test func findsTheFetchedPicturesInTheirColorElseAnother() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DeviceArtTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let blue = directory.appendingPathComponent("AirPodsMax1,2-20")
        try FileManager.default.createDirectory(at: blue, withIntermediateDirectories: true)
        let turntable = try #require(Bundle.main.url(forResource: "AirPodsMax-Blue", withExtension: "turntable.heic"))
        try FileManager.default.copyItem(at: turntable, to: blue.appendingPathComponent(DeviceArt.turntableName))
        // One made the way DyNotch used to, which is fetched again rather than shown.
        let old = directory.appendingPathComponent("AirPodsMax1,1-15")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: turntable, to: old.appendingPathComponent("turntable.heic"))
        let art = DeviceArt(directory: directory)
        #expect(art.turntable(productID: 0x201F, colorID: 0x14)?.frames.count == 120)
        // Asked for in Midnight, which isn't here: the color that is.
        #expect(art.turntable(productID: 0x201F, colorID: 0x12) != nil)
        #expect(art.turntable(productID: 0x200A, colorID: nil) == nil)
        #expect(art.turntable(productID: 0x9999, colorID: nil) == nil)
        // Nothing to fetch, or wait for, when it's here in its color, or for what isn't Apple's.
        #expect(art.prepare(productID: 0x201F, colorID: 0x14) == nil)
        #expect(art.prepare(productID: 0x9999, colorID: nil) == nil)
    }

    @Test func makesATurntableOfAVideoThatTurnsWithOrWithoutItsCase() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TurntableTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // A square going round a circle on nothing, a frame a second for 24 seconds, by a bar just
        // beside its path (a second bud) and a block further off (the case).
        let video = directory.appendingPathComponent("turn.mov")
        let writer = try AVAssetWriter(outputURL: video, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha, AVVideoWidthKey: 200, AVVideoHeightKey: 200])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 200, kCVPixelBufferHeightKey as String: 200])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<24 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try #require(adaptor.pixelBufferPool), &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            let context = try #require(CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
            context.clear(CGRect(x: 0, y: 0, width: 200, height: 200))
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            let angle = Double(frame) / 24 * 2 * .pi
            context.fill(CGRect(x: 90 + 40 * cos(angle) - 10, y: 90 + 20 * sin(angle) - 10, width: 20, height: 20))
            context.fill(CGRect(x: 144, y: 80, width: 6, height: 20))
            context.fill(CGRect(x: 170, y: 80, width: 20, height: 20))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 1))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: 24, timescale: 1))
        await writer.finishWriting()
        #expect(writer.status == .completed)

        let output = directory.appendingPathComponent("turn.heic")
        try await Turntable.make(fromVideo: video, to: output, count: 24, side: 40)
        let turntable = try #require(Turntable.load(output))
        #expect(turntable.frames.count == 24)
        // Cropped to everything's reach, 150 × 60, and fitted to the tiles.
        #expect(turntable.size.width >= 38 && turntable.size.width <= 40)
        #expect(abs(turntable.size.height - turntable.size.width * 0.4) <= 3)

        // Without the case: the square's path and the bar, 110 × 60.
        let buds = directory.appendingPathComponent("buds.heic")
        try await Turntable.make(fromVideo: video, to: buds, count: 24, side: 40, leftOfWidestGap: true)
        let budsOnly = try #require(Turntable.load(buds))
        #expect(budsOnly.size.width >= 38 && budsOnly.size.width <= 40)
        #expect(abs(budsOnly.size.height - budsOnly.size.width * 60 / 110) <= 3)
    }

    @Test func findsTheRenderMacOSShowsForEachModelAndColor() {
        #expect(ProductRender.imageName(productID: 0x2024, colorID: nil) == "B698.icns")
        // The USB-C AirPods Max's colors are 0x12–0x16; one it doesn't list gets the usual one.
        #expect(ProductRender.imageName(productID: 0x201F, colorID: 0x12) == "B515c-18-Basalt.icns")
        #expect(ProductRender.imageName(productID: 0x201F, colorID: 0x40) == "B515c-19-Stardust.icns")
        #expect(ProductRender.image(productID: 0x2024, colorID: nil) != nil)
        #expect(ProductRender.image(productID: 0x9999, colorID: nil) == nil)
    }

    @Test func turntablePicksTheFramesEitherSideOfTheAngle() throws {
        let turntable = try #require(Turntable.named("AirPodsMax-Starlight"))
        #expect(turntable.frames.count == 120)
        let start = turntable.frames(around: -360)
        #expect(start.first === turntable.frames[0] && start.second === turntable.frames[1] && start.fraction == 0)
        let between = turntable.frames(around: 13.5)
        #expect(between.first === turntable.frames[4] && between.second === turntable.frames[5] && abs(between.fraction - 0.5) < 1e-9)
        let before = turntable.frames(around: -3)
        #expect(before.first === turntable.frames[119] && before.second === turntable.frames[0])
        #expect(Turntable.named("NoSuchModel") == nil)
    }

    @Test func turntableCropsToWhereTheModelReaches() throws {
        // Rendered square; side by side, the AirPods Pro are about twice as wide as tall.
        let pro = try #require(Turntable.named("AirPodsPro"))
        #expect(pro.size.width > 76 && pro.size.width <= 84)
        #expect(pro.size.height < pro.size.width * 0.75)
        #expect(pro.frames.allSatisfy { $0.width == pro.frames[0].width && $0.height == pro.frames[0].height })
    }

    @Test func airPodsMaxTurnInTheirColor() {
        let max = AirPodsModel.airPodsMax
        #expect(max.turntable(productID: 0x201F, colorID: 0x12) == "AirPodsMax-Midnight")
        #expect(max.turntable(productID: 0x200A, colorID: 0x02) == "AirPodsMax-Pink")
        // Not known: the color macOS pictures them in.
        #expect(max.turntable(productID: 0x201F, colorID: nil) == "AirPodsMax-Starlight")
        #expect(max.turntable(productID: 0x200A, colorID: 0x40) == "AirPodsMax-SpaceGray")
        #expect(AirPodsModel.airPodsPro.turntable(productID: 0x2024, colorID: nil).flatMap(Turntable.named) != nil)
        #expect(AirPodsModel.airPods4.turntable(productID: 0x2019, colorID: nil) == nil)
        // The app has every color's.
        for colorID in [0x00, 0x02, 0x03, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16] {
            #expect(max.turntable(productID: 0x201F, colorID: colorID).flatMap(Turntable.named) != nil)
        }
    }

    @Test func airPodsAnimateOnlyWhenTheyConnect() {
        let notch = CGSize(width: 185, height: 32)
        func layout(_ airPods: AirPodsModel?, connected: Bool, animates: Bool = true) -> ActivityLayout {
            LiveActivityKind.bluetooth(BluetoothEvent(
                address: "A", name: "Device", symbol: "airpods", isConnected: connected, airPods: airPods, animatesAirPods: animates
            )).layout(notch: notch)
        }
        // Every model turns into view beside the notch, as on the iPhone.
        #expect(layout(.airPods4, connected: true) == .wings(AirPodsActivityView.wing))
        #expect(layout(.airPodsPro, connected: true) == .wings(AirPodsActivityView.wing))
        #expect(layout(.airPodsMax, connected: true) == .wings(AirPodsActivityView.wing))
        #expect(layout(.beats(productID: 0x2012), connected: true) == .wings(AirPodsActivityView.wing))
        #expect(layout(.airPodsPro, connected: false) == .wings(140))
        #expect(layout(nil, connected: true) == .wings(140))
        // With the animation off in Settings, AirPods fit beside the notch like anything else.
        #expect(layout(.airPodsPro, connected: true, animates: false) == .wings(140))
    }
}

/// Bytes a test's archive handed out.
private actor ByteTally {
    var bytes = 0
    func add(_ count: Int) { bytes += count }
}
