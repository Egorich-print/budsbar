// BudsBar — Huawei FreeBuds control protocol (wire format layer)
// SPDX-License-Identifier: MIT
//
// Wire format facts (magic, framing, CRC, command IDs) were determined by
// black-box observation of a locally owned device plus published
// interoperability documentation. All code here is original.

import Foundation

/// CRC-16/XMODEM: polynomial 0x1021, initial value 0x0000, no reflection.
public enum CRC16 {
    public static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var value: UInt16 = 0
        for byte in bytes {
            value ^= UInt16(byte) << 8
            for _ in 0..<8 {
                value = (value & 0x8000) != 0 ? (value << 1) ^ 0x1021 : value << 1
            }
        }
        return value
    }

    /// Incremental variant for streaming decoders.
    public static func checksum(_ bytes: ArraySlice<UInt8>, seed: UInt16 = 0) -> UInt16 {
        var value = seed
        for byte in bytes {
            value ^= UInt16(byte) << 8
            for _ in 0..<8 {
                value = (value & 0x8000) != 0 ? (value << 1) ^ 0x1021 : value << 1
            }
        }
        return value
    }
}

/// A single decoded frame: a 16-bit command plus TLV fields keyed by tag.
public struct Frame: Equatable, Sendable {
    public let command: UInt16
    public let fields: [UInt8: [UInt8]]

    public init(command: UInt16, fields: [UInt8: [UInt8]] = [:]) {
        self.command = command
        self.fields = fields
    }

    /// Single-byte field value.
    public func byte(_ tag: UInt8) -> UInt8? {
        guard let value = fields[tag], value.count == 1 else { return nil }
        return value[0]
    }

    /// Multi-byte field as a signed integer (device encodes levels as signed bytes).
    public func int(_ tag: UInt8) -> Int? {
        guard let value = fields[tag], !value.isEmpty else { return nil }
        return Int(Int8(bitPattern: value[0]))
    }

    /// Text field, trimmed of control characters.
    public func text(_ tag: UInt8) -> String? {
        guard let value = fields[tag], !value.isEmpty else { return nil }
        guard let string = String(bytes: value, encoding: .utf8) else { return nil }
        let trimmed = string.trimmingCharacters(in: .controlCharacters)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// All field values for a tag interpreted as a list of signed bytes.
    public func byteList(_ tag: UInt8) -> [Int]? {
        guard let value = fields[tag], !value.isEmpty else { return nil }
        return value.map { Int(Int8(bitPattern: $0)) }
    }
}

/// Wire-format encoder/decoder for the Huawei SPP control protocol.
///
/// Frame layout:
///   `0x5A` | length (2, big-endian) | `0x00` | command (2, big-endian)
///   | TLV* | CRC-16/XMODEM (2, big-endian)
///
/// `length` counts the command body plus one, i.e. `2 + Σ(2 + tagValueLength) + 1`.
public enum WireFormat {
    public static let magic: UInt8 = 0x5A
    public static let maxFrameSize = 8192

    /// Encodes a frame into the bytes to write to the transport.
    public static func encode(command: UInt16, fields: [UInt8: [UInt8]] = [:]) -> [UInt8] {
        var body = [UInt8(command >> 8), UInt8(command & 0xFF)]
        for tag in fields.keys.sorted() {
            let value = fields[tag] ?? []
            body.append(tag)
            body.append(UInt8(value.count))
            body.append(contentsOf: value)
        }
        let length = body.count + 1
        var bytes: [UInt8] = [magic, UInt8(length >> 8), UInt8(length & 0xFF), 0x00]
        bytes.append(contentsOf: body)
        let crc = CRC16.checksum(bytes)
        bytes.append(UInt8(crc >> 8))
        bytes.append(UInt8(crc & 0xFF))
        return bytes
    }

    /// Decodes one frame from `buffer` at `index`.
    ///
    /// Returns `nil` when the buffer does not yet hold a complete, CRC-valid frame.
    /// A leading byte that is not the magic marks the buffer as desynchronised;
    /// callers should drop one byte and retry.
    public static func decode(_ buffer: [UInt8], at index: Int = 0) -> Frame? {
        guard buffer.count - index >= 6 else { return nil }
        guard buffer[index] == magic else { return nil }
        guard buffer[index + 3] == 0x00 else { return nil }

        let length = (Int(buffer[index + 1]) << 8) | Int(buffer[index + 2])
        let total = length + 5
        guard (8...maxFrameSize).contains(total) else { return nil }
        guard buffer.count - index >= total else { return nil }

        let frame = Array(buffer[index..<(index + total)])
        let expected = (UInt16(frame[total - 2]) << 8) | UInt16(frame[total - 1])
        guard CRC16.checksum(Array(frame.dropLast(2))) == expected else { return nil }

        var fields: [UInt8: [UInt8]] = [:]
        var cursor = 6
        let payloadEnd = total - 2
        while cursor < payloadEnd {
            guard cursor + 2 <= payloadEnd else { return nil }
            let tag = frame[cursor]
            let size = Int(frame[cursor + 1])
            let end = cursor + 2 + size
            guard end <= payloadEnd, fields[tag] == nil else { return nil }
            fields[tag] = Array(frame[(cursor + 2)..<end])
            cursor = end
        }
        return Frame(command: (UInt16(frame[4]) << 8) | UInt16(frame[5]), fields: fields)
    }
}

/// Streaming frame decoder that tolerates arbitrary chunk boundaries.
public struct FrameStreamDecoder {
    private var buffer: [UInt8] = []

    public init() {}

    /// Feeds a chunk and returns every complete frame it produced.
    public mutating func consume(_ chunk: [UInt8]) -> [Frame] {
        buffer.append(contentsOf: chunk)
        var frames: [Frame] = []

        while buffer.count >= 6 {
            if buffer[0] != WireFormat.magic {
                buffer.removeFirst()
                continue
            }
            let length = (Int(buffer[1]) << 8) | Int(buffer[2])
            let total = length + 5
            guard (8...WireFormat.maxFrameSize).contains(total), buffer[3] == 0x00 else {
                buffer.removeFirst()
                continue
            }
            guard buffer.count >= total else { break }

            let candidate = Array(buffer.prefix(total))
            buffer.removeFirst(total)
            if let frame = WireFormat.decode(candidate, at: 0) {
                frames.append(frame)
            }
        }

        if buffer.count > WireFormat.maxFrameSize {
            buffer.removeAll(keepingCapacity: true)
        }
        return frames
    }

    public mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
    }
}
