import Foundation

/// 火山引擎 (Volcengine) 豆包大模型双向流式 (Bi-TTS) 二进制帧编解码。
///
/// 帧结构：4 字节 header + 变长 optional (event/sessionId 等) + 4 字节 payload size + payload。
/// 本协议完全对齐 Volcengine V3 双流式规范，且保持零依赖、免 CocoaPods 的纯 Swift 实现。
/// 防负向优化：复用了 ASRFrame 类似的位运算，但针对 `withEvent` 做特化。

public enum DoubaoBiTTSMessageType: UInt8 {
    case fullClientRequest = 0b0001
    case audioOnlyRequest = 0b0010
    case fullServerResponse = 0b1001
    case audioOnlyResponse = 0b1011
    case errorMessage = 0b1111

    public static func from(raw: UInt8) -> DoubaoBiTTSMessageType? {
        DoubaoBiTTSMessageType(rawValue: raw)
    }
}

public enum DoubaoBiTTSFlags: UInt8 {
    case none = 0b0000
    case positiveSequence = 0b0001
    case lastPacket = 0b0010
    case negativeSequence = 0b0011
    case withEvent = 0b0100
}

public enum DoubaoBiTTSSerialization: UInt8 {
    case none = 0b0000
    case json = 0b0001
}

public enum DoubaoBiTTSEvent: Int32 {
    case none = 0
    case startConnection = 1
    case finishConnection = 2
    case connectionStarted = 50
    case connectionFailed = 51
    case connectionFinished = 52
    
    // Session (Client -> Server)
    case startSession = 100
    case cancelSession = 101
    case finishSession = 102
    
    // Session (Server -> Client)
    case sessionStarted = 150
    case sessionCanceled = 151
    case sessionFinished = 152
    case sessionFailed = 153
    
    // Generics
    case taskRequest = 200
    
    // TTS Downstream
    case ttsSentenceStart = 350
    case ttsSentenceEnd = 351
    case ttsResponse = 352
    
    public static func from(raw: Int32) -> DoubaoBiTTSEvent {
        DoubaoBiTTSEvent(rawValue: raw) ?? .none
    }
}

public struct DoubaoBiTTSParsedFrame: Equatable {
    public var messageType: DoubaoBiTTSMessageType?
    public var flags: UInt8
    public var event: DoubaoBiTTSEvent
    public var sessionId: String?
    public var connectionId: String?
    public var responseMetaJson: String?
    public var errorCode: Int32?
    public var payload: Data
}

public enum DoubaoBiTTSFrame {
    private static let headerByte0: UInt8 = 0x11 // header_size = 1 * 4 = 4 bytes, version = 1
    private static let compressionNone: UInt8 = 0b0000

    /// 构建上行请求帧
    public static func build(
        messageType: DoubaoBiTTSMessageType,
        flags: DoubaoBiTTSFlags,
        serialization: DoubaoBiTTSSerialization,
        event: DoubaoBiTTSEvent,
        sessionId: String?,
        payload: Data
    ) -> Data {
        var frame = Data(capacity: 4 + 4 + 36 + payload.count) // Estimate
        
        // 1. Header (4 bytes)
        frame.append(headerByte0)
        frame.append((messageType.rawValue << 4) | flags.rawValue)
        frame.append((serialization.rawValue << 4) | compressionNone)
        frame.append(0x00)
        
        // 2. Optional
        if flags == .withEvent {
            if event != .none {
                frame.append(contentsOf: bigEndianBytes(UInt32(bitPattern: event.rawValue)))
            }
            if let sessionId {
                let sessionBytes = [UInt8](sessionId.utf8)
                frame.append(contentsOf: bigEndianBytes(UInt32(sessionBytes.count)))
                frame.append(contentsOf: sessionBytes)
            }
        }
        
        // 3. Payload
        frame.append(contentsOf: bigEndianBytes(UInt32(payload.count)))
        frame.append(payload)
        
        return frame
    }

