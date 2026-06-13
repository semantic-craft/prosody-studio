import Foundation
import os
import Testing
@testable import ResponsayCore

@Suite struct DoubaoBiTTSClientTests {
    @Test func credentialsUseAppIdAndAccessKeyHeaders() async throws {
        let fake = FakeDoubaoWebSocket()
        let requestBox = RequestBox()
        let client = DoubaoBiTTSClient(
            credentials: DoubaoTTSCredentials(appId: "app-id", accessToken: "access-token", resourceID: "seed-tts-2.0"),
            connectionFactory: { request in
                requestBox.set(request)
                return fake
            })

        try await openSession(client, fake: fake, speed: 1.25)
        await client.cancel()

        let request = try #require(requestBox.value)
        #expect(request.url?.absoluteString == DoubaoTTSCredentials.bidirectionalEndpoint)
        #expect(request.value(forHTTPHeaderField: "X-Api-App-Id") == "app-id")
        #expect(request.value(forHTTPHeaderField: "X-Api-Access-Key") == "access-token")
        #expect(request.value(forHTTPHeaderField: "X-Api-Resource-Id") == "seed-tts-2.0")
        #expect(request.value(forHTTPHeaderField: "X-Api-Connect-Id")?.isEmpty == false)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "X-Api-Key") == nil)

        let frames = fake.sentFrames
        #expect(clientEvent(frames[0]) == DoubaoBiTTSEvent.startConnection.rawValue)
        #expect(clientEvent(frames[1]) == DoubaoBiTTSEvent.startSession.rawValue)
        let payload = try startSessionPayload(frames[1])
        let req = try #require(payload["req_params"] as? [String: Any])
        #expect(req["speaker"] as? String == doubaoTestVoice)
        let audio = try #require(req["audio_params"] as? [String: Any])
        #expect(audio["format"] as? String == "pcm")
        #expect(audio["sample_rate"] as? Int == 24_000)
        #expect(audio["speech_rate"] as? Int == 25)
    }

    @Test func modelResourceRidesInHeader() async throws {
        let fake = FakeDoubaoWebSocket()
        let requestBox = RequestBox()
        let client = DoubaoBiTTSClient(
            credentials: DoubaoTTSCredentials(appId: "app-id", accessToken: "access-token", resourceID: "seed-tts-1.0"),
            connectionFactory: { request in
                requestBox.set(request)
                return fake
            })

        try await openSession(client, fake: fake)
        await client.cancel()

        let request = try #require(requestBox.value)
        #expect(request.value(forHTTPHeaderField: "X-Api-App-Id") == "app-id")
        #expect(request.value(forHTTPHeaderField: "X-Api-Access-Key") == "access-token")
        #expect(request.value(forHTTPHeaderField: "X-Api-Resource-Id") == "seed-tts-1.0")
        #expect(request.value(forHTTPHeaderField: "X-Api-Key") == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func credentialsCompletenessRequiresAppIdAndAccessKey() {
        #expect(DoubaoTTSCredentials(appId: "app", accessToken: "token").isComplete)
        #expect(!DoubaoTTSCredentials(appId: " ", accessToken: "token").isComplete)
        #expect(!DoubaoTTSCredentials(appId: "app", accessToken: " ").isComplete)
    }
}

private func openSession(
    _ client: DoubaoBiTTSClient,
    fake: FakeDoubaoWebSocket,
    speed: Double = 1
) async throws {
    async let opening: Void = client.openSession(voice: doubaoTestVoice, speed: speed)
    try await waitUntil { fake.sentFrames.count >= 1 }
    fake.deliver(DoubaoBiTTSFrame.build(
        messageType: .fullServerResponse,
        flags: .withEvent,
        serialization: .json,
        event: .connectionStarted,
        sessionId: "conn-id",
        payload: Data()))
    try await opening
}

private func waitUntil(_ predicate: @escaping @Sendable () -> Bool) async throws {
    for _ in 0..<100 {
        if predicate() { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw TestTimeout()
}

private struct TestTimeout: Error {}

private let doubaoTestVoice = "en_female_dacey_uranus_bigtts"

private func clientEvent(_ frame: Data) -> Int32? {
    readInt32([UInt8](frame), offset: 4)
}

private func startSessionPayload(_ frame: Data) throws -> [String: Any] {
    let bytes = [UInt8](frame)
    var offset = 4
    _ = try #require(readInt32(bytes, offset: offset))
    offset += 4
    let sessionIdLength = Int(try #require(readInt32(bytes, offset: offset)))
    offset += 4 + sessionIdLength
    let payloadSize = Int(try #require(readInt32(bytes, offset: offset)))
    offset += 4
    let payload = Data(bytes[offset..<offset + payloadSize])
    return try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
}

private func readInt32(_ bytes: [UInt8], offset: Int) -> Int32? {
    guard offset >= 0, bytes.count >= offset + 4 else { return nil }
    let value = (UInt32(bytes[offset]) << 24)
        | (UInt32(bytes[offset + 1]) << 16)
        | (UInt32(bytes[offset + 2]) << 8)
        | UInt32(bytes[offset + 3])
    return Int32(bitPattern: value)
}

private final class RequestBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<URLRequest?>(initialState: nil)
    var value: URLRequest? { lock.withLock { $0 } }
    func set(_ request: URLRequest) { lock.withLock { $0 = request } }
}

private final class FakeDoubaoWebSocket: VolcengineWebSocketConnection, @unchecked Sendable {
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

    private let state = OSAllocatedUnfairLock(initialState: State())
    var sentFrames: [Data] { state.withLock { $0.sent } }

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

    func cancel() {
        let pending: CheckedContinuation<Event, Never>? = state.withLock { state in
            state.cancelled = true
            defer { state.waiter = nil }
            return state.waiter
        }
        pending?.resume(returning: .failure(nil))
    }

    func deliver(_ frame: Data) { enqueue(.frame(frame)) }

    private func nextEvent() async -> Event {
        await withCheckedContinuation { continuation in
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
