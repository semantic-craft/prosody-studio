import Foundation

/// Transport seam over the Volcengine streaming socket. Extracted so
/// `VolcengineStreamingASRClient`'s session logic (sequencing, end-frame
/// ordering, partial fallback, 401/403 classification) can be unit-tested with a
/// fake socket — the real one needs a live network and a real 火山 account.
///
/// `receive()` yields only binary frames; text / ping / pong are skipped inside
/// the implementation so the client only ever sees protocol frames.
protocol VolcengineWebSocketConnection: Sendable {
    func send(_ data: Data) async throws
    /// Awaits the next binary frame. Throws `VolcengineWebSocketFailure` on close
    /// or transport error (carrying the handshake HTTP status when available).
    func receive() async throws -> Data
    func cancel()
}

/// Transport-level failure. `statusCode` carries the WebSocket handshake HTTP
/// status when the upgrade was rejected (401 / 403 ⇒ credentials), else `nil`
/// (network / TLS / mid-stream drop).
struct VolcengineWebSocketFailure: Error, LocalizedError {
    let statusCode: Int?
    let underlying: Error?

    var errorDescription: String? {
        if let underlying {
            return underlying.localizedDescription
        }
        if let statusCode {
            return "HTTP \(statusCode)"
        }
        return "Unknown WebSocket failure"
    }
}

/// Production connection backed by `URLSessionWebSocketTask`.
final class URLSessionVolcengineWebSocket: VolcengineWebSocketConnection, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(request: URLRequest, session: URLSession = .shared) {
        task = session.webSocketTask(with: request)
        task.resume()
    }

    deinit {
        // Mirror openless's RAII close: in Rust the split sink closes the socket when
        // the ASR struct drops, but a `URLSessionWebSocketTask` is retained by its
        // URLSession until explicitly cancelled — so an abandoned session (this wrapper
        // freed before an explicit `cancel()`) would otherwise leak the connection open
        // and burn a Volcengine per-credential connection slot. Redundant after the
        // normal-path `cancel()`; kept as the safety net.
        task.cancel(with: .abnormalClosure, reason: nil)
    }

    func send(_ data: Data) async throws {
        do {
            try await task.send(.data(data))
        } catch {
            let status = (task.response as? HTTPURLResponse)?.statusCode
            throw VolcengineWebSocketFailure(statusCode: status, underlying: error)
        }
    }

    func receive() async throws -> Data {
        while true {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await task.receive()
            } catch {
                let status = (task.response as? HTTPURLResponse)?.statusCode
                throw VolcengineWebSocketFailure(statusCode: status, underlying: error)
            }
            switch message {
            case let .data(data):
                return data
            case .string:
                continue   // ignore text / ping / pong — Volcengine streams binary frames
            @unknown default:
                continue
            }
        }
    }

    func cancel() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}
