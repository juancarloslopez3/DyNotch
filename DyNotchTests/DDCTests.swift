import Foundation
import Synchronization
import Testing

@testable import DyNotch

struct DDCTests {
    @Test func setRequestFollowsTheStandard() {
        // Brightness to 50: the length, "Set VCP Feature", the code, the value high byte first, and
        // a checksum over every byte on the wire, the display's address (0x6E) and the host's (0x51)
        // included.
        #expect(DDC.setRequest(DDC.brightness, value: 50) == [0x84, 0x03, 0x10, 0x00, 0x32, 0x9A])
        #expect(DDC.setRequest(DDC.brightness, value: 0x1234) == [0x84, 0x03, 0x10, 0x12, 0x34, 0x8E])
    }

    @Test func getRequestChecksumsTheHostAddressToo() {
        #expect(DDC.getRequest(DDC.brightness) == [0x82, 0x01, 0x10, 0xAC])
    }

    @Test func everyMessageXORsToZeroWithBothAddresses() {
        for message in [DDC.getRequest(0x12), DDC.setRequest(0x62, value: 0xFFFF), DDC.setRequest(0x10, value: 0)] {
            #expect(message.reduce(0x6E ^ 0x51, ^) == 0)
        }
    }

    /// A display's answer to "Get VCP Feature" for its brightness, at 37 of 100.
    private let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x25, 0xE5]

    @Test func readsTheValueAndMaximumFromAReply() {
        #expect(DDC.value(inReply: reply, for: DDC.brightness) == DDC.Value(current: 37, maximum: 100))
        // Both high bytes count.
        let wide = resealed(reply, [6: 0x01, 7: 0x00, 8: 0x00, 9: 0xC8])
        #expect(DDC.value(inReply: wide, for: DDC.brightness) == DDC.Value(current: 200, maximum: 256))
    }

    @Test func turnsDownRepliesThatArentSound() {
        var damaged = reply
        damaged[9] = 0x26
        #expect(DDC.value(inReply: damaged, for: DDC.brightness) == nil)
        // About another code, about a code the display hasn't got, or with no scale.
        #expect(DDC.value(inReply: resealed(reply, [4: 0x12]), for: DDC.brightness) == nil)
        #expect(DDC.value(inReply: resealed(reply, [3: 0x01]), for: DDC.brightness) == nil)
        #expect(DDC.value(inReply: resealed(reply, [7: 0x00]), for: DDC.brightness) == nil)
        // Cut short, or nothing on the bus.
        #expect(DDC.value(inReply: Array(reply.dropLast()), for: DDC.brightness) == nil)
        #expect(DDC.value(inReply: [UInt8](repeating: 0xFF, count: DDC.replyLength), for: DDC.brightness) == nil)
    }

    @Test func theLeadIsTheDisplayTheHUDShows() {
        #expect(BrightnessTarget.display(5).lead == 5)
        #expect(BrightnessTarget.all(lead: 3).lead == 3)
    }

    @Test func aBurstOfLevelsSendsTheNewest() async {
        let bus = FakeBus(reply: reply)
        let channel = DDCChannel(framebuffer: "", bus: bus, route: .standard)
        for value in UInt16(1)...100 { channel.write(DDC.brightness, value: value) }
        // A read waits for what's being sent.
        _ = await channel.read(DDC.brightness)
        let sets = bus.writes.filter { $0.bytes.first == 0x84 }
        #expect(sets.last?.bytes == DDC.setRequest(DDC.brightness, value: 100))
        #expect(sets.count < 20)
        #expect(sets.allSatisfy { $0.address == 0x37 && $0.offset == 0x51 })
    }

    @Test func readsTheWayEachRouteNeeds() async {
        let bus = FakeBus(reply: reply)
        let channel = DDCChannel(framebuffer: "", bus: bus, route: .standard)
        #expect(await channel.read(DDC.brightness) == DDC.Value(current: 37, maximum: 100))
        #expect(bus.writes.first == FakeBus.Write(bytes: DDC.getRequest(DDC.brightness), address: 0x37, offset: 0x51))
        #expect(bus.reads == [FakeBus.Read(count: 11, address: 0x37, offset: 0)])

        // Through the MCDP29xx behind some Macs' HDMI port, as m1ddc reads it.
        let hdmi = FakeBus(reply: reply)
        let throughHDMI = DDCChannel(framebuffer: "", bus: hdmi, route: .mcdp29xx)
        #expect(await throughHDMI.read(DDC.brightness) == DDC.Value(current: 37, maximum: 100))
        #expect(hdmi.writes.first?.address == 0xB7)
        #expect(hdmi.reads == [FakeBus.Read(count: 12, address: 0xB7, offset: 0x51)])
    }

    @Test func aDisplayThatDoesntAnswerIsAskedAFewTimes() async {
        let bus = FakeBus()
        let channel = DDCChannel(framebuffer: "", bus: bus, route: .standard)
        #expect(await channel.read(DDC.brightness) == nil)
        #expect(bus.reads.count == 5)
    }

    /// `reply` with some bytes changed and its checksum made right again.
    private func resealed(_ reply: [UInt8], _ changes: [Int: UInt8]) -> [UInt8] {
        var reply = reply
        for (index, byte) in changes { reply[index] = byte }
        reply[reply.count - 1] = reply.dropLast().reduce(0x50, ^)
        return reply
    }
}

/// A display on a stand-in bus: notes every write and read, and answers reads with `reply`.
nonisolated private final class FakeBus: I2CBus {
    struct Write: Equatable {
        var bytes: [UInt8]
        var address: UInt8
        var offset: UInt8
    }

    struct Read: Equatable {
        var count: Int
        var address: UInt8
        var offset: UInt8
    }

    private let reply: [UInt8]?
    private let log = Mutex<(writes: [Write], reads: [Read])>(([], []))

    init(reply: [UInt8]? = nil) {
        self.reply = reply
    }

    var writes: [Write] { log.withLock { $0.writes } }
    var reads: [Read] { log.withLock { $0.reads } }

    func write(_ bytes: [UInt8], to address: UInt8, offset: UInt8) -> Bool {
        log.withLock { $0.writes.append(Write(bytes: bytes, address: address, offset: offset)) }
        return true
    }

    func read(_ count: Int, from address: UInt8, offset: UInt8) -> [UInt8]? {
        log.withLock { $0.reads.append(Read(count: count, address: address, offset: offset)) }
        // With nothing answering, the bus reads high.
        let answer = reply ?? []
        return Array((answer + [UInt8](repeating: 0xFF, count: count)).prefix(count))
    }
}
