import AVFoundation
import Foundation
import Testing
@testable import ResponsayCore

@Test func pitchContourExtractor_detectsStableSinePitch() {
    let samples = sineWave(frequency: 220, duration: 0.5)
    let contour = PitchContourExtractor.extract(samples: samples, sampleRate: 16_000)

    #expect(contour.points.count > 8)
    #expect((median(contour.points) ?? 0) > 210)
    #expect((median(contour.points) ?? 0) < 230)
}

@Test func pitchContourExtractor_tracksRisingPitchDirection() {
    let samples = glissando(startFrequency: 140, endFrequency: 240, duration: 0.6)
    let contour = PitchContourExtractor.extract(samples: samples, sampleRate: 16_000)

    #expect(contour.points.count > 8)
    #expect((contour.points.first ?? 1) < (contour.points.last ?? 0))
}

@Test func pitchContourExtractor_ignoresSilence() {
    let contour = PitchContourExtractor.extract(
        samples: Array(repeating: 0, count: 8_000),
        sampleRate: 16_000)

    #expect(contour.points.isEmpty)
}

@Test func pitchContourExtractor_readsAVAudioFile() throws {
    let samples = sineWave(frequency: 180, duration: 0.45)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("responsay-pitch-\(UUID().uuidString)")
        .appendingPathExtension("caf")
    defer { try? FileManager.default.removeItem(at: url) }

    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
    buffer.frameLength = AVAudioFrameCount(samples.count)
    let channel = buffer.floatChannelData![0]
    for (index, value) in samples.enumerated() {
        channel[index] = value
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)

    let contour = try PitchContourExtractor.extract(fileURL: url)

    #expect(contour.points.count > 8)
    #expect((median(contour.points) ?? 0) > 170)
    #expect((median(contour.points) ?? 0) < 201)
}

private func sineWave(frequency: Double, duration: Double, sampleRate: Double = 16_000) -> [Float] {
    let count = Int(duration * sampleRate)
    return (0..<count).map { index in
        Float(sin(2 * Double.pi * frequency * Double(index) / sampleRate) * 0.35)
    }
}

private func glissando(
    startFrequency: Double,
    endFrequency: Double,
    duration: Double,
    sampleRate: Double = 16_000
) -> [Float] {
    let count = Int(duration * sampleRate)
    var phase = 0.0
    return (0..<count).map { index in
        let progress = Double(index) / Double(max(1, count - 1))
        let frequency = startFrequency + (endFrequency - startFrequency) * progress
        phase += 2 * Double.pi * frequency / sampleRate
        return Float(sin(phase) * 0.35)
    }
}

private func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
}
