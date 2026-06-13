import Foundation
import OSLog

public enum DoubaoBiTTSError: Error, Equatable, LocalizedError {
    case credentialsMissing
    case connectionFailed(String)
    case authRejected(Int)
    case ttsError(code: Int, message: String)
    case sessionTimeout
    case streamClosed
    
    public var errorDescription: String? {
        switch self {
        case .credentialsMissing:
            return "请先在设置中填写豆包语音的 API Key。"
        case let .connectionFailed(detail):
            return "豆包语音连接失败：\(detail)"
        case let .authRejected(status):
            return "豆包语音凭据被拒（HTTP \(status)）。"
        case let .ttsError(code, message):
            return "豆包语音错误 \(code): \(message)"
        case .sessionTimeout:
            return "豆包语音等待结果超时。"
        case .streamClosed:
            return "音频流已关闭"
        }
    }
}

/// 豆包双向流式 TTS 客户端 (V3 API: wss://openspeech.bytedance.com/api/v3/tts/bidirection)
/// 
/// 遵循 OpenLess 的无锁并发设计：
/// - Actor 隔离发送状态
/// - 独立的 `Task` 运行 `receiveLoop`
/// - 生命周期完全依赖 Swift Concurrency 的 Continuation 闭包，断开连接时安全排空。
public actor DoubaoBiTTSClient {
    private let credentials: DoubaoTTSCredentials
    private let connectionFactory: @Sendable (URLRequest) -> any VolcengineWebSocketConnection
    private let log = Logger(subsystem: "responsay", category: "doubao-bitts")
    
    private var connection: (any VolcengineWebSocketConnection)?
    private var receiveTask: Task<Void, Never>?
    private var isConnected = false
    private var currentSessionId: String?
    private var connectionStartedContinuation: CheckedContinuation<Void, Error>?
    private var didReceiveConnectionStarted = false
    
    /// 流式抛出返回的 PCM 音频包
    private var audioContinuation: AsyncThrowingStream<Data, Error>.Continuation?
    public nonisolated let audioStream: AsyncThrowingStream<Data, Error>
    
    public static let endpoint = DoubaoTTSCredentials.bidirectionalEndpoint
    
    public init(credentials: DoubaoTTSCredentials) {
        self.credentials = credentials
        self.connectionFactory = { URLSessionVolcengineWebSocket(request: $0) }
        
        var cont: AsyncThrowingStream<Data, Error>.Continuation!
        self.audioStream = AsyncThrowingStream { cont = $0 }
        self.audioContinuation = cont
    }
    
    init(
        credentials: DoubaoTTSCredentials,
        connectionFactory: @escaping @Sendable (URLRequest) -> any VolcengineWebSocketConnection
    ) {
        self.credentials = credentials
        self.connectionFactory = connectionFactory
        
        var cont: AsyncThrowingStream<Data, Error>.Continuation!
        self.audioStream = AsyncThrowingStream { cont = $0 }
        self.audioContinuation = cont
    }
    
    public func openSession(voice: String, speed: Double = 1.0) async throws {
        guard credentials.isComplete else { throw DoubaoBiTTSError.credentialsMissing }
        guard let url = URL(string: credentials.trimmedEndpoint) else {
            throw DoubaoBiTTSError.connectionFailed("invalid endpoint")
        }
        
        let connectID = UUID().uuidString
        var request = URLRequest(url: url)
        for (field, value) in credentials.authHeaders(connectID: connectID) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        
        let connection = connectionFactory(request)
        self.connection = connection
        self.isConnected = true
        self.currentSessionId = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        self.didReceiveConnectionStarted = false
        
        receiveTask = Task { [weak self] in await self?.runReceiveLoop() }
        
        let startConnection = DoubaoBiTTSFrame.build(
            messageType: .fullClientRequest,
            flags: .withEvent,
            serialization: .json,
            event: .startConnection,
            sessionId: nil,
            payload: Data()
        )
        try await sendBinary(startConnection)
        try await waitForConnectionStarted()

        let payload = buildStartSessionPayload(voice: voice, speed: speed)
        let frame = DoubaoBiTTSFrame.build(
            messageType: .fullClientRequest,
            flags: .withEvent,
            serialization: .json,
            event: .startSession,
            sessionId: currentSessionId,
            payload: payload
        )
        try await sendBinary(frame)
    }
    
    public func sendText(_ text: String, voice: String) async throws {
        guard isConnected, let sessionId = currentSessionId else { return }
        let payload = buildTaskRequestPayload(text: text, voice: voice)
        let frame = DoubaoBiTTSFrame.build(
            messageType: .fullClientRequest,
            flags: .withEvent,
            serialization: .json,
            event: .taskRequest,
            sessionId: sessionId,
            payload: payload
        )
        try await sendBinary(frame)
    }
    
    public func finishSession() async throws {
        guard isConnected, let sessionId = currentSessionId else { return }
        let frame = DoubaoBiTTSFrame.build(
            messageType: .fullClientRequest,
            flags: .withEvent,
            serialization: .json,
            event: .finishSession,
            sessionId: sessionId,
            payload: Data() // xiaozhi uses "{}" occasionally but Data() is fine for finishSession
        )
        try await sendBinary(frame)
    }
    
    public func cancel() {
        isConnected = false
        audioContinuation?.finish(throwing: DoubaoBiTTSError.streamClosed)
        teardownSocket()
    }
    
    // MARK: - Receive loop
    
    private func runReceiveLoop() async {
        guard let connection else { return }
        while isConnected {
            do {
                let data = try await connection.receive()
                if !handle(frame: data) { return }
            } catch {
                if isConnected { handleReceiveFailure(error) }
                return
            }
        }
    }
    
    private func handle(frame data: Data) -> Bool {
        guard let parsed = DoubaoBiTTSFrame.parse(data) else {
            log.error("frame parse failed (\(data.count, privacy: .public) bytes)")
            return true
        }
        
        if parsed.messageType == .errorMessage {
            let body = String(data: parsed.payload, encoding: .utf8) ?? ""
            let code = Int(parsed.errorCode ?? 0)
            log.error("error frame code=\(code, privacy: .public)")
            audioContinuation?.finish(throwing: DoubaoBiTTSError.ttsError(code: code, message: body))
            teardownSocket()
            return false
        }
        
        if parsed.messageType == .audioOnlyResponse {
            if parsed.payload.count > 0 {
                audioContinuation?.yield(parsed.payload)
            }
        }
        
        // Handle Control Events
        switch parsed.event {
        case .connectionStarted:
            didReceiveConnectionStarted = true
            connectionStartedContinuation?.resume(returning: ())
            connectionStartedContinuation = nil
        case .connectionFailed:
            let message = parsed.responseMetaJson ?? "connection failed"
            connectionStartedContinuation?.resume(throwing: DoubaoBiTTSError.connectionFailed(message))
            connectionStartedContinuation = nil
            audioContinuation?.finish(throwing: DoubaoBiTTSError.connectionFailed(message))
            isConnected = false
            teardownSocket()
            return false
        case .sessionFinished, .sessionFailed, .sessionCanceled:
            log.debug("Session ended with event \(parsed.event.rawValue)")
            audioContinuation?.finish()
            isConnected = false
            teardownSocket()
            return false
        case .connectionFinished:
            log.debug("Connection finished")
            audioContinuation?.finish()
            isConnected = false
            teardownSocket()
            return false
        default:
            break
        }
        
        return true
    }
    
    private func handleReceiveFailure(_ error: Error) {
        if let continuation = connectionStartedContinuation {
            connectionStartedContinuation = nil
            continuation.resume(throwing: error)
        }
        if let status = (error as? VolcengineWebSocketFailure)?.statusCode, status == 401 || status == 403 {
            audioContinuation?.finish(throwing: DoubaoBiTTSError.authRejected(status))
        } else {
            audioContinuation?.finish(throwing: DoubaoBiTTSError.connectionFailed(error.localizedDescription))
        }
        teardownSocket()
    }
    
    private func teardownSocket() {
        if let continuation = connectionStartedContinuation {
            connectionStartedContinuation = nil
            continuation.resume(throwing: DoubaoBiTTSError.streamClosed)
        }
        receiveTask?.cancel()
        receiveTask = nil
        connection?.cancel()
        connection = nil
    }
    
    private func sendBinary(_ data: Data) async throws {
        guard let connection else { throw DoubaoBiTTSError.connectionFailed("websocket not open") }
        do {
            try await connection.send(data)
        } catch {
            if let status = (error as? VolcengineWebSocketFailure)?.statusCode, status == 401 || status == 403 {
                throw DoubaoBiTTSError.authRejected(status)
            }
            throw DoubaoBiTTSError.connectionFailed(error.localizedDescription)
        }
    }

    private func waitForConnectionStarted() async throws {
        if didReceiveConnectionStarted { return }
        try await withCheckedThrowingContinuation { continuation in
            connectionStartedContinuation = continuation
        }
    }
    
    // MARK: - Payloads
    
    private func buildStartSessionPayload(voice: String, speed: Double) -> Data {
        let payload: [String: Any] = [
            "user": ["uid": "responsay-client"],
            "event": DoubaoBiTTSEvent.startSession.rawValue,
            "namespace": "BidirectionalTTS",
            "req_params": [
                "speaker": voice,
                "audio_params": [
                    "format": "pcm",
                    "sample_rate": 24_000,
                    "speech_rate": Self.speechRate(fromSpeed: speed)
                ]
            ]
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }
    
    private func buildTaskRequestPayload(text: String, voice: String) -> Data {
        let payload: [String: Any] = [
            "user": ["uid": "responsay-client"],
            "event": DoubaoBiTTSEvent.taskRequest.rawValue,
            "namespace": "BidirectionalTTS",
            "req_params": [
                "text": text,
                "speaker": voice
            ]
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    private static func speechRate(fromSpeed speed: Double) -> Int {
        let clamped = min(2.0, max(0.5, speed))
        return Int(((clamped - 1.0) * 100.0).rounded())
    }
}
