import Accelerate
@preconcurrency import AVFoundation
import Foundation

public struct PitchExtractionConfiguration: Sendable, Equatable {
    public var minFrequency: Double
    public var maxFrequency: Double
    public var frameDuration: Double
    public var hopDuration: Double
    public var minRMS: Float
    public var yinThreshold: Double
    public var maxPoints: Int

    public init(
        minFrequency: Double = 75,
        maxFrequency: Double = 500,
        frameDuration: Double = 0.04,
        hopDuration: Double = 0.02,
        minRMS: Float = 0.006,
        yinThreshold: Double = 0.15,
        maxPoints: Int = 240
    ) {
        self.minFrequency = minFrequency
        self.maxFrequency = maxFrequency
        self.frameDuration = frameDuration
        self.hopDuration = hopDuration
        self.minRMS = minRMS
        self.yinThreshold = yinThreshold
        self.maxPoints = maxPoints
    }
}

public enum PitchContourExtractor {
    public static func extract(
        fileURL: URL,
        configuration: PitchExtractionConfiguration = PitchExtractionConfiguration()
    ) throws -> PitchContour {
        let file = try AVAudioFile(forReading: fileURL)
        let buffer = try readPCMBuffer(from: file)
        return extract(
            samples: monoSamples(from: buffer),
            sampleRate: buffer.format.sampleRate,
            configuration: configuration)
    }

    public static func extract(
        samples: [Float],
        sampleRate: Double,
        configuration: PitchExtractionConfiguration = PitchExtractionConfiguration()
    ) -> PitchContour {
        guard sampleRate > 0,
              samples.count > 8,
              configuration.minFrequency > 0,
              configuration.maxFrequency > configuration.minFrequency else {
            return PitchContour(points: [])
        }

        let frameSize = max(64, Int(sampleRate * configuration.frameDuration))
        let hopSize = max(1, Int(sampleRate * configuration.hopDuration))
        guard frameSize < samples.count else { return PitchContour(points: []) }

        var points = [Double]()
        var start = 0
        while start + frameSize <= samples.count, points.count < configuration.maxPoints {
            var frame = Array(samples[start..<(start + frameSize)])
            removeDCOffset(&frame)
            if rms(frame) >= configuration.minRMS,
               let f0 = estimateYIN(frame: frame, sampleRate: sampleRate, configuration: configuration) {
                points.append(f0)
            }
            start += hopSize
        }

        return PitchContour(points: smooth(points))
    }

    private static func readPCMBuffer(from file: AVAudioFile) throws -> AVAudioPCMBuffer {
        let inputFormat = file.processingFormat
        let frameCapacity = AVAudioFrameCount(max(1, min(file.length, AVAudioFramePosition(UInt32.max))))
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCapacity) else {
            throw CoachAPIError.message("无法读取录音音频。")
        }
        try file.read(into: inputBuffer)

