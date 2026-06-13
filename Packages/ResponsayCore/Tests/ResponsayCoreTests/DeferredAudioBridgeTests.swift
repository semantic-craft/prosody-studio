import Testing
import Foundation
@testable import ResponsayCore

private final class ChunkCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [AudioChunk] = []

    func append(_ chunk: AudioChunk) {
        lock.lock()
        chunks.append(chunk)
        lock.unlock()
    }

    func appendAll(_ newChunks: [AudioChunk]) {
        lock.lock()
        chunks.append(contentsOf: newChunks)
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return chunks.count
    }
}

@Suite struct DeferredAudioBridgeTests {

    private func chunk(_ seq: Int, bytes: Int = 100) -> AudioChunk {
        AudioChunk(sequence: seq, pcm: Data(repeating: UInt8(seq & 0xFF), count: bytes))
    }

    // MARK: - Buffer then flush

    @Test func buffersChunksBeforeAttach() {
        let bridge = DeferredAudioBridge()
        bridge.send(chunk(1))
        bridge.send(chunk(2))
        bridge.send(chunk(3))

        let flushed = bridge.attach()
        #expect(flushed.count == 3)
        #expect(flushed[0].sequence == 1)
        #expect(flushed[1].sequence == 2)
        #expect(flushed[2].sequence == 3)
    }

    @Test func attachReturnsEmptyWhenNoChunksBuffered() {
        let bridge = DeferredAudioBridge()
        let flushed = bridge.attach()
        #expect(flushed.isEmpty)
    }

    // MARK: - Passthrough after attach

    @Test func passthroughAfterAttach() {
        let bridge = DeferredAudioBridge()
        var received: [AudioChunk] = []
        _ = bridge.attach { received.append($0) }

        bridge.send(chunk(10))
        bridge.send(chunk(11))
        #expect(received.count == 2)
        #expect(received[0].sequence == 10)
        #expect(received[1].sequence == 11)
    }

    // MARK: - Finish

    @Test func sendAfterFinishIsNoOp() {
        let bridge = DeferredAudioBridge()
        bridge.send(chunk(1))
        bridge.finish()
        bridge.send(chunk(2))

        let flushed = bridge.attach()
        #expect(flushed.count == 1)
        #expect(flushed[0].sequence == 1)
    }

    @Test func finishAfterAttachStopsPassthrough() {
        let bridge = DeferredAudioBridge()
        var received: [AudioChunk] = []
        _ = bridge.attach { received.append($0) }

        bridge.send(chunk(1))
        bridge.finish()
        bridge.send(chunk(2))
        #expect(received.count == 1)
    }

    // MARK: - Thread safety

    @Test func concurrentSendAndAttachDoesNotCrash() async {
        let bridge = DeferredAudioBridge()
        let collector = ChunkCollector()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    bridge.send(AudioChunk(sequence: i, pcm: Data(repeating: 0, count: 64)))
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 1_000_000)
                let flushed = bridge.attach { chunk in
                    collector.append(chunk)
                }
                collector.appendAll(flushed)
            }
        }
        // All 100 chunks should arrive either via flush or passthrough — no lost audio.
        #expect(collector.count == 100)
    }

    // MARK: - Stats

    @Test func reportsFlushedStats() {
        let bridge = DeferredAudioBridge()
        bridge.send(chunk(1, bytes: 200))
        bridge.send(chunk(2, bytes: 300))
        let flushed = bridge.attach()
        #expect(flushed.count == 2)
        #expect(bridge.flushedChunkCount == 2)
        #expect(bridge.flushedByteCount == 500)
    }
}
