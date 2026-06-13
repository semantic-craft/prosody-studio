import Foundation

/// App-side connected-speech detection (issue 144 v2). The prosody model emits
/// `linkToNext = null`; the app adds clear learner-facing links deterministically
/// from the boundary phonemes (so the model can't mis-mark them):
///
/// - **liaison**  consonant → vowel  ("holds_up" /z/+/ʌ/)
/// - **intrusion** vowel → vowel      ("go_on" /oʊ/+/ɑ/ → /w/)
/// - **elision**  identical adjacent consonant ("good_day" /d/+/d/)
public struct LiaisonRules: Sendable {
    public init() {}

    /// IPA vowel base letters (modifiers like ˈ ˌ ː are stripped first).
    static let vowels: Set<Character> = [
        "i", "ɪ", "e", "ɛ", "æ", "ə", "ɚ", "ɝ", "ɜ", "ʌ", "ɑ", "ɒ", "ɔ",
        "o", "ʊ", "u", "y", "a", "ɐ", "ɤ", "ɯ",
    ]

    public func link(leftIPA: String?, rightIPA: String?) -> Link? {
        guard let left = Self.lastSound(leftIPA), let right = Self.firstSound(rightIPA) else { return nil }
        let leftVowel = Self.vowels.contains(left)
        let rightVowel = Self.vowels.contains(right)

        if !leftVowel, rightVowel { return .liaison }
        if leftVowel, rightVowel { return .intrusion }
        if !leftVowel, !rightVowel, left == right { return .elision }
        return nil
    }

    // MARK: - Boundary phonemes

    private static func sounds(_ ipa: String?) -> [Character] {
        guard let ipa else { return [] }
        return ipa.filter { !"ˈˌːˑ./ ".contains($0) }
    }

    static func lastSound(_ ipa: String?) -> Character? { sounds(ipa).last }
    static func firstSound(_ ipa: String?) -> Character? { sounds(ipa).first }
}
