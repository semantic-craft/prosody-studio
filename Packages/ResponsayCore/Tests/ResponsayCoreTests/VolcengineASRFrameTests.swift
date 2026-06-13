import Testing
import Foundation
@testable import ResponsayCore

/// Binary frame codec for Volcengine 火山引擎 大模型流式 ASR (SAUC bigmodel).
/// Ported from the openless Rust `asr::frame` (itself a port of the original
/// Swift). Frame = 4-byte header + optional i32 sequence + 4-byte big-endian
/// payload size + payload; client always declares "no compression".
@Suite struct VolcengineASRFrameTests {
    @Test func roundTripFullClientRequestWithPositiveSequence() throws {
        let payload = Data("hi".utf8)
        let frame = VolcengineASRFrame.build(
            messageType: .fullClientRequest,
            flags: .positiveSequence,
            serialization: .json,
            payload: payload,
            sequence: 1)
        let parsed = try #require(VolcengineASRFrame.parse(frame))
        #expect(parsed.messageType == .fullClientRequest)
        #expect(parsed.flags == VolcFlags.positiveSequence.rawValue)
        #expect(parsed.sequence == 1)
        #expect(parsed.errorCode == nil)
        #expect(parsed.payload == payload)
        #expect(parsed.isFinal == false)
    }

    @Test func roundTripAudioOnlyWithLastPacketIsFinal() throws {
        let frame = VolcengineASRFrame.build(
            messageType: .audioOnlyRequest,
            flags: .lastPacket,
            serialization: .none,
            payload: Data(),
            sequence: nil)
        let parsed = try #require(VolcengineASRFrame.parse(frame))
        #expect(parsed.messageType == .audioOnlyRequest)
        #expect(parsed.flags == VolcFlags.lastPacket.rawValue)
        #expect(parsed.sequence == nil)
        #expect(parsed.payload.isEmpty)
        #expect(parsed.isFinal)
    }

    @Test func parseReturnsNilOnTruncatedBuffer() {
        #expect(VolcengineASRFrame.parse(Data(count: 4)) == nil)
    }

    @Test func roundTripNegativeSequenceIsFinal() throws {
        let frame = VolcengineASRFrame.build(
            messageType: .audioOnlyRequest,
            flags: .negativeSequence,
            serialization: .none,
            payload: Data(),
            sequence: -5)
        let parsed = try #require(VolcengineASRFrame.parse(frame))
        #expect(parsed.sequence == -5)
        #expect(parsed.isFinal)
    }

    @Test func roundTripErrorMessage() throws {
        // Manually craft an ErrorMessage frame: header + code(BE u32) + size(BE u32) + body.
        let body = Data("boom".utf8)
        var frame = Data()
        frame.append(0x11)
        frame.append((VolcMessageType.errorMessage.rawValue << 4) | VolcFlags.none.rawValue)
        frame.append((VolcSerialization.none.rawValue << 4) | 0b0000)
        frame.append(0x00)
        frame.append(contentsOf: UInt32(123).bigEndianBytes)
        frame.append(contentsOf: UInt32(body.count).bigEndianBytes)
        frame.append(body)

        let parsed = try #require(VolcengineASRFrame.parse(frame))
        #expect(parsed.messageType == .errorMessage)
        #expect(parsed.errorCode == 123)
        #expect(parsed.payload == body)
    }

    @Test func positiveSequenceAudioFrameIsNotFinal() throws {
        let frame = VolcengineASRFrame.build(
            messageType: .audioOnlyRequest,
            flags: .positiveSequence,
            serialization: .none,
            payload: Data([0x01, 0x02]),
            sequence: 7)
        let parsed = try #require(VolcengineASRFrame.parse(frame))
        #expect(parsed.sequence == 7)
        #expect(parsed.isFinal == false)
    }

    // MARK: - Compression self-consistency (issue 287)

    /// Audio frames must declare no-compression (openless's deliberate design):
    /// the server echoes the client's compression mode, and `parse()` only
    /// accepts uncompressed frames — so declaring gzip would make every server
    /// response undecodable. This pins the compression nibble to 0b0000.
    @Test func audioFramesAreNeverCompressed() {
        let pcm = Data(repeating: 0xAB, count: 6400)
        let frame = VolcengineASRFrame.build(
            messageType: .audioOnlyRequest,
            flags: .positiveSequence,
            serialization: .none,
            payload: pcm,
            sequence: 1)
        let bytes = [UInt8](frame)
        #expect(bytes[2] & 0x0F == 0b0000)
        // Payload travels verbatim: size field == raw PCM size.
        let sizeField = bytes[8..<12].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        #expect(sizeField == UInt32(pcm.count))
    }

    /// `flags == none` omits the sequence on the wire even if a value is passed —
    /// only positive/negative sequence frames carry it (matches the Rust/Swift codec).
    @Test func noneFlagsOmitSequenceOnWire() throws {
        let frame = VolcengineASRFrame.build(
            messageType: .fullClientRequest,
            flags: .none,
            serialization: .json,
            payload: Data("x".utf8),
            sequence: 99)
        let parsed = try #require(VolcengineASRFrame.parse(frame))
        #expect(parsed.sequence == nil)
        #expect(parsed.payload == Data("x".utf8))
    }
}

private extension UInt32 {
    var bigEndianBytes: [UInt8] {
        [UInt8(truncatingIfNeeded: self >> 24),
         UInt8(truncatingIfNeeded: self >> 16),
         UInt8(truncatingIfNeeded: self >> 8),
         UInt8(truncatingIfNeeded: self)]
    }
}
