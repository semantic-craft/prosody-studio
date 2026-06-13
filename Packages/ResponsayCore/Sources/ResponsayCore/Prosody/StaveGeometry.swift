import Foundation

// MARK: - 144 toStave() geometry (v2: per-lane, tone-across-group + emphasis)
//
// The model emits `ProsodyAnalysis` (words + tone + stress), NEVER coordinates.
// `toStave` is the *rendering* job: one **lane per thought group**; the tone
// shapes the whole lane's baseline (fall = steady descent…) and stress lifts
// individual points so重音 is visible. Ported from the proven vscode-english-coach
// `stave.ts`, tuned for the warm native renderer. Liaisons are app-computed
// (`LiaisonRules`), not model-emitted.

public enum StavePointKind: String, Sendable, Equatable {
    case nuclear, stressed, reduced, plain
}

public enum StaveLinkKind: String, Sendable, Equatable {
    case liaison, elision, intrusion
    init(_ link: Link) {
        switch link {
        case .liaison: self = .liaison
        case .elision: self = .elision
        case .intrusion: self = .intrusion
        }
    }
}

/// One word in a lane, with the syllable detail the renderer marks stress on.
public struct StaveToken: Sendable, Equatable {
    public let index: Int                 // position within the lane
    public let text: String
    public let syllables: [String]
    public let stressIndex: Int?          // which syllable carries primary stress
    public let stressed: Bool
    public let nuclear: Bool
    public let reduced: Bool              // stressIndex == nil
    public let ipa: String?
    public let link: StaveLinkKind?       // app-computed liaison to the next word

    public init(index: Int, text: String, syllables: [String], stressIndex: Int?,
                stressed: Bool, nuclear: Bool, reduced: Bool, ipa: String?, link: StaveLinkKind?) {
        self.index = index
        self.text = text
        self.syllables = syllables
        self.stressIndex = stressIndex
        self.stressed = stressed
        self.nuclear = nuclear
        self.reduced = reduced
        self.ipa = ipa
        self.link = link
    }
}

/// A point on the lane's pitch contour, aligned above its word. `pitch` 1 = high.
public struct StavePoint: Sendable, Equatable {
    public let x: Double
    public let pitch: Double
    public let kind: StavePointKind
    public init(x: Double, pitch: Double, kind: StavePointKind) {
        self.x = x
        self.pitch = pitch
        self.kind = kind
    }
}

/// One thought group = one rendered lane (card). Long sentences stack lanes.
public struct StaveLane: Sendable, Equatable {
    public let tone: Tone
    public let toneArrow: String
    public let toneLabel: String
    public let tokens: [StaveToken]
    public let points: [StavePoint]

    public init(tone: Tone, toneArrow: String, toneLabel: String, tokens: [StaveToken], points: [StavePoint]) {
        self.tone = tone
        self.toneArrow = toneArrow
        self.toneLabel = toneLabel
        self.tokens = tokens
        self.points = points
    }
}

public enum ProsodyStave {
    static let arrows: [Tone: String] = [
        .fall: "↘", .rise: "↗", .level: "→", .fallRise: "↘↗", .riseFall: "↗↘",
    ]
    static let labels: [Tone: String] = [
        .fall: "fall", .rise: "rise", .level: "level", .fallRise: "fall-rise", .riseFall: "rise-fall",
    ]

    /// Derive the lanes. Deterministic, pure (given the same liaison rules).
    public static func toStave(_ analysis: ProsodyAnalysis, liaison: LiaisonRules = LiaisonRules()) -> [StaveLane] {
        analysis.thoughtGroups.map { group in
            let count = group.words.count
            let last = max(count - 1, 1)
            let tokens: [StaveToken] = group.words.enumerated().map { index, word in
                let next = index + 1 < group.words.count ? group.words[index + 1] : nil
                let link = next.flatMap { liaison.link(leftIPA: word.ipa, rightIPA: $0.ipa) }
                return StaveToken(
                    index: index, text: word.text, syllables: word.syllables,
                    stressIndex: word.stressIndex, stressed: word.stressed, nuclear: word.nuclear,
                    reduced: word.stressIndex == nil, ipa: word.ipa,
                    link: link.map(StaveLinkKind.init)
                )
            }
            let points: [StavePoint] = tokens.map { token in
                let progress = count == 1 ? 0.5 : Double(token.index) / Double(last)
                let x = count == 1 ? 0.5 : 0.08 + progress * 0.84
                let pitch = clamp(baseline(group.tone, progress) + emphasis(token), 0.30, 0.88)
                return StavePoint(x: x, pitch: pitch, kind: kind(token))
            }
            return StaveLane(
                tone: group.tone,
                toneArrow: arrows[group.tone] ?? "→",
                toneLabel: labels[group.tone] ?? group.tone.rawValue,
                tokens: tokens, points: points
            )
        }
    }

    // MARK: - Pitch model (1 = high)

    /// Tone shapes the whole lane; stress/reduction offsets land on top.
    static func baseline(_ tone: Tone, _ p: Double) -> Double {
        switch tone {
        case .fall:     return 0.70 - p * 0.34          // steady descent
        case .rise:     return 0.36 + p * 0.34          // steady ascent
        case .level:    return 0.54
        case .fallRise: return 0.70 - sinHump(p) * 0.34 // high → low → high
        case .riseFall: return 0.36 + sinHump(p) * 0.34 // low → high → low
        }
    }

    static func emphasis(_ token: StaveToken) -> Double {
        if token.nuclear { return 0.10 }
        if token.stressed { return 0.06 }
        if token.reduced { return -0.08 }
        return 0
    }

    private static func kind(_ token: StaveToken) -> StavePointKind {
        if token.nuclear { return .nuclear }
        if token.stressed { return .stressed }
        if token.reduced { return .reduced }
        return .plain
    }

    private static func sinHump(_ p: Double) -> Double {
        // 0 at the ends, 1 at the middle (a single smooth hump).
        sin(max(0, min(1, p)) * Double.pi)
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(high, max(low, value))
    }
}
