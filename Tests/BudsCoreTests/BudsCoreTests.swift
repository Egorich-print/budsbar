// BudsBar — protocol unit tests
// SPDX-License-Identifier: MIT

import Testing
@testable import BudsCore

@Suite("Wire format")
struct WireFormatTests {

    /// A frame captured from a real device, verified byte for byte.
    @Test("Encodes a known frame")
    func encodesKnownFrame() {
        // ANC status query: command 0x2b2a, tags 1 and 2.
        let bytes = WireFormat.encode(command: 0x2B2A, fields: [1: [], 2: []])
        #expect(bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
                == "5a 00 07 00 2b 2a 01 00 02 00 1d 33")
    }

    @Test("Decodes a frame captured from a real device")
    func decodesKnownFrame() {
        // Captured from HUAWEI FreeBuds 6 (model BTFT0020) on the control channel.
        let hex = "5a 00 97 00 01 07 02 02 01 55 03 0d 48 4c 31 48 36 4d 52 5f 56 65 72 2e 41"
            + " 07 20 48 61 72 6d 6f 6e 79 4f 53 20 36 2e 31 2e 30 2e 33 35 38 28 46 30 30 33 48 30 30 33 43 39 30 29"
            + " 09 10 33 45 44 42 42 32 35 36 32 31 31 30 32 31 30 35 0a 0f 42 54 46 54 30 30 32 30 2d 30 30 30 31 35 35"
            + " 0f 08 42 54 46 54 30 30 32 30 18 25 4c 2d 42 42 30 34 33 36 32 35 35 4e 41 30 30 38 39 32 2c 52 2d 42 42 30 34 35 32 32 35 34 50 41 31 38 31 33 34"
            + " 19 01 01 1b 06 36 e1 fe 98 a9 30 9c f6"
        let bytes = hex.split(separator: " ").compactMap { UInt8($0, radix: 16) }
        let frame = WireFormat.decode(bytes)
        #expect(frame != nil)
        #expect(frame?.command == 0x0107)
        #expect(frame?.text(3) == "HL1H6MR_Ver.A")
        #expect(frame?.text(15) == "BTFT0020")
        // Field 2 carries two bytes, so the single-byte accessor declines it.
        #expect(frame?.fields[2] == [0x01, 0x55])
        #expect(frame?.byte(2) == nil)
    }

    @Test("Rejects a frame with a bad checksum")
    func rejectsBadChecksum() {
        var bytes = WireFormat.encode(command: 0x0108, fields: [1: [], 2: []])
        bytes[bytes.count - 1] ^= 0xFF
        #expect(WireFormat.decode(bytes) == nil)
    }

    @Test("Rejects a frame with the wrong magic byte")
    func rejectsWrongMagic() {
        var bytes = WireFormat.encode(command: 0x0108)
        bytes[0] = 0x00
        #expect(WireFormat.decode(bytes) == nil)
    }

    @Test("Length field excludes the checksum")
    func lengthExcludesChecksum() {
        let bytes = WireFormat.encode(command: 0x0108, fields: [1: [], 2: [], 3: []])
        let length = (Int(bytes[1]) << 8) | Int(bytes[2])
        #expect(length == 2 + 6 + 1)
        #expect(bytes.count == length + 5)
    }

    @Test("CRC matches the XMODEM check vector")
    func crcKnownVector() {
        // CRC-16/XMODEM of "123456789" is 0x31C3.
        #expect(CRC16.checksum(Array("123456789".utf8)) == 0x31C3)
    }
}

@Suite("Streaming decoder")
struct FrameStreamDecoderTests {

    @Test("Reassembles a frame split across chunks")
    func reassemblesSplitFrames() {
        var decoder = FrameStreamDecoder()
        let frame = WireFormat.encode(command: 0x0108, fields: [1: [], 2: [], 3: []])
        #expect(decoder.consume(Array(frame.prefix(4))).isEmpty)
        let frames = decoder.consume(Array(frame.dropFirst(4)))
        #expect(frames.count == 1)
        #expect(frames.first?.command == 0x0108)
    }

    @Test("Decodes two frames delivered in one chunk")
    func decodesTwoFramesInOneChunk() {
        var decoder = FrameStreamDecoder()
        let first = WireFormat.encode(command: 0x0108)
        let second = WireFormat.encode(command: 0x2B2A)
        let frames = decoder.consume(first + second)
        #expect(frames.count == 2)
        #expect(frames.map(\.command) == [0x0108, 0x2B2A])
    }

    @Test("Resynchronises after leading garbage")
    func resynchronisesAfterGarbage() {
        var decoder = FrameStreamDecoder()
        let frame = WireFormat.encode(command: 0x0108)
        let frames = decoder.consume([0xAA, 0xBB, 0xCC] + frame)
        #expect(frames.count == 1)
    }
}

@Suite("Command catalogue")
struct CommandTests {

    @Test("Noise mode write uses mode then strength")
    func noiseModeWriteFormat() {
        let request = ProtocolCatalogue.setNoiseMode(.cancellation)
        #expect(request.command == 0x2B04)
        #expect(request.fields[1] == [0x01, 0xFF])
    }

    @Test("Noise mode off writes zero strength")
    func noiseModeOffFormat() {
        let request = ProtocolCatalogue.setNoiseMode(.off)
        #expect(request.fields[1] == [0x00, 0x00])
    }

    @Test("Equalizer write targets the first field")
    func equalizerWriteFormat() {
        let request = ProtocolCatalogue.setEqualizer(2)
        #expect(request.command == 0x2B49)
        #expect(request.fields[1] == [0x02])
    }

    @Test("Gesture write targets the field of the chosen earbud")
    func gestureWriteFormat() {
        let right = ProtocolCatalogue.setDoubleTap(side: .right, action: 7)
        #expect(right.command == 0x011F)
        #expect(right.fields[2] == [0x07])
        #expect(right.fields[1] == nil)

        let left = ProtocolCatalogue.setDoubleTap(side: .left, action: 1)
        #expect(left.fields[1] == [0x01])
    }

    @Test("Low latency shares one command id for read and write")
    func lowLatencyCommand() {
        let request = ProtocolCatalogue.setLowLatency(true)
        #expect(request.command == Command.lowLatency)
        #expect(request.fields[1] == [0x01])
    }
}
