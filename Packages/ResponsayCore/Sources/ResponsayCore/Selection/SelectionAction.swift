import Foundation

/// The opinionated, context-aware actions a text selection can route to
/// (ADR-0022). There is deliberately **no free-form chat** action; `ask` is a
/// bounded, structured action. Only the chosen main transform auto-inserts
/// (ADR-0019); everything else previews or opens a panel.
public enum SelectionAction: String, Sendable, Equatable, CaseIterable {
    case legalSkill     // route through the LEGAL_SKILL palette (context-aware)
    case verify         // 来源核验: extractable 法条/案号/文献 → 一键开权威源 (215)
    case polish         // rewriteSelection (existing ⌥R)
    case translate      // translateSelection (existing ⌥T)
    case coachIdiomatic // English sentence → 地道表达 coach (preview, never silent insert) — 300
    case analyzeProsody  // English sentence → 韵律分析 (analysis feedback)
    case enterRepeat    // English sentence → 进跟读 (practice seed, 125)
    case readAloud      // 朗读 (English sentence) — 136
    case addToDictionary // term-shaped selection → 识别词典 (hotword biasing) — 300
    case ask            // bounded structured help — NOT open chat

    public var title: String {
        switch self {
        case .legalSkill:  return "法律技能"
        case .verify:      return "来源核验"
        case .polish:      return "改写"
        case .translate:   return "翻译"
        case .coachIdiomatic: return "地道表达"
        case .analyzeProsody: return "分析韵律"
        case .enterRepeat: return "进跟读"
        case .readAloud:   return "朗读"
        case .addToDictionary: return "加入词典"
        case .ask:         return "追问"
        }
    }

    public var systemImage: String {
        switch self {
        case .legalSkill:  return "scalemass"
        case .verify:      return "checkmark.seal"
        case .polish:      return "wand.and.stars"
        case .translate:   return "character.book.closed"
        case .coachIdiomatic: return "sparkles"
        case .analyzeProsody: return "waveform.path.ecg"
        case .enterRepeat: return "repeat"
        case .readAloud:   return "speaker.wave.2"
        case .addToDictionary: return "text.book.closed"
        case .ask:         return "bubble.left.and.text.bubble.right"
        }
    }

    /// Only `polish` / `translate` may auto-insert their result (the chosen main
    /// transform). The rest open a panel / seed a session — never silent insert.
    public var autoInserts: Bool { self == .polish || self == .translate }

    /// `ask` is the bounded, structured action (ADR-0022) — it is the only one
    /// that could be mistaken for chat, so it is explicitly marked bounded.
    public var isBounded: Bool { self == .ask }
}
