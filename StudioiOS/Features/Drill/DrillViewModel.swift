import Foundation
import Observation
import SwiftUI
import ResponsayCore

@MainActor
@Observable
final class DrillViewModel {
    var mode: RepeatMode = .sentence
    var count = 3
    var interval: TimeInterval = 1.5
    var speed = 1.0
    var autoAdvance = true
    var selectedSentenceIndex = 0
    var abStart: TimeInterval = 2.4
    var abEnd: TimeInterval = 5.1
    private(set) var events: [String] = ["准备"]

    let sentences = [
        RepeatSentence(index: 0, text: "I want to fix this bug.", startTime: 0, endTime: 2.4),
        RepeatSentence(index: 1, text: "I'm not sure that conclusion holds up.", startTime: 2.4, endTime: 5.1),
        RepeatSentence(index: 2, text: "Let's revise the claim before the meeting.", startTime: 5.1, endTime: 8.3)
    ]

    private var controller = RepeatController()
    var state: RepeatState { controller.state }

    var statusTitle: String {
        switch state.phase {
        case .idle: "空闲"
        case .playing: "播放"
        case .waiting: "间隔"
        case .paused: "暂停"
        }
    }

    var statusIcon: String {
        switch state.phase {
        case .idle: "repeat"
        case .playing: "waveform"
        case .waiting: "timer"
        case .paused: "pause.fill"
        }
    }

    var statusColor: Color {
        switch state.phase {
        case .idle: .secondary
        case .playing: Theme.accent
        case .waiting: .orange
        case .paused: .secondary
        }
    }

    var currentText: String {
        guard let config = state.config else { return selectedSentence?.text ?? "" }
        switch config.mode {
        case .ab: return "AB \(timeLabel(config.startTime)) - \(timeLabel(config.endTime))"
        case .full: return fullText
        case .sentence:
            return sentences.first(where: { $0.index == config.sentenceIndex })?.text ?? selectedSentence?.text ?? ""
        }
    }

    var roundText: String {
        guard let count = state.config?.count, state.currentRound > 0 else { return "\(self.count) 轮" }
        return "\(state.currentRound)/\(count)"
    }

    var roundProgress: Double {
        guard let count = state.config?.count, count > 0 else { return 0 }
        return Double(state.currentRound) / Double(count)
    }

    var rangeText: String {
        guard let config = state.config else { return selectedRangeText }
        return "\(timeLabel(config.startTime)) - \(timeLabel(config.endTime))"
    }

    var speedText: String { String(format: "%.2gx", state.config?.speed ?? speed) }
    var fullText: String { sentences.map(\.text).joined(separator: " ") }
    var fullRangeText: String { "\(timeLabel(sentences.first?.startTime ?? 0)) - \(timeLabel(sentences.last?.endTime ?? 0))" }

    func start() {
        do {
            let command: RepeatCommand
            switch mode {
            case .ab:
                normalizeABRange()
                command = try controller.startABRepeat(
                    startTime: abStart,
                    endTime: abEnd,
                    count: count,
                    interval: interval,
                    speed: speed)
            case .sentence:
                command = try controller.startSentenceRepeat(
                    sentenceIndex: selectedSentenceIndex,
                    sentences: sentences,
                    count: count,
                    interval: interval,
                    speed: speed,
                    autoAdvance: autoAdvance)
            case .full:
                command = try controller.startFullRepeat(
                    sentences: sentences,
                    count: count,
                    interval: interval,
                    speed: speed)
            }
            record(command)
        } catch {
            record("错误 \(error.localizedDescription)")
        }
    }

    func completeSegment() {
        if state.phase == .waiting {
            record(controller.completeInterval())
        } else {
            record(controller.completeSegment())
        }
        syncSelectedSentence()
    }

    func togglePause() {
        if state.phase == .paused {
            record(controller.resume())
        } else if state.phase == .playing {
            let start = state.config?.startTime ?? 0
            let end = state.config?.endTime ?? start
            record(controller.pause(at: (start + end) / 2))
        }
    }

    func updateSpeed(_ value: Double) {
        guard state.phase != .idle else { return }
        record(controller.setSpeed(value))
    }

    func stop() {
        controller.stop()
        record(.stop)
    }

    func normalizeABRange() {
        if abEnd <= abStart {
            abEnd = min(12, abStart + 0.2)
        }
        if abStart >= abEnd {
            abStart = max(0, abEnd - 0.2)
        }
    }

    func timeLabel(_ value: TimeInterval) -> String {
        String(format: "%.1fs", value)
    }

    func rangeLabel(for sentence: RepeatSentence) -> String {
        "\(timeLabel(sentence.startTime))-\(timeLabel(sentence.endTime))"
    }

    private var selectedSentence: RepeatSentence? {
        sentences.first { $0.index == selectedSentenceIndex }
    }

    private var selectedRangeText: String {
        if mode == .ab {
            return "\(timeLabel(abStart)) - \(timeLabel(abEnd))"
        }
        if mode == .full { return fullRangeText }
        return selectedSentence.map(rangeLabel) ?? ""
    }

    private func syncSelectedSentence() {
        guard let index = state.config?.sentenceIndex else { return }
        selectedSentenceIndex = index
    }

    private func record(_ command: RepeatCommand) {
        record(label(for: command))
    }

    private func record(_ event: String) {
        events.insert(event, at: 0)
        if events.count > 5 { events.removeLast(events.count - 5) }
    }

    private func label(for command: RepeatCommand) -> String {
        switch command {
        case .play(let start, let end, let speed):
            "play \(timeLabel(start))-\(timeLabel(end)) @ \(String(format: "%.2gx", speed))"
        case .wait(let duration):
            "wait \(timeLabel(duration))"
        case .pause:
            "pause"
        case .stop:
            "stop"
        case .updateSpeed(let speed):
            "speed \(String(format: "%.2gx", speed))"
        }
    }
}