        guard inputFormat.commonFormat == .pcmFormatFloat32, !inputFormat.isInterleaved else {
            guard let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inputFormat.sampleRate,
                channels: inputFormat.channelCount,
                interleaved: false),
                  let outputBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: inputBuffer.frameCapacity),
                  let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                throw CoachAPIError.message("无法转换录音音频。")
            }

            var conversionError: NSError?
            let provider = AudioConverterInputProvider(buffer: inputBuffer)
            let status = converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: provider.provideInput)
            if let conversionError { throw conversionError }
            guard status != .error else {
                throw CoachAPIError.message("无法转换录音音频。")
            }
            return outputBuffer
        }

        return inputBuffer
    }

    private static func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        guard channelCount > 0, frameCount > 0 else { return [] }

        if channelCount == 1 {
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        }

        var samples = Array(repeating: Float(0), count: frameCount)
        for channel in 0..<channelCount {
            let values = UnsafeBufferPointer(start: channelData[channel], count: frameCount)
            for index in 0..<frameCount {
                samples[index] += values[index] / Float(channelCount)
            }
        }
        return samples
    }

    private static func removeDCOffset(_ frame: inout [Float]) {
        guard !frame.isEmpty else { return }
        let mean = frame.reduce(Float(0), +) / Float(frame.count)
        guard mean.isFinite, abs(mean) > 0.000_001 else { return }
        for index in frame.indices {
            frame[index] -= mean
        }
    }

    private static func rms(_ frame: [Float]) -> Float {
        guard !frame.isEmpty else { return 0 }
        var value = Float(0)
        vDSP_rmsqv(frame, 1, &value, vDSP_Length(frame.count))
        return value.isFinite ? value : 0
    }

    private static func estimateYIN(
        frame: [Float],
        sampleRate: Double,
        configuration: PitchExtractionConfiguration
    ) -> Double? {
        let maxLag = min(frame.count - 2, Int(sampleRate / configuration.minFrequency))
        let minLag = max(2, Int(sampleRate / configuration.maxFrequency))
        guard minLag < maxLag else { return nil }

        var difference = Array(repeating: 0.0, count: maxLag + 1)
        for tau in 1...maxLag {
            var sum = 0.0
            let limit = frame.count - tau
            for index in 0..<limit {
                let delta = Double(frame[index] - frame[index + tau])
                sum += delta * delta
            }
            difference[tau] = sum
        }

        var cmnd = Array(repeating: 1.0, count: maxLag + 1)
        var running = 0.0
        for tau in 1...maxLag {
            running += difference[tau]
            cmnd[tau] = running > 0 ? difference[tau] * Double(tau) / running : 1
        }

        if let tau = firstDip(in: cmnd, minLag: minLag, maxLag: maxLag, threshold: configuration.yinThreshold) {
            return frequency(for: tau, cmnd: cmnd, sampleRate: sampleRate, min: configuration.minFrequency, max: configuration.maxFrequency)
        }

        guard let best = (minLag...maxLag).min(by: { cmnd[$0] < cmnd[$1] }),
              cmnd[best] < 0.35 else {
            return nil
        }
        return frequency(for: best, cmnd: cmnd, sampleRate: sampleRate, min: configuration.minFrequency, max: configuration.maxFrequency)
    }

    private static func firstDip(in cmnd: [Double], minLag: Int, maxLag: Int, threshold: Double) -> Int? {
        var tau = minLag
        while tau <= maxLag {
            if cmnd[tau] < threshold {
                while tau + 1 <= maxLag, cmnd[tau + 1] < cmnd[tau] {
                    tau += 1
                }
                return tau
            }
            tau += 1
        }
        return nil
    }

    private static func frequency(
        for tau: Int,
        cmnd: [Double],
        sampleRate: Double,
        min minFrequency: Double,
        max maxFrequency: Double
    ) -> Double? {
        var refinedLag = Double(tau)
        if tau > 1, tau + 1 < cmnd.count {
            let left = cmnd[tau - 1]
            let center = cmnd[tau]
            let right = cmnd[tau + 1]
            let denominator = left - 2 * center + right
            if abs(denominator) > 0.000_001 {
                refinedLag += 0.5 * (left - right) / denominator
            }
        }
        guard refinedLag > 0 else { return nil }
        let value = sampleRate / refinedLag
        guard value >= minFrequency, value <= maxFrequency, value.isFinite else { return nil }
        return value
    }

    private static func smooth(_ points: [Double]) -> [Double] {
        guard points.count >= 3 else { return points }
        return points.indices.map { index in
            let start = max(0, index - 1)
            let end = min(points.count - 1, index + 1)
            let window = points[start...end]
            return window.reduce(0, +) / Double(window.count)
        }
    }
}

private final class AudioConverterInputProvider: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private let lock = NSLock()
    private var didProvideInput = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func provideInput(
        packetCount _: AVAudioPacketCount,
        outStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>
    ) -> AVAudioBuffer? {
        lock.lock()
        defer { lock.unlock() }
        if didProvideInput {
            outStatus.pointee = .noDataNow
            return nil
        }
        didProvideInput = true
        outStatus.pointee = .haveData
        return buffer
    }
}
