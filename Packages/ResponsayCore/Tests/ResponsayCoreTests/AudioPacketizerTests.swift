import Testing
import Foundation
@testable import ResponsayCore

/// Frames a 16 kHz / mono / Int16 PCM stream into fixed ~100 ms chunks with a
/// monotonic sequence, as the realtime client streams to
/// `input_audio_buffer.append`. 100 ms = 16000 Hz × 0.1 s × 2 bytes = 3200 B.
@Suite struct AudioPacketizerTests {
    @Test func emitsOneChunkWhenExactlyOneFrameAppended() {
        var packetizer = AudioPacketizer()
        let frame = Data(repeating: 0xAB, count: 3200)
        let chunks = packetizer.append(frame)
        #expect(chunks == [AudioChunk(sequence: 0, pcm: frame)])
    }

    @Test func partialFrameIsHeldUntilFlush() {
        var packetizer = AudioPacketizer()
        let partial = Data(repeating: 0x01, count: 1000)
        #expect(packetizer.append(partial).isEmpty)
        #expect(packetizer.flush() == AudioChunk(sequence: 0, pcm: partial))
        #expect(packetizer.flush() == nil)
    }

    @Test func splitsMultipleFramesAndContinuesSequenceAcrossAppends() {
        var packetizer = AudioPacketizer()
        // 2 whole frames + 100 B leftover.
        let first = packetizer.append(Data(repeating: 0x02, count: 3200 * 2 + 100))
        #expect(first.map(\.sequence) == [0, 1])
        #expect(first.allSatisfy { $0.pcm.count == 3200 })
        // 100 B carried over + 1500 B = 1600 B, still below a frame.
        #expect(packetizer.append(Data(repeating: 0x03, count: 1500)).isEmpty)
        let tail = packetizer.flush()
        #expect(tail?.sequence == 2)
        #expect(tail?.pcm.count == 1600)
    }

    @Test func chunksPreserveExactByteBoundaries() {
        // Distinguishable byte pattern so an off-by-one slice or mis-ordered
        // concat would change chunk *contents*, not just lengths.
        var packetizer = AudioPacketizer()
        let stream = Data((0..<7000).map { UInt8($0 % 251) })
        var chunks = packetizer.append(stream)
        if let tail = packetizer.flush() { chunks.append(tail) }
        #expect(chunks.map(\.sequence) == [0, 1, 2])
        #expect(chunks[0].pcm == stream.subdata(in: 0..<3200))
        #expect(chunks[1].pcm == stream.subdata(in: 3200..<6400))
        #expect(chunks[2].pcm == stream.subdata(in: 6400..<7000))
    }
}
