import Foundation

/// Buffers audio chunks while a WebSocket connection is being established, then
/// flushes them all at once when the connection is ready.
///
/// Modeled after openless's `DeferredAsrBridge` (`asr_setup.rs:464-528`).
/// Uses NSLock (not an actor) so ``send(_:)`` is synchronous and safe to call
/// from the audio tap thread. Matches the ``RealtimeAudioSink`` thread-safety
/// pattern already used in the codebase.
///
/// State machine: `buffering` → `attached` → `finished`.
/// - `buffering`: chunks accumulate in an array.
/// - `attached`: ``attach(_:)`` returns the buffered array; subsequent sends
///   go directly to the consumer closure.
/// - `finished`: sends are no-ops.
public final class DeferredAudioBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [AudioChunk] = []
    private var consumer: ((AudioChunk) -> Void)?
    private var isFinished = false
    private var _flushedChunkCount = 0
    private var _flushedByteCount = 0

    public init() {}

    /// Accept one chunk. If not yet attached, buffers it. If attached, passes
    /// it directly to the consumer. If finished, drops it.
    public func send(_ chunk: AudioChunk) {
        lock.lock()
        if isFinished {
            lock.unlock()
            return
        }
        if let consumer {
            lock.unlock()
            consumer(chunk)
        } else {
            buffer.append(chunk)
            lock.unlock()
        }
    }

    /// Flush all buffered chunks and switch to passthrough. Returns the buffered
    /// chunks; subsequent ``send(_:)`` calls invoke `consumer` directly.
    ///
    /// The no-consumer overload is for callers that process the flushed array
    /// themselves and don't need passthrough (e.g. a loop that awaits each send).
    @discardableResult
    public func attach(_ consumer: ((AudioChunk) -> Void)? = nil) -> [AudioChunk] {
        lock.lock()
        let flushed = buffer
        buffer = []
        self.consumer = consumer
        _flushedChunkCount = flushed.count
        _flushedByteCount = flushed.reduce(0) { $0 + $1.pcm.count }
        lock.unlock()
        return flushed
    }

    /// Mark the bridge as finished. No more chunks will be accepted or forwarded.
    public func finish() {
        lock.lock()
        isFinished = true
        consumer = nil
        lock.unlock()
    }

    /// Number of chunks returned by the last ``attach(_:)`` call.
    public var flushedChunkCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _flushedChunkCount
    }

    /// Total PCM bytes returned by the last ``attach(_:)`` call.
    public var flushedByteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _flushedByteCount
    }
}
