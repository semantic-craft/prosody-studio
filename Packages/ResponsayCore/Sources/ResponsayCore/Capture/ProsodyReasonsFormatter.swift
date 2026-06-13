import Foundation

// MARK: - 372 ProsodyReasonsFormatter
//
// The prosody "reason line" formatting lifted off QuickCaptureViewModel. A pure
// function of a `ProsodyAnalysis` → the Chinese coaching lines (升降调 / 重音 /
// 连读 / IPA / notes) the feedback modes surface. No actor isolation, no I/O,
// no VM state — directly unit-testable.

public struct ProsodyReasonsFormatter: Sendable {
    public init() {}

    public func reasons(from analysis: ProsodyAnalysis, heading: String) -> [String] {
        var reasons = [heading]

        let tones = analysis.thoughtGroups.enumerated().map { index, group in
            "第\(index + 1)组 \(toneLabel(group.tone))"
        }
        if !tones.isEmpty {
            reasons.append("升降调: \(tones.joined(separator: " / "))")
        }

        let stressed = analysis.thoughtGroups
            .flatMap(\.words)
            .filter { $0.stressed || $0.nuclear }
            .map(\.text)
        if !stressed.isEmpty {
            reasons.append("重音: \(stressed.prefix(10).joined(separator: ", "))")
        }

        let links = linkingHints(from: analysis)
        if !links.isEmpty {
            reasons.append("连读: \(links.prefix(6).joined(separator: " / "))")
        }

        if !analysis.ipa.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reasons.append("IPA: \(analysis.ipa)")
        }

        if let notes = analysis.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !notes.isEmpty {
            reasons.append(notes)
        }

        return reasons
    }

    private func linkingHints(from analysis: ProsodyAnalysis) -> [String] {
        analysis.thoughtGroups.flatMap { group in
            group.words.enumerated().compactMap { index, word in
                guard let link = word.linkToNext, index + 1 < group.words.count else { return nil }
                return "\(word.text) \(linkLabel(link)) \(group.words[index + 1].text)"
            }
        }
    }

    private func toneLabel(_ tone: Tone) -> String {
        switch tone {
        case .fall: "降调"
        case .rise: "升调"
        case .fallRise: "降升调"
        case .riseFall: "升降调"
        case .level: "平调"
        }
    }

    private func linkLabel(_ link: Link) -> String {
        switch link {
        case .liaison: "连到"
        case .elision: "省音连到"
        case .intrusion: "加音连到"
        }
    }
}
