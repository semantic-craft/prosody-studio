import Testing
import Foundation
import os
@testable import ResponsayCore

/// Drives `VolcengineStreamingASRClient`'s session logic through a fake socket
/// (`FakeVolcengineWebSocket`) so the sequencing, end-frame ordering, partial
/// fallback, and 401/403 classification are covered without a real network or a
/// real 火山 account. Real audio + a real key remain a device-only check.
@Suite struct VolcengineStreamingASRClientTests {
    private let creds = VolcengineCredentials(appId: "tok", accessToken: "tok", resourceID: "res")

    @Test func openSessionThrowsWhenCredentialsIncomplete() async {
        let client = VolcengineStreamingASRClient(
            credentials: VolcengineCredentials(appId: "", accessToken: "", resourceID: "r"))
        await #expect(throws: VolcengineASRError.credentialsMissing) {
            try await client.openSession()
        }
    }

    @Test func streamsFramesInOrderAndReturnsFinalTranscript() async throws {
        let fake = FakeVolcengineWebSocket()
        let client = VolcengineStreamingASRClient(
            credentials: creds, hotwords: [], connectionFactory: { _ in fake })

        try await client.openSession()
        await client.consume(pcm: Data(repeating: 1, count: VolcengineASRProtocol.targetAudioChunkBytes))
        try await client.sendLastFrame()

        // Server returns a final frame (lastPacket header) carrying the transcript.
        let finalFrame = VolcengineASRFrame.build(
            messageType: .fullServerResponse, flags: .lastPacket, serialization: .json,
            payload: Data(#"{"result":{"text":"你好世界"}}"#.utf8), sequence: nil)
        fake.deliver(finalFrame)

        let text = try await client.awaitFinalResult(timeout: Duration.seconds(2))
        #expect(text == "你好世界")

        // Exactly: first frame (FullClientRequest seq=1), one audio frame
        // (AudioOnlyRequest positive seq=2), and the negative-sequence end frame.
        let sent = fake.sentFrames
        #expect(sent.count == 3)
        let first = try #require(VolcengineASRFrame.parse(sent[0]))
        #expect(first.messageType == .fullClientRequest)
        #expect(first.sequence == 1)
        // Audio frames are sent uncompressed (issue 287 — openless parity);
        // verify the header bytes directly, including the compression nibble.
        let audioBytes = [UInt8](sent[1])
        #expect(audioBytes.count >= 8)
        #expect(audioBytes[2] & 0x0F == 0b0000)
        #expect((audioBytes[1] >> 4) & 0x0F == VolcMessageType.audioOnlyRequest.rawValue)
        #expect(audioBytes[1] & 0x0F == VolcFlags.positiveSequence.rawValue)
        let end = try #require(VolcengineASRFrame.parse(sent[2]))
        #expect(end.flags == VolcFlags.negativeSequence.rawValue)
        #expect(end.isFinal)
    }

    @Test func fallsBackToLastPartialWhenServerClosesBeforeFinal() async throws {
        let fake = FakeVolcengineWebSocket()
        let client = VolcengineStreamingASRClient(
            credentials: creds, hotwords: [], connectionFactory: { _ in fake })

        try await client.openSession()
        // A non-final partial, then the server closes without ever sending a final frame.
        let partial = VolcengineASRFrame.build(
            messageType: .fullServerResponse, flags: .none, serialization: .json,
            payload: Data(#"{"result":{"text":"半句话"}}"#.utf8), sequence: nil)
        fake.deliver(partial)
        fake.close()

        let text = try await client.awaitFinalResult(timeout: Duration.seconds(2))
        #expect(text == "半句话")   // partial fallback, not an error
    }

    // 290②: a stale (lower-sequence) partial arriving after a newer one must
    // not overwrite it — otherwise a disconnect right then would surface the
    // OLDER text as the fallback "final".
    @Test func staleOutOfOrderPartialDoesNotPolluteFallback() async throws {
        let fake = FakeVolcengineWebSocket()
        let client = VolcengineStreamingASRClient(
            credentials: creds, hotwords: [], connectionFactory: { _ in fake })

        try await client.openSession()
        func partialFrame(_ text: String, seq: Int32) -> Data {
            VolcengineASRFrame.build(
                messageType: .fullServerResponse, flags: .positiveSequence, serialization: .json,
                payload: Data(#"{"result":{"text":"\#(text)"}}"#.utf8), sequence: seq)
        }
        fake.deliver(partialFrame("今天天气很好我们", seq: 5))
        fake.deliver(partialFrame("今天天气", seq: 3))   // late, out of order
        fake.close()                                     // drop before any final frame

        let text = try await client.awaitFinalResult(timeout: Duration.seconds(2))
        #expect(text == "今天天气很好我们")   // newer partial survives as fallback
    }

    @Test func classifiesHandshakeRejectionAsAuthRejected() async throws {
        let fake = FakeVolcengineWebSocket()
        let client = VolcengineStreamingASRClient(
            credentials: creds, hotwords: [], connectionFactory: { _ in fake })

        try await client.openSession()
        fake.close(status: 403)

        await #expect(throws: VolcengineASRError.authRejected(403)) {
            try await client.awaitFinalResult(timeout: Duration.seconds(2))
        }
    }

    // The success path (final frame received) MUST close the socket. A
    // `URLSessionWebSocketTask` only releases its connection on an explicit
    // `cancel()`, and Volcengine SAUC caps concurrent connections per credential —
    // so a leaked happy-path socket makes the NEXT capture's handshake fail
    // ("worked once, then 不上屏" — Volcengine-only, the sole persistent-WS engine).
    @Test func closesSocketAfterFinalResult() async throws {
        let fake = FakeVolcengineWebSocket()
        let client = VolcengineStreamingASRClient(
            credentials: creds, hotwords: [], connectionFactory: { _ in fake })

        try await client.openSession()
        await client.consume(pcm: Data(repeating: 1, count: VolcengineASRProtocol.targetAudioChunkBytes))
        try await client.sendLastFrame()
        let finalFrame = VolcengineASRFrame.build(
            messageType: .fullServerResponse, flags: .lastPacket, serialization: .json,
            payload: Data(#"{"result":{"text":"你好"}}"#.utf8), sequence: nil)
        fake.deliver(finalFrame)

        _ = try await client.awaitFinalResult(timeout: Duration.seconds(2))
        #expect(fake.wasCancelled)
    }

    // The error-frame path must also close the socket (no leak on a server error).
    @Test func closesSocketAfterErrorFrame() async throws {
        let fake = FakeVolcengineWebSocket()
        let client = VolcengineStreamingASRClient(
            credentials: creds, hotwords: [], connectionFactory: { _ in fake })

        try await client.openSession()
        let errorFrame = VolcengineASRFrame.build(
            messageType: .errorMessage, flags: .none, serialization: .json,
            payload: Data(#"{"error":"quota"}"#.utf8), sequence: nil)
        fake.deliver(errorFrame)

        _ = try? await client.awaitFinalResult(timeout: Duration.seconds(2))
        #expect(fake.wasCancelled)
    }

    /// Cancelling the socket must make a pending/next `receive()` fail, never hang
    /// — guards the fake's continuation against a future test that opens a session
    /// without delivering or closing a frame.
    @Test func cancelMakesReceiveFailRatherThanHang() async {
        let fake = FakeVolcengineWebSocket()
        fake.cancel()
        await #expect(throws: VolcengineWebSocketFailure.self) {
            _ = try await fake.receive()
        }
    }
}

/// In-memory `VolcengineWebSocketConnection` double: records every frame the
/// client sends, and lets the test script the server side (deliver frames /
/// close with an optional handshake status). A lock-guarded single-consumer
/// event queue — the client's receive loop is the only consumer.
private final class FakeVolcengineWebSocket: VolcengineWebSocketConnection, @unchecked Sendable {
    private enum Event {
        case frame(Data)
        case failure(Int?)
    }

    private struct State {
        var sent: [Data] = []
        var queued: [Event] = []
        var waiter: CheckedContinuation<Event, Never>?
        var cancelled = false
    }

    // OSAllocatedUnfairLock.withLock is non-suspending, so it is usable from the
    // async send/receive methods (NSLock is not).
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Frames the client has sent, in order.
    var sentFrames: [Data] { state.withLock { $0.sent } }
    /// Whether the client closed (cancelled) the socket — the leak-regression probe.
    var wasCancelled: Bool { state.withLock { $0.cancelled } }

    func send(_ data: Data) async throws {
        state.withLock { $0.sent.append(data) }
    }

    func receive() async throws -> Data {
        switch await nextEvent() {
        case let .frame(data):
            return data
        case let .failure(code):
            throw VolcengineWebSocketFailure(statusCode: code, underlying: nil)
        }
    }

    /// A cancelled connection fails any parked receive and all future ones,
    /// instead of leaving an `await` hung forever (mirrors a real socket).
    func cancel() {
        let pending: CheckedContinuation<Event, Never>? = state.withLock { state in
            state.cancelled = true
            defer { state.waiter = nil }
            return state.waiter
        }
        pending?.resume(returning: .failure(nil))
    }

    // MARK: Test driver API

    func deliver(_ frame: Data) { enqueue(.frame(frame)) }
    func close(status: Int? = nil) { enqueue(.failure(status)) }

    private func nextEvent() async -> Event {
        await withCheckedContinuation { continuation in
            // Resolve outside the lock to avoid resuming while holding it.
            let ready: Event? = state.withLock { state in
                if state.cancelled { return .failure(nil) }
                if state.queued.isEmpty {
                    state.waiter = continuation
                    return nil
                }
                return state.queued.removeFirst()
            }
            if let ready { continuation.resume(returning: ready) }
        }
    }

    private func enqueue(_ event: Event) {
        let pending: CheckedContinuation<Event, Never>? = state.withLock { state in
            if let waiter = state.waiter {
                state.waiter = nil
                return waiter
            }
            state.queued.append(event)
            return nil
        }
        pending?.resume(returning: event)
    }
}
