import Compression
import Foundation

/// 火山引擎 (Volcengine) 大模型流式 ASR 二进制帧编解码。
///
/// 帧结构：4 字节 header + 可选 i32 sequence + 4 字节大端 payload size + payload。
/// 为避免依赖 gzip，这里显式声明 *no compression*；官方协议允许客户端选择不压缩，
/// 服务端会沿用客户端声明的压缩方式。
///
/// Ported from the openless Rust `asr::frame` (itself a direct port of the
/// original Swift `VolcengineStreamingASR`); the protocol quirks are preserved
/// verbatim — see `VolcParsedFrame.isFinal` for the "stream end" rule.

enum VolcMessageType: UInt8 {
    case fullClientRequest = 0b0001
    case audioOnlyRequest = 0b0010
    case fullServerResponse = 0b1001
    case errorMessage = 0b1111

    static func from(raw: UInt8) -> VolcMessageType? {
        VolcMessageType(rawValue: raw)
    }
}

enum VolcFlags: UInt8 {
    case none = 0b0000
    case positiveSequence = 0b0001
    case lastPacket = 0b0010
    case negativeSequence = 0b0011
}

enum VolcSerialization: UInt8 {
    case none = 0b0000
    case json = 0b0001
}

struct VolcParsedFrame: Equatable {
    var messageType: VolcMessageType?
    var flags: UInt8
    var sequence: Int32?
    var errorCode: UInt32?
    var payload: Data

    /// Stream end is signalled ONLY by the frame header — `lastPacket`,
    /// `negativeSequence`, or a negative sequence number. Crucially NOT by an
    /// `utterance.definite=true` in the payload: that just means "this segment is
    /// fixed", the user may still be talking. Trusting `definite` ended the
    /// receive loop early and dropped trailing speech (the original 9-second
    /// loss bug). See `VolcengineASRProtocol` result extraction.
    var isFinal: Bool {
        flags == VolcFlags.lastPacket.rawValue
            || flags == VolcFlags.negativeSequence.rawValue
            || (sequence ?? 0) < 0
    }
}

enum VolcengineASRFrame {
    private static let headerByte0: UInt8 = 0x11 // header_size = 1 * 4 = 4 bytes, version = 1
    private static let compressionNone: UInt8 = 0b0000
    // Deliberately no gzip support, mirroring openless: the client declares
    // no-compression, the server echoes the client's mode, so parse() never
    // sees a compressed frame. A raw-deflate-as-"gzip" variant existed briefly
    // (issue 269) but broke that self-consistency and was removed (issue 287).

    /// Build a single binary frame. `sequence` is only emitted onto the wire when
    /// `flags` is `.positiveSequence` or `.negativeSequence`.
    static func build(
        messageType: VolcMessageType,
        flags: VolcFlags,
        serialization: VolcSerialization,
        payload: Data,
        sequence: Int32?
    ) -> Data {
        var frame = Data(capacity: 4 + 4 + 4 + payload.count)
        frame.append(headerByte0)
        frame.append((messageType.rawValue << 4) | flags.rawValue)
        frame.append((serialization.rawValue << 4) | compressionNone)
        frame.append(0x00)

        let needsSequence = flags == .positiveSequence || flags == .negativeSequence
        if needsSequence, let sequence {
            // i32 → big-endian (preserves the sign as a two's-complement bit pattern).
            frame.append(contentsOf: Self.bigEndianBytes(UInt32(bitPattern: sequence)))
        }

        frame.append(contentsOf: Self.bigEndianBytes(UInt32(payload.count)))
        frame.append(payload)
        return frame
    }

    /// Parse a binary frame received from the server. Returns `nil` if the buffer
    /// is truncated, mis-framed, or uses an unsupported compression mode.
    static func parse(_ data: Data) -> VolcParsedFrame? {
        let bytes = [UInt8](data)
        guard bytes.count >= 8 else { return nil }

        let headerSize = Int(bytes[0] & 0x0F) * 4
        guard headerSize >= 4, bytes.count >= headerSize + 4 else { return nil }

        let messageType = VolcMessageType.from(raw: (bytes[1] >> 4) & 0x0F)
        let flagsRaw = bytes[1] & 0x0F
        let compression = bytes[2] & 0x0F
        guard compression == compressionNone else { return nil }

        var offset = headerSize
        var sequence: Int32?

        if Self.hasSequence(flagsRaw) {
            guard let value = Self.readUInt32(bytes, offset) else { return nil }
            sequence = Int32(bitPattern: value)
            offset += 4
        }

        if messageType == .errorMessage {
            guard let code = Self.readUInt32(bytes, offset),
                  let rawSize = Self.readUInt32(bytes, offset + 4) else { return nil }
            let messageSize = Int(rawSize)
            offset += 8
            guard bytes.count >= offset + messageSize else { return nil }
            return VolcParsedFrame(
                messageType: messageType,
                flags: flagsRaw,
                sequence: sequence,
                errorCode: code,
                payload: Data(bytes[offset..<offset + messageSize]))
        }

        guard let rawPayloadSize = Self.readUInt32(bytes, offset) else { return nil }
        let payloadSize = Int(rawPayloadSize)
        offset += 4
        guard bytes.count >= offset + payloadSize else { return nil }
        return VolcParsedFrame(
            messageType: messageType,
            flags: flagsRaw,
            sequence: sequence,
            errorCode: nil,
            payload: Data(bytes[offset..<offset + payloadSize]))
    }

    // MARK: - Byte helpers

    private static func hasSequence(_ flags: UInt8) -> Bool {
        flags == VolcFlags.positiveSequence.rawValue || flags == VolcFlags.negativeSequence.rawValue
    }

    private static func bigEndianBytes(_ value: UInt32) -> [UInt8] {
        [UInt8(truncatingIfNeeded: value >> 24),
         UInt8(truncatingIfNeeded: value >> 16),
         UInt8(truncatingIfNeeded: value >> 8),
         UInt8(truncatingIfNeeded: value)]
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32? {
        guard offset >= 0, bytes.count >= offset + 4 else { return nil }
        return (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }
}
