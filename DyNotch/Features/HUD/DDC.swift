import Foundation
import IOKit
import Synchronization

/// DDC/CI, which displays take their settings over through the video cable, as VESA defines it:
/// the messages to send and the replies to read.
nonisolated enum DDC {
    /// The VCP code of a display's brightness ("luminance").
    static let brightness: UInt8 = 0x10
    /// The display's I²C address (7-bit), and the host's, which starts every message sent.
    static let displayAddress: UInt8 = 0x37
    static let hostAddress: UInt8 = 0x51
    /// The length of a reply to "Get VCP Feature", from the display's address to the checksum.
    static let replyLength = 11

    /// A VCP feature's value, and how high it goes.
    struct Value: Equatable, Sendable {
        var current: UInt16
        var maximum: UInt16
    }

    /// "Set VCP Feature": `code` to `value`.
    static func setRequest(_ code: UInt8, value: UInt16) -> [UInt8] {
        message([0x03, code, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    /// "Get VCP Feature": asks for `code`'s value.
    static func getRequest(_ code: UInt8) -> [UInt8] {
        message([0x01, code])
    }

    /// What follows the host's address: the length, `payload`, and a checksum that XORs every byte
    /// of the message, both addresses included. (MonitorControl and m1ddc leave the host's out of
    /// their requests for a value; displays that check need it.)
    private static func message(_ payload: [UInt8]) -> [UInt8] {
        let bytes = [0x80 | UInt8(payload.count)] + payload
        return bytes + [bytes.reduce((displayAddress << 1) ^ hostAddress, ^)]
    }

    /// The value in a reply to "Get VCP Feature" for `code`, or nil if it's damaged, about another
    /// code, or says the display hasn't got it.
    static func value(inReply reply: [UInt8], for code: UInt8) -> Value? {
        // From the display's address: the length, the opcode (0x02), the result (0 when the code is
        // supported), the code, its type, then the maximum and current value, high byte first. A
        // reply's checksum starts from 0x50 for the host.
        guard reply.count == replyLength,
              reply.dropLast().reduce(0x50, ^) == reply[replyLength - 1],
              reply[2] == 0x02, reply[3] == 0x00, reply[4] == code
        else { return nil }
        let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
        guard maximum > 0 else { return nil }
        return Value(current: UInt16(reply[8]) << 8 | UInt16(reply[9]), maximum: maximum)
    }
}

/// The I²C bus a display's DDC/CI goes over: its AV service, or a stand-in in tests.
nonisolated protocol I2CBus: Sendable {
    /// Writes `bytes` to the device at the (7-bit) I²C `address`, after a first byte `offset`.
    func write(_ bytes: [UInt8], to address: UInt8, offset: UInt8) -> Bool
    /// Reads `count` bytes from the device at the (7-bit) I²C `address`.
    func read(_ count: Int, from address: UInt8, offset: UInt8) -> [UInt8]?
}

/// Talks DDC/CI with one external display, on a queue of its own: each exchange takes tens of
/// milliseconds, and a read that goes unanswered half a second.
nonisolated final class DDCChannel: @unchecked Sendable {
    /// How a display's DDC/CI is reached.
    struct Route: Equatable {
        /// Where it answers on the I²C bus: at 0x37 as the standard says, or at 0xB7 through the
        /// MCDP29xx chip that turns some Macs' DisplayPort into their HDMI port.
        var address: UInt8
        /// What a read starts from, and how many bytes it takes.
        var readOffset: UInt8
        var readLength: Int

        /// As MonitorControl reads.
        static let standard = Route(address: DDC.displayAddress, readOffset: 0, readLength: DDC.replyLength)
        /// As m1ddc reads through the MCDP29xx.
        static let mcdp29xx = Route(address: 0xB7, readOffset: DDC.hostAddress, readLength: DDC.replyLength + 1)
    }

    /// The display's framebuffer in the I/O Registry, which is how CoreDisplay names it too.
    let framebuffer: String
    let route: Route
    private let bus: any I2CBus
    private let queue = DispatchQueue(label: "app.dynotch.ddc", qos: .userInitiated)
    /// The values waiting to be sent, by VCP code. Only the newest of each waits, so a held key
    /// or a dragged slider never leaves a backlog of old ones to send.
    private let pending = Mutex([UInt8: UInt16]())

    // MonitorControl's timings: every message goes twice, as some displays miss the first, and a
    // reply is read a moment after asking.
    private static let sendDelay: useconds_t = 10_000
    private static let replyDelay: useconds_t = 50_000
    private static let retryDelay: useconds_t = 20_000
    private static let attempts = 5

    init(framebuffer: String, bus: any I2CBus, route: Route) {
        self.framebuffer = framebuffer
        self.bus = bus
        self.route = route
    }

    /// Sets VCP feature `code` to `value`, once what's under way is through.
    func write(_ code: UInt8, value: UInt16) {
        let isIdle = pending.withLock { pending in
            let isIdle = pending.isEmpty
            pending[code] = value
            return isIdle
        }
        if isIdle { queue.async { self.sendPending() } }
    }

    /// VCP feature `code`'s value, or nil if the display doesn't answer.
    func read(_ code: UInt8) async -> DDC.Value? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.ask(code)) }
        }
    }

    private func sendPending() {
        while let next = pending.withLock({ $0.popFirst() }) {
            for attempt in 0..<Self.attempts {
                if attempt > 0 { usleep(Self.retryDelay) }
                if send(DDC.setRequest(next.key, value: next.value)) { break }
            }
        }
    }

    private func ask(_ code: UInt8) -> DDC.Value? {
        let request = DDC.getRequest(code)
        for attempt in 0..<Self.attempts {
            if attempt > 0 { usleep(Self.retryDelay) }
            send(request)
            usleep(Self.replyDelay)
            if let reply = bus.read(route.readLength, from: route.address, offset: route.readOffset),
               let value = DDC.value(inReply: Array(reply.prefix(DDC.replyLength)), for: code) {
                return value
            }
        }
        return nil
    }

    /// Sends `message` twice; true if the second went through.
    @discardableResult
    private func send(_ message: [UInt8]) -> Bool {
        var sent = false
        for _ in 0..<2 {
            usleep(Self.sendDelay)
            sent = bus.write(message, to: route.address, offset: DDC.hostAddress)
        }
        return sent
    }
}

