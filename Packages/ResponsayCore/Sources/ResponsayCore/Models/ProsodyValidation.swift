import Foundation

/// Validate / repair / normalize the canonical `ProsodyAnalysis` (issue 143).
/// Prosody is a **rendering** job: the LLM emits candidate JSON, we validate the
/// shape, repair what we safely can, and normalize toward everyday English
/// before the stave renderer consumes it. The schema itself (ARCHITECTURE §4) is
/// never redesigned here.
public enum ProsodyValidationError: Error, Equatable {
    case emptyThoughtGroups
    case wordOrderMismatch(expected: [String], got: [String])
    case noNuclear
    case emptySyllables(word: String)
    case stressIndexOutOfBounds(word: String, stressIndex: Int, syllableCount: Int)
    case stressedWithoutStressIndex(word: String)
}

public enum ProsodyValidator {
    /// Words that should not normally carry stress in everyday English.
    static let functionWords: Set<String> = [
        "the", "a", "an", "to", "of", "and", "or", "is", "are", "am", "was", "were",
        "in", "on", "for", "do", "does", "you", "i", "it", "this", "that", "by",
        "at", "be", "as", "with", "but", "so", "if", "we", "he", "she", "they",
    ]

    // MARK: - Validate

    /// Throws when the analysis is structurally unusable for rendering.
    public static func validateProsody(_ analysis: ProsodyAnalysis) throws {
        guard !analysis.thoughtGroups.isEmpty else { throw ProsodyValidationError.emptyThoughtGroups }
        let prosodyWords = analysis.thoughtGroups.flatMap(\.words)
        let words = prosodyWords.map(\.text)
        guard !words.isEmpty else { throw ProsodyValidationError.emptyThoughtGroups }

        let expected = tokenize(analysis.text)
        if normalized(words) != normalized(expected) {
            throw ProsodyValidationError.wordOrderMismatch(expected: expected, got: words)
        }
        try prosodyWords.forEach(validateSyllableStressShape)
        let hasNuclear = analysis.thoughtGroups.contains { $0.words.contains(where: \.nuclear) }
        guard hasNuclear else { throw ProsodyValidationError.noNuclear }
    }

    // MARK: - Repair

    /// Fix what is safe: make `text` authoritative from the word stream (so
    /// word-order/text mismatch becomes consistent) and guarantee one nuclear.
    /// Throws only when there is nothing to render (no thought groups / words).
    public static func repairProsodyShape(_ analysis: ProsodyAnalysis) throws -> ProsodyAnalysis {
        guard !analysis.thoughtGroups.isEmpty else { throw ProsodyValidationError.emptyThoughtGroups }
        let words = analysis.thoughtGroups.flatMap { $0.words.map(\.text) }
        guard !words.isEmpty else { throw ProsodyValidationError.emptyThoughtGroups }

        var groups = analysis.thoughtGroups.map { group in
            ThoughtGroup(tone: group.tone, words: group.words.map(repairSyllableStressShape))
        }
        // Guarantee a nuclear: if none anywhere, mark the last word of the last group.
        if !groups.contains(where: { $0.words.contains(where: \.nuclear) }) {
            let lastIndex = groups.count - 1
            var last = groups[lastIndex]
            if let wordIndex = last.words.indices.last {
                var w = last.words
                w[wordIndex] = repairSyllableStressShape(
                    w[wordIndex].updating(stressed: true, nuclear: true)
                )
                last = ThoughtGroup(tone: last.tone, words: w)
                groups[lastIndex] = last
            }
        }

        let rebuiltText = words.joined(separator: " ")
        return ProsodyAnalysis(
            text: rebuiltText,
            isGeneratedExample: analysis.isGeneratedExample,
            sourceWord: analysis.sourceWord,
            ipa: analysis.ipa,
            thoughtGroups: groups,
            notes: analysis.notes
        )
    }

    // MARK: - Normalize

    /// Everyday-English normalization: thin out over-stressing (function words
    /// first, then shortest), and collapse to exactly one nuclear per group
    /// (the last stressed word).
    public static func normalizeProsodyForEverydayEnglish(_ analysis: ProsodyAnalysis) -> ProsodyAnalysis {
        let groups = analysis.thoughtGroups.map(normalizeGroup)
        return ProsodyAnalysis(
            text: analysis.text,
            isGeneratedExample: analysis.isGeneratedExample,
            sourceWord: analysis.sourceWord,
            ipa: analysis.ipa,
            thoughtGroups: groups,
            notes: analysis.notes
        )
    }

