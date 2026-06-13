import Foundation

/// One framed PCM chunk ready to stream to `input_audio_buffer.append`.
public struct AudioChunk: Sendable, Equatable {
    /// Monotonic index across the whole session. A future transport layer may
    /// use it to derive event ids or de-duplicate after a reconnect; this core
    /// only guarantees the index is contiguous and increasing.
    public let sequence: Int
    /// Raw little-endian Int16 PCM bytes (base64 encoding happens at the wire layer).
    public let pcm: Data

    public init(sequence: Int, pcm: Data) {
        self.sequence = sequence
        self.pcm = pcm
    }
}

/// Buffers a PCM byte stream and emits fixed-size frames.
///
/// The realtime API streams better with small, regular chunks; this splits the
/// incoming audio into `frameByteCount`-sized pieces (default ~100 ms at
/// 16 kHz/mono/Int16) and assigns each a monotonic ``AudioChunk/sequence``.
public struct AudioPacketizer: Sendable {
    private let frameByteCount: Int
    private var buffer = Data()
    private var nextSequence = 0

    public init(frameByteCount: Int = 3200) {
        precondition(frameByteCount > 0, "frameByteCount must be positive")
        self.frameByteCount = frameByteCount
    }

    /// Append more PCM and return any whole frames it completed.
    public mutating func append(_ pcm: Data) -> [AudioChunk] {
        buffer.append(pcm)
        var chunks: [AudioChunk] = []
        while buffer.count >= frameByteCount {
            let frame = buffer.prefix(frameByteCount)
            chunks.append(AudioChunk(sequence: nextSequence, pcm: Data(frame)))
            nextSequence += 1
            buffer.removeFirst(frameByteCount)
        }
        return chunks
    }

    /// Emit whatever audio remains as a final (possibly short) chunk. Returns
    /// `nil` when the buffer is empty. Call once at end-of-utterance.
    public mutating func flush() -> AudioChunk? {
        guard !buffer.isEmpty else { return nil }
        let chunk = AudioChunk(sequence: nextSequence, pcm: Data(buffer))
        nextSequence += 1
        buffer.removeAll(keepingCapacity: false)
        return chunk
    }
}
