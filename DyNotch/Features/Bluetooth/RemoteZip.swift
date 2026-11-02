import Compression
import Foundation

/// A zip archive read a piece at a time from a server that answers range requests: the index at its
/// end first, then only the members wanted. Apple's asset archives keep each video compressed on its
/// own, so `DeviceArt` fetches the one clip it turns (~1.5 MB) rather than the whole archive (up to
/// 20 MB), and has it soon enough to show while the device is still on screen.
nonisolated struct RemoteZip: Sendable {
    /// Bytes of the archive: its last few, or those in a range.
    nonisolated enum Bytes: Equatable, Sendable {
        case last(Int)
        case range(Range<Int>)
    }

    /// Reads bytes of the archive. Past its end, it gives what there is.
    typealias Reader = @Sendable (Bytes) async throws -> Data

    nonisolated struct Member: Equatable, Sendable {
        let name: String
        /// 0 stored, 8 deflated.
        let method: Int
        let crc: UInt32
        let compressedSize: Int
        let size: Int
        /// Where its local header starts.
        let offset: Int
    }

    let members: [Member]
    private let read: Reader

    /// Reads the archive's index.
    static func open(_ read: @escaping Reader) async throws -> RemoteZip {
        // The end-of-index record is the last 22 bytes, but for a comment of up to 64 KB after it.
        let tail = try await read(.last(64 * 1024))
        guard let end = endOfIndex(in: tail) else { throw CocoaError(.fileReadCorruptFile) }
        // The record comes right after the index, so the tail starts this far into the archive.
        let tailStart = end.indexOffset + end.indexSize - end.position
        let index = end.indexOffset >= tailStart
            ? tail.subdata(in: (tail.startIndex + end.indexOffset - tailStart)..<(tail.startIndex + end.position))
            : try await read(.range(end.indexOffset..<(end.indexOffset + end.indexSize)))
        return RemoteZip(members: members(inIndex: index), read: read)
    }

    /// The member's contents, checked against its CRC.
    func data(of member: Member) async throws -> Data {
        // The local header's name and extra field can be longer than the index says: read a little
        // over, then make sure.
        let likely = 30 + member.name.utf8.count + 256
        var chunk = try await read(.range(member.offset..<(member.offset + likely + member.compressedSize)))
        guard chunk.count >= 30, Self.uint32(chunk, 0) == 0x0403_4B50 else { throw CocoaError(.fileReadCorruptFile) }
        let start = 30 + Self.uint16(chunk, 26) + Self.uint16(chunk, 28)
        if start + member.compressedSize > chunk.count {
            chunk = try await read(.range(member.offset..<(member.offset + start + member.compressedSize)))
        }
        guard start + member.compressedSize <= chunk.count else { throw CocoaError(.fileReadCorruptFile) }
        let compressed = chunk.subdata(in: (chunk.startIndex + start)..<(chunk.startIndex + start + member.compressedSize))
        let data: Data? = switch member.method {
        case 0: compressed
        case 8: Self.inflate(compressed, size: member.size)
        default: nil
        }
        guard let data, data.count == member.size, Self.crc32(data) == member.crc else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }

    /// Reads ranges of the archive at `url`. Should the server send the whole of it instead, the
    /// part asked for.
    static func reader(for url: URL) -> Reader {
        { bytes in
            let range = switch bytes {
            case .last(let count): "bytes=-\(count)"
            case .range(let range): "bytes=\(range.lowerBound)-\(range.upperBound - 1)"
            }
            var request = URLRequest(url: url)
            request.setValue(range, forHTTPHeaderField: "Range")
            let (data, response) = try await URLSession.shared.data(for: request)
            switch (response as? HTTPURLResponse)?.statusCode {
            case 206: return data
            case 200: return slice(data, bytes)
            default: throw URLError(.badServerResponse)
            }
        }
    }

    /// Those bytes of a whole archive.
    static func slice(_ archive: Data, _ bytes: Bytes) -> Data {
        switch bytes {
        case .last(let count): Data(archive.suffix(count))
        case .range(let range): archive.subdata(in: min(range.lowerBound, archive.count)..<min(range.upperBound, archive.count))
        }
    }

    // MARK: - Format

    /// The end-of-index record: where it is in `tail`, and where the index is in the archive. Nil
    /// if there's none, or the archive is Zip64.
    static func endOfIndex(in tail: Data) -> (position: Int, indexSize: Int, indexOffset: Int)? {
        guard tail.count >= 22 else { return nil }
        for position in stride(from: tail.count - 22, through: 0, by: -1) where uint32(tail, position) == 0x0605_4B50 {
            let size = uint32(tail, position + 12), offset = uint32(tail, position + 16)
            guard offset != 0xFFFF_FFFF else { return nil }
            return (position, Int(size), Int(offset))
        }
        return nil
    }

    static func members(inIndex index: Data) -> [Member] {
        var members: [Member] = []
        var position = 0
        while position + 46 <= index.count, uint32(index, position) == 0x0201_4B50 {
            let nameLength = uint16(index, position + 28)
            let next = position + 46 + nameLength + uint16(index, position + 30) + uint16(index, position + 32)
            guard next <= index.count else { break }
            members.append(Member(
                name: String(decoding: index.subdata(in: (index.startIndex + position + 46)..<(index.startIndex + position + 46 + nameLength)), as: UTF8.self),
                method: uint16(index, position + 10),
                crc: uint32(index, position + 16),
                compressedSize: Int(uint32(index, position + 20)),
                size: Int(uint32(index, position + 24)),
                offset: Int(uint32(index, position + 42))
            ))
            position = next
        }
        return members
    }

    /// Raw DEFLATE, as zip keeps it.
    static func inflate(_ data: Data, size: Int) -> Data? {
        guard size > 0, !data.isEmpty else { return size == 0 ? Data() : nil }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { output in
            data.withUnsafeBytes { input in
                compression_decode_buffer(
                    output.bindMemory(to: UInt8.self).baseAddress!, size,
                    input.bindMemory(to: UInt8.self).baseAddress!, input.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        return written == size ? output : nil
    }

    private static let crcTable: [UInt32] = (0..<256).map { byte in
        (0..<8).reduce(UInt32(byte)) { crc, _ in crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
    }

    static func crc32(_ data: Data) -> UInt32 {
        ~data.reduce(~UInt32(0)) { crc, byte in crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
    }

    private static func uint16(_ data: Data, _ at: Int) -> Int {
        Int(data[data.startIndex + at]) | Int(data[data.startIndex + at + 1]) << 8
    }

    private static func uint32(_ data: Data, _ at: Int) -> UInt32 {
        (0..<4).reduce(0) { value, byte in value | UInt32(data[data.startIndex + at + byte]) << (8 * byte) }
    }
}