    /// 解析下行响应帧
    public static func parse(_ data: Data) -> DoubaoBiTTSParsedFrame? {
        let bytes = [UInt8](data)
        guard bytes.count >= 8 else { return nil }

        let headerSize = Int(bytes[0] & 0x0F) * 4
        guard headerSize >= 4, bytes.count >= headerSize + 4 else { return nil }

        let messageType = DoubaoBiTTSMessageType.from(raw: (bytes[1] >> 4) & 0x0F)
        let flagsRaw = bytes[1] & 0x0F
        let compression = bytes[2] & 0x0F
        guard compression == compressionNone else { return nil } // We only handle no compression

        var offset = headerSize
        var event = DoubaoBiTTSEvent.none
        var sessionId: String?
        var connectionId: String?
        var responseMetaJson: String?
        var payload = Data()
        var errorCode: Int32?

        if messageType == .fullServerResponse || messageType == .audioOnlyResponse {
            if flagsRaw == DoubaoBiTTSFlags.withEvent.rawValue {
                guard let eventVal = readInt32(bytes, offset) else { return nil }
                event = DoubaoBiTTSEvent.from(raw: eventVal)
                offset += 4
                
                if event == .none {
                    return DoubaoBiTTSParsedFrame(messageType: messageType, flags: flagsRaw, event: event, payload: Data())
                } else if event == .connectionStarted {
                    guard let (str, newOffset) = readString(bytes, offset) else { return nil }
                    connectionId = str
                    offset = newOffset
                } else if event == .connectionFailed {
                    guard let (str, newOffset) = readString(bytes, offset) else { return nil }
                    responseMetaJson = str
                    offset = newOffset
                } else if event == .sessionStarted || event == .sessionFailed || event == .sessionFinished {
                    guard let (sId, offsetAfterSid) = readString(bytes, offset) else { return nil }
                    sessionId = sId
                    offset = offsetAfterSid
                    guard let (meta, offsetAfterMeta) = readString(bytes, offset) else { return nil }
                    responseMetaJson = meta
                    offset = offsetAfterMeta
                } else {
                    guard let (sId, offsetAfterSid) = readString(bytes, offset) else { return nil }
                    sessionId = sId
                    offset = offsetAfterSid
                    
                    guard let (readPayload, offsetAfterPayload) = readPayloadData(bytes, offset) else { return nil }
                    payload = readPayload
                    offset = offsetAfterPayload
                }
            }
        } else if messageType == .errorMessage {
            guard let code = readInt32(bytes, offset) else { return nil }
            errorCode = code
            offset += 4
            guard let (readPayload, offsetAfterPayload) = readPayloadData(bytes, offset) else { return nil }
            payload = readPayload
            offset = offsetAfterPayload
        }

        return DoubaoBiTTSParsedFrame(
            messageType: messageType,
            flags: flagsRaw,
            event: event,
            sessionId: sessionId,
            connectionId: connectionId,
            responseMetaJson: responseMetaJson,
            errorCode: errorCode,
            payload: payload
        )
    }

    // MARK: - Byte helpers

    private static func bigEndianBytes(_ value: UInt32) -> [UInt8] {
        [UInt8(truncatingIfNeeded: value >> 24),
         UInt8(truncatingIfNeeded: value >> 16),
         UInt8(truncatingIfNeeded: value >> 8),
         UInt8(truncatingIfNeeded: value)]
    }

    private static func readInt32(_ bytes: [UInt8], _ offset: Int) -> Int32? {
        guard offset >= 0, bytes.count >= offset + 4 else { return nil }
        let u = (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
        return Int32(bitPattern: u)
    }
    
    private static func readString(_ bytes: [UInt8], _ offset: Int) -> (String, Int)? {
        guard let size = readInt32(bytes, offset) else { return nil }
        let len = Int(size)
        let newOffset = offset + 4
        guard bytes.count >= newOffset + len else { return nil }
        
        let data = Data(bytes[newOffset..<newOffset+len])
        let str = String(data: data, encoding: .utf8) ?? ""
        return (str, newOffset + len)
    }
    
    private static func readPayloadData(_ bytes: [UInt8], _ offset: Int) -> (Data, Int)? {
        guard let size = readInt32(bytes, offset) else { return nil }
        let len = Int(size)
        let newOffset = offset + 4
        guard bytes.count >= newOffset + len else { return nil }
        
        return (Data(bytes[newOffset..<newOffset+len]), newOffset + len)
    }
}