nonisolated extension DDCChannel {
    /// A channel to every external display, from the I/O Registry: Apple silicon gives each display
    /// a `DCPAVServiceProxy`, listed after the framebuffer it serves, which is how MonitorControl
    /// pairs them. Walks some 2,000 entries in 10–20 ms, so it runs off the main thread.
    static func discover() -> [DDCChannel] {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }

        let name = UnsafeMutablePointer<CChar>.allocate(capacity: MemoryLayout<io_name_t>.size)
        defer { name.deallocate() }
        var channels: [DDCChannel] = []
        var framebuffer: String?
        while case let entry = IOIteratorNext(iterator), entry != IO_OBJECT_NULL {
            defer { IOObjectRelease(entry) }
            guard IORegistryEntryGetName(entry, name) == KERN_SUCCESS else { continue }
            switch String(cString: name) {
            case "AppleCLCD2", "IOMobileFramebufferShim":
                framebuffer = IORegistryEntryCopyPath(entry, kIOServicePlane)?.takeRetainedValue() as String?
            case "DCPAVServiceProxy":
                // The built-in display's is "Embedded".
                guard let framebuffer, property("Location", of: entry) == "External",
                      let service = IOAVService(entry)
                else { continue }
                let route: Route = isBehindMCDP29XX(entry) ? .mcdp29xx : .standard
                channels.append(DDCChannel(framebuffer: framebuffer, bus: service, route: route))
            default:
                break
            }
        }
        return channels
    }

    /// The MCDP29xx shows as the provider of the proxy's endpoint, which is how m1ddc tells it.
    private static func isBehindMCDP29XX(_ proxy: io_registry_entry_t) -> Bool {
        var parent = io_registry_entry_t()
        guard IORegistryEntryGetParentEntry(proxy, kIOServicePlane, &parent) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(parent) }
        return property("EPICProviderClass", of: parent) == "AppleDCPMCDP29XX"
    }

    private static func property(_ key: String, of entry: io_registry_entry_t) -> String? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
    }
}
