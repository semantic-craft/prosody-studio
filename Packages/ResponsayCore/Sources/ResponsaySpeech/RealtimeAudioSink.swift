import AVFoundation
import AVFAudio
import Foundation
import ResponsayCore

/// Shared microphone → 16 kHz / 16-bit / mono PCM sink for the streaming ASR
/// capture services (Qwen realtime, Volcengine streaming). Converts each input
/// buffer, emits RMS levels (0...1) for the waveform, gates out leading silence,
/// and packetizes into fixed frames as ``AudioChunk``s.
///
/// Extracted from `RealtimeQwenSpeechCaptureService` so the Volcengine service can
/// reuse the exact same proven conversion + speech-gate path.
final class RealtimeAudioSink: @unchecked Sendable {
    private static let targetSampleRate = 16_000.0
    private static let speechLevelThreshold: Float = 0.06
    private static let speechStartDuration: TimeInterval = 0.18

    private let lock = NSLock()
    private let converter: AVAudioConverter
    private let targetFormat: AVAudioFormat
    private let audioContinuation: AsyncStream<AudioChunk>.Continuation?
    private let bridge: DeferredAudioBridge?
    private let levelContinuation: AsyncStream<Float>.Continuation
    private var packetizer = AudioPacketizer()
    private var candidateSpeechDuration: TimeInterval = 0
    private var speechDetected = false
    private var finished = false

    init(
        sourceFormat: AVAudioFormat,
        audioContinuation: AsyncStream<AudioChunk>.Continuation,
        levelContinuation: AsyncStream<Float>.Continuation
    ) throws {
        self.bridge = nil
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: true),
            let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw CoachAPIError.message("无法创建 16kHz mono PCM 转换器。")
        }
        self.converter = converter
        self.targetFormat = targetFormat
        self.audioContinuation = audioContinuation
        self.levelContinuation = levelContinuation
    }

    init(
        sourceFormat: AVAudioFormat,
        bridge: DeferredAudioBridge,
        levelContinuation: AsyncStream<Float>.Continuation
    ) throws {
        self.audioContinuation = nil
        self.bridge = bridge
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: true),
            let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw CoachAPIError.message("无法创建 16kHz mono PCM 转换器。")
        }
        self.converter = converter
        self.targetFormat = targetFormat
        self.levelContinuation = levelContinuation
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        let level = Self.level(from: buffer)
        levelContinuation.yield(level)
        updateSpeechGate(level: level, duration: buffer.duration)
        guard speechDetected, let pcm = convert(buffer) else { return }
        for chunk in packetizer.append(pcm) {
            if let bridge { bridge.send(chunk) }
            else { audioContinuation?.yield(chunk) }
        }
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        if let chunk = packetizer.flush() {
            if let bridge { bridge.send(chunk) }
            else { audioContinuation?.yield(chunk) }
        }
        finished = true
        audioContinuation?.finish()
        levelContinuation.finish()
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 512
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
            return nil
        }

        var provided = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if provided {
                outStatus.pointee = .noDataNow
                return nil
            }
            provided = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error else { return nil }
        let audioBuffer = output.audioBufferList.pointee.mBuffers
        guard let bytes = audioBuffer.mData, audioBuffer.mDataByteSize > 0 else { return nil }
        return Data(bytes: bytes, count: Int(audioBuffer.mDataByteSize))
    }

    private func updateSpeechGate(level: Float, duration: TimeInterval) {
        guard !speechDetected else { return }
        if level >= Self.speechLevelThreshold {
            candidateSpeechDuration += duration
        } else {
            candidateSpeechDuration = 0
        }
        if candidateSpeechDuration >= Self.speechStartDuration {
            speechDetected = true
        }
    }

    private static func level(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sumOfSquares: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sumOfSquares += sample * sample
        }
        return min(1, (sumOfSquares / Float(count)).squareRoot() * 8)
    }
}

extension AVAudioPCMBuffer {
    var duration: TimeInterval {
        guard format.sampleRate > 0 else { return 0 }
        return TimeInterval(frameLength) / format.sampleRate
    }
}
