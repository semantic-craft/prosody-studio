import Foundation
import OSLog

/// Volcengine 火山引擎 SAUC bigmodel **streaming** ASR client (service/10038).
///
/// Swift port of the openless Rust `VolcengineStreamingASR` (itself a port of the
/// original Swift). The battle-tested protocol quirks are preserved:
///   • Stream end is signalled ONLY by the frame header (`lastPacket` /
///     `negativeSequence`), never by `utterance.definite=true`.
///   • A `partial` transcript is cached and used as a fallback if the server
///     closes before sending a final frame — "at least don't drop what was said".
///   • The end frame (negative sequence) must follow all audio frames; here the
///     `actor` serializes calls, so awaiting `consume(pcm:)` before
///     `sendLastFrame()` is enough — no separate send-worker / drain barrier.
public actor VolcengineStreamingASRClient {
    private let credentials: VolcengineCredentials
    private let hotwords: [VolcengineHotword]
    private let boostingTableID: String?
    private let connectionFactory: @Sendable (URLRequest) -> any VolcengineWebSocketConnection
    private let log = Logger(subsystem: "responsay", category: "volc-asr")

    private var connection: (any VolcengineWebSocketConnection)?
    private var receiveTask: Task<Void, Never>?
    private var nextSequence: Int32 = 1
    private var pendingAudio = Data()
    private var bytesSent = 0
    private var isConnected = false

    /// Most recent non-final transcript; the close/error fallback.
    private var lastPartialText = ""
    /// Highest server frame sequence seen this session (290②): frames can land
    /// out of order after network jitter, and a stale partial overwriting
    /// `lastPartialText` would become the disconnect-fallback "final".
    private var highestServerSequence: Int32 = 0

    // Final-result delivery: resolved once, by the receive loop, a fallback, or cancel.
    private var finalResult: Result<String, Error>?
    private var finalWaiters: [CheckedContinuation<String, Error>] = []

    /// Live (non-final) transcript previews while recording.
    public nonisolated let partials: AsyncStream<String>
    private let partialContinuation: AsyncStream<String>.Continuation

    public init(
        credentials: VolcengineCredentials,
        hotwords: [VolcengineHotword] = [],
        boostingTableID: String? = nil
    ) {
        self.credentials = credentials
        self.hotwords = hotwords
        self.boostingTableID = boostingTableID
        self.connectionFactory = { URLSessionVolcengineWebSocket(request: $0) }
        (partials, partialContinuation) = AsyncStream.makeStream(of: String.self)
    }

    /// Test seam: inject a fake `VolcengineWebSocketConnection` so the session
    /// logic runs without a real socket. Internal — reached from tests via
    /// `@testable import ResponsayCore`.
    init(
        credentials: VolcengineCredentials,
        hotwords: [VolcengineHotword],
        connectionFactory: @escaping @Sendable (URLRequest) -> any VolcengineWebSocketConnection
    ) {
        self.credentials = credentials
        self.hotwords = hotwords
        self.boostingTableID = nil
        self.connectionFactory = connectionFactory
        (partials, partialContinuation) = AsyncStream.makeStream(of: String.self)
    }

    // MARK: - Public lifecycle

    /// Connect, reset session state, and send the first (full client request) frame.
    public func openSession(vadConfig: VolcengineVADConfig? = nil) async throws {
        guard credentials.isComplete else { throw VolcengineASRError.credentialsMissing }
        guard let url = URL(string: VolcengineASRProtocol.endpoint) else {
            throw VolcengineASRError.connectionFailed("invalid endpoint")
        }
        let connectID = UUID().uuidString
        var request = URLRequest(url: url)
        // X-Api-* four-header auth, matching openless volcengine.rs and the
        // official doc. `Authorization: Bearer; <token>` was a port-time
        // invention the server rejects outright with HTTP 400 "no token or
        // access_key was found" — live-verified 2026-06-11 (issue 316).
        request.setValue(credentials.accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(credentials.appId, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(credentials.resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(connectID, forHTTPHeaderField: "X-Api-Connect-Id")

        let connection = connectionFactory(request)
        self.connection = connection
        nextSequence = 1
        pendingAudio.removeAll(keepingCapacity: true)
        bytesSent = 0
        lastPartialText = ""
        highestServerSequence = 0
        finalResult = nil
        isConnected = true

        // First frame: full client request (JSON), positive sequence = 1.
        let payload = VolcengineASRProtocol.firstFramePayload(
            connectID: connectID, hotwords: hotwords,
            boostingTableID: boostingTableID, vadConfig: vadConfig)
        try await sendBinary(VolcengineASRFrame.build(
            messageType: .fullClientRequest,
            flags: .positiveSequence,
            serialization: .json,
            payload: payload,
            sequence: allocatePositiveSequence()))

        receiveTask = Task { [weak self] in await self?.runReceiveLoop() }
    }

    /// Feed 16 kHz / 16-bit / mono PCM. Buffers and flushes whole 200 ms
    /// (`targetAudioChunkBytes`) audio frames in monotonic positive-sequence order.
    public func consume(pcm: Data) async {
        guard isConnected else { return }
        pendingAudio.append(pcm)
        while pendingAudio.count >= VolcengineASRProtocol.targetAudioChunkBytes {
            let chunk = Data(pendingAudio.prefix(VolcengineASRProtocol.targetAudioChunkBytes))
            pendingAudio.removeFirst(VolcengineASRProtocol.targetAudioChunkBytes)
            bytesSent += chunk.count
            // No compression, mirroring openless's deliberate choice: the server
            // echoes the client's compression mode (volcengine_asr.md「服务端将使用
            // 客户端的压缩方法」), and parse() only accepts uncompressed frames —
            // declaring gzip would make every server response undecodable. PCM is
            // high-entropy anyway, so the saving was negligible (issue 287).
            let frame = VolcengineASRFrame.build(
                messageType: .audioOnlyRequest,
                flags: .positiveSequence,
                serialization: .none,
                payload: chunk,
                sequence: allocatePositiveSequence())
            do {
                try await sendBinary(frame)
            } catch {
                log.error("audio frame send failed: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
    }

    /// Flush any leftover audio, then send the negative-sequence end frame telling
    /// the server "the stream ends here". Because the actor serializes, every
    /// `consume(pcm:)` issued before this call has already been sent.
    public func sendLastFrame() async throws {
        guard isConnected else { return }
        if !pendingAudio.isEmpty {
            let leftover = pendingAudio
            pendingAudio.removeAll(keepingCapacity: false)
            bytesSent += leftover.count
            try await sendBinary(VolcengineASRFrame.build(
                messageType: .audioOnlyRequest,
                flags: .positiveSequence,
                serialization: .none,
                payload: leftover,
                sequence: allocatePositiveSequence()))
        }
        let finalSeq = -nextSequence
        nextSequence += 1
        try await sendBinary(VolcengineASRFrame.build(
            messageType: .audioOnlyRequest,
            flags: .negativeSequence,
            serialization: .none,
            payload: Data(),
            sequence: finalSeq))
        log.info("sent end frame; \(self.bytesSent, privacy: .public) audio bytes total")
    }

    /// Await the final transcript (or the partial fallback). Times out — defaulting
    /// to 12 s, matching the Rust `FINAL_RESULT_TIMEOUT` — and tears the socket down.
    public func awaitFinalResult(timeout: Duration = .seconds(12)) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await self.waitForFinal() }
            group.addTask {
                try await Task.sleep(for: timeout)
                await self.resolveTimeout()
                throw VolcengineASRError.finalResultTimeout
            }
            defer { group.cancelAll() }
            return try await group.next() ?? ""
        }
    }

    /// Close the socket and resolve any pending wait (no-op if already resolved).
    public func cancel() {
        isConnected = false
        resolveFinal(.failure(VolcengineASRError.noFinalResult))
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

    /// Returns `false` once the session has terminated (caller stops reading).
    private func handle(frame data: Data) -> Bool {
        guard let parsed = VolcengineASRFrame.parse(data) else {
            log.error("frame parse failed (\(data.count, privacy: .public) bytes)")
            return true
        }

        if parsed.messageType == .errorMessage {
            let body = String(data: parsed.payload, encoding: .utf8) ?? ""
            let code = Int(parsed.errorCode ?? 0)
            log.error("error frame code=\(code, privacy: .public)")
            resolveFinal(.failure(VolcengineASRError.asrError(code: code, message: body)))
            return false
        }

        guard parsed.messageType == .fullServerResponse else { return true }
        guard let text = VolcengineASRProtocol.transcriptText(fromServerJSON: parsed.payload) else {
            return true
        }

        // Stream end only trusts the frame header (lastPacket / negativeSequence),
        // NEVER utterance.definite — see VolcParsedFrame.isFinal.
        if parsed.isFinal {
            resolveFinal(.success(text))
            return false
        }
        if !text.isEmpty {
            // 290②: drop out-of-order partials — the server sequence must be
            // monotone. `magnitude` because the final frame uses a negative
            // sequence; partial frames are positive.
            if let seq = parsed.sequence {
                let magnitude = seq == Int32.min ? Int32.max : abs(seq)
                guard magnitude >= highestServerSequence else {
                    log.debug("stale partial dropped (seq \(magnitude, privacy: .public) < \(self.highestServerSequence, privacy: .public))")
                    return true
                }
                highestServerSequence = magnitude
            }
            lastPartialText = text
            partialContinuation.yield(text)
        }
        return true
    }

    private func handleReceiveFailure(_ error: Error) {
        // Distinguish a rejected handshake (401/403) from a network/TLS drop.
        if let status = (error as? VolcengineWebSocketFailure)?.statusCode,
           status == 401 || status == 403 {
            resolveFinal(.failure(VolcengineASRError.authRejected(status)))
        } else {
            fallbackToPartialOrError(.connectionFailed(error.localizedDescription))
        }
        teardownSocket()
    }

    /// Server closed / network dropped before a final frame: hand back the last
    /// partial if we have one, otherwise surface the error.
    private func fallbackToPartialOrError(_ error: VolcengineASRError) {
        if !lastPartialText.isEmpty {
            log.warning("no final frame; using partial fallback (\(self.lastPartialText.count, privacy: .public) chars)")
            resolveFinal(.success(lastPartialText))
        } else {
            resolveFinal(.failure(error))
        }
    }

    // MARK: - Final-result plumbing

    private func waitForFinal() async throws -> String {
        if let finalResult { return try finalResult.get() }
        return try await withCheckedThrowingContinuation { continuation in
            finalWaiters.append(continuation)
        }
    }

    private func resolveTimeout() {
        log.error("final result timed out")
        resolveFinal(.failure(VolcengineASRError.finalResultTimeout))
        teardownSocket()
    }

    private func resolveFinal(_ result: Result<String, Error>) {
        guard finalResult == nil else { return }
        finalResult = result
        isConnected = false
        partialContinuation.finish()
        let waiters = finalWaiters
        finalWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(with: result)
        }
        // Close the socket on EVERY resolution, including the success path (final
        // frame received). A `URLSessionWebSocketTask` is retained by its URLSession
        // until explicitly cancelled — unlike openless's Rust socket, which closes on
        // RAII drop — so without this the happy-path connection leaks open. Volcengine
        // SAUC caps concurrent connections per credential, so a leaked socket makes the
        // NEXT capture's handshake fail: dictation worked once, then "不上屏" on every
        // retry (Volcengine-only, since it is the sole persistent-WebSocket engine).
        // The explicit `teardownSocket()` calls on the error/timeout/cancel paths are
        // now redundant no-ops (connection already nil), kept for clarity.
        teardownSocket()
    }

    // MARK: - Helpers

    private func allocatePositiveSequence() -> Int32 {
        let value = nextSequence
        nextSequence += 1
        return value
    }

    private func sendBinary(_ data: Data) async throws {
        guard let connection else { throw VolcengineASRError.connectionFailed("websocket not open") }
        do {
            try await connection.send(data)
        } catch {
            if let status = (error as? VolcengineWebSocketFailure)?.statusCode, status == 401 || status == 403 {
                throw VolcengineASRError.authRejected(status)
            }
            throw VolcengineASRError.connectionFailed(error.localizedDescription)
        }
    }

    private func teardownSocket() {
        receiveTask?.cancel()
        receiveTask = nil
        connection?.cancel()
        connection = nil
    }
}