    private static func normalizeGroup(_ group: ThoughtGroup) -> ThoughtGroup {
        var words = group.words
        let cap = max(1, Int(ceil(Double(words.count) / 2.0)))   // stress-sparse: ≤ half

        // 1. Exactly one nuclear = last stressed word (or last word if none stressed),
        //    chosen BEFORE thinning so it is protected from being unstressed.
        let nucleusIndex = words.lastIndex(where: \.stressed) ?? words.indices.last
        words = words.indices.map { index in words[index].updating(nuclear: index == nucleusIndex) }
        if let nucleusIndex { words[nucleusIndex] = words[nucleusIndex].updating(stressed: true, nuclear: true) }

        // 2. Unstress non-nuclear function words.
        words = words.map { word in
            (word.stressed && !word.nuclear && functionWords.contains(word.text.lowercased()))
                ? word.updating(stressed: false)
                : word
        }
        // 3. Still over the cap → drop stress from shortest non-nuclear stressed words.
        while words.filter(\.stressed).count > cap {
            guard let index = words.indices
                .filter({ words[$0].stressed && !words[$0].nuclear })
                .min(by: { words[$0].text.count < words[$1].text.count })
            else { break }
            words[index] = words[index].updating(stressed: false)
        }
        words = words.map(repairSyllableStressShape)
        return ThoughtGroup(tone: group.tone, words: words)
    }

    // MARK: - Helpers

    private static func validateSyllableStressShape(_ word: Word) throws {
        let syllables = nonEmptyTrimmedSyllables(word)
        guard !syllables.isEmpty, syllables.count == word.syllables.count else {
            throw ProsodyValidationError.emptySyllables(word: word.text)
        }
        if let stressIndex = word.stressIndex {
            guard syllables.indices.contains(stressIndex) else {
                throw ProsodyValidationError.stressIndexOutOfBounds(
                    word: word.text,
                    stressIndex: stressIndex,
                    syllableCount: syllables.count
                )
            }
        } else if word.stressed {
            throw ProsodyValidationError.stressedWithoutStressIndex(word: word.text)
        }
    }

    private static func repairSyllableStressShape(_ word: Word) -> Word {
        let syllables = repairedSyllables(for: word)
        let stressIndex = repairedStressIndex(for: word, syllableCount: syllables.count)
        return word.updatingSyllableStress(syllables: syllables, stressIndex: stressIndex)
    }

    private static func repairedSyllables(for word: Word) -> [String] {
        let syllables = nonEmptyTrimmedSyllables(word)
        if !syllables.isEmpty { return syllables }

        let fallback = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return [fallback.isEmpty ? word.text : fallback]
    }

    private static func repairedStressIndex(for word: Word, syllableCount: Int) -> Int? {
        guard syllableCount > 0 else { return nil }
        if let stressIndex = word.stressIndex {
            return min(max(stressIndex, 0), syllableCount - 1)
        }
        return word.stressed ? 0 : nil
    }

    private static func nonEmptyTrimmedSyllables(_ word: Word) -> [String] {
        word.syllables
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func normalized(_ words: [String]) -> [String] {
        words.map { word in
            String(word.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        }.filter { !$0.isEmpty }
    }
}

extension Word {
    /// Copy with selected fields changed (id is regenerated — it is render identity only).
    func updating(stressed: Bool? = nil, nuclear: Bool? = nil) -> Word {
        Word(
            text: text,
            syllables: syllables,
            stressIndex: stressIndex,
            stressed: stressed ?? self.stressed,
            nuclear: nuclear ?? self.nuclear,
            ipa: ipa,
            linkToNext: linkToNext
        )
    }

    /// Copy with validated syllable/stress shape changed (id is regenerated).
    func updatingSyllableStress(syllables: [String], stressIndex: Int?) -> Word {
        Word(
            text: text,
            syllables: syllables,
            stressIndex: stressIndex,
            stressed: stressed,
            nuclear: nuclear,
            ipa: ipa,
            linkToNext: linkToNext
        )
    }
}
