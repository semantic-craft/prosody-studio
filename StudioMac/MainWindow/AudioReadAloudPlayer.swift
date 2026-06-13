import AVFoundation
import OSLog
import ResponsayCore

/// Plays a `ComposedReadAloud`'s chunks gaplessly on an `AVAudioPlayerNode` and
/// exposes the real playback `elapsed` time so `ReadAloudController` can drive the
/// word highlight from the audio clock instead of an estimate (issue 194).
///
/// Real audio output is **not** verifiable in the simulator / headless (CLAUDE.md);
/// the scheduling math + elapsed clock are correct by construction and exercised on
/// a real Mac (test standard T3). The estimated-clock path remains the fallback.
@MainActor
final class AudioReadAloudPlayer: ReadAloudAudioPlaying {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var startSampleTime: AVAudioFramePosition?
    private var sampleRate: Double = 24_000
    private var totalDuration: TimeInterval = 0
    private static let log = Logger(
        subsystem: "com.semanticcraft.responsay.mac", category: "ReadAloudAudio")

    init() {
        engine.attach(node)
    }

    /// Elapsed playback time in seconds (0 before start, clamped to total).
    var elapsed: TimeInterval {
        guard let startSampleTime,
              let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime) else { return 0 }
        let frames = playerTime.sampleTime - startSampleTime
        let seconds = Double(max(0, frames)) / sampleRate
        return min(seconds, totalDuration)
    }

    var isFinished: Bool { elapsed >= totalDuration && totalDuration > 0 }

    /// Schedule the composed chunks and start playing. Throws if audio setup fails.
    func play(_ composed: ComposedReadAloud) throws {
        stop()
        guard let first = composed.chunks.first else { return }
        sampleRate = Double(first.sampleRate)
        totalDuration = composed.totalDuration
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
            channels: 1, interleaved: false) else {
            throw TTSError.synthesisFailed("无法创建音频格式")
        }
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try engine.start()

        for chunk in composed.chunks {
            guard let buffer = Self.buffer(from: chunk.samples, format: format) else { continue }
            node.scheduleBuffer(buffer, completionHandler: nil)
        }
        node.play()
        if let nodeTime = node.lastRenderTime,
           let playerTime = node.playerTime(forNodeTime: nodeTime) {
            startSampleTime = playerTime.sampleTime
        } else {
            startSampleTime = 0
        }
    }

    func pause() { node.pause() }
    func resume() { node.play() }

    func stop() {
        node.stop()
        if engine.isRunning { engine.stop() }
        startSampleTime = nil
        totalDuration = 0
        streaming = false
        streamFormat = nil
        accumulated = 0
    }

    // MARK: - 197 incremental streaming playback

    private var streaming = false
    private var accumulated: TimeInterval = 0
    private var streamFormat: AVAudioFormat?

    /// Begin a streaming session (issue 197): start the node and accept chunks as
    /// they arrive, for low time-to-first-audio. `elapsed` / `totalDuration` grow as
    /// chunks are appended (we don't know the full length up front).
    func beginStreaming(sampleRate: Double) throws {
        stop()
        self.sampleRate = sampleRate
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
            channels: 1, interleaved: false) else {
            throw TTSError.synthesisFailed("无法创建音频格式")
        }
        streamFormat = format
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try engine.start()
        node.play()
        if let nodeTime = node.lastRenderTime,
           let playerTime = node.playerTime(forNodeTime: nodeTime) {
            startSampleTime = playerTime.sampleTime
        } else {
            startSampleTime = 0
        }
        streaming = true
    }

    /// Schedule one streaming chunk on the player node; returns the new accumulated
    /// total duration. Buffers queue gaplessly behind whatever is already playing.
    @discardableResult
    func appendStreaming(_ speech: SynthesizedSpeech) -> TimeInterval {
        guard streaming, let format = streamFormat,
              let buffer = Self.buffer(from: speech.samples, format: format) else {
            return accumulated
        }
        node.scheduleBuffer(buffer, completionHandler: nil)
        accumulated += speech.duration
        totalDuration = accumulated
        return accumulated
    }

    /// No more chunks will arrive — the accumulated duration is now final.
    func endStreaming() { streaming = false }

    private static func buffer(from samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData else { return nil }
        samples.withUnsafeBufferPointer { src in
            channel[0].update(from: src.baseAddress!, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }
}
