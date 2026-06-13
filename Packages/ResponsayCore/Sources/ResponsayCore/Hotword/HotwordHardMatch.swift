import Foundation

/// One spelling repair the enforcer made: the surface text it found (`from`)
/// and the canonical hotword spelling it swapped in (`to`).
public struct HotwordReplacement: Sendable, Equatable {
    public let from: String
    public let to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

/// The result of a hard-match pass: the (possibly rewritten) transcript plus the
/// list of replacements applied, left-to-right. `replacements` is empty for a no-op.
public struct HotwordEnforcement: Sendable, Equatable {
    public let text: String
    public let replacements: [HotwordReplacement]

    public init(text: String, replacements: [HotwordReplacement]) {
        self.text = text
        self.replacements = replacements
    }
}

/// Hotword **hard-match enforcement** (ADR-0011) — the app-side Swift port of the
/// retired backend `hotword_match.mjs`, restored after the Node backend was
/// deleted (ADR-0029) so the Mac app stops shipping weak hints only.
///
/// A conservative, anchor-required post-pass over an ASR transcript: when the text
/// already contains a token (or short run of tokens) that is a near-miss of a domain
/// hotword, the span is rewritten to the hotword's exact spelling. It **never inserts**
/// a term that was not spoken — it only repairs the spelling of something already there
/// — so the faithful transcript (ADR-0008) is preserved. Idempotent; a no-op on empty
/// input or an empty hotword list.
public enum HotwordHardMatch {
    /// Widest token run a single hotword may span. Caps the acronym/space-split
    /// window so a long sentence never fans out into huge candidate windows.
    private static let maxWindowTokens = 12

    /// Rewrite near-miss spans of `text` to the exact spelling of any matching `hotword`.
    public static func enforce(_ text: String, hotwords: [String]) -> HotwordEnforcement {
        let terms = prepareHotwords(hotwords)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !terms.isEmpty else {
            return HotwordEnforcement(text: text, replacements: [])
        }

        let tokens = tokenize(text)
        let longestKey = terms.reduce(1) { max($0, $1.key.count) }
        let maxWindow = min(maxWindowTokens, longestKey)

        let candidates = collectCandidates(in: text, tokens: tokens, terms: terms, maxWindow: maxWindow)
        let chosen = resolveOverlaps(candidates)
        guard !chosen.isEmpty else {
            return HotwordEnforcement(text: text, replacements: [])
        }
        return applyReplacements(to: text, chosen: chosen)
    }

    // MARK: - Hotword preparation

    /// A hotword reduced to its canonical spelling plus the normalized comparison key.
    private struct Term {
        let spelling: String
        let key: String
    }

    /// De-duplicate by normalized key, dropping blanks; preserves first-seen spelling.
    private static func prepareHotwords(_ hotwords: [String]) -> [Term] {
        var seen = Set<String>()
        var terms: [Term] = []
        for raw in hotwords {
            let spelling = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizeKey(spelling)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            terms.append(Term(spelling: spelling, key: key))
        }
        return terms
    }

    /// Lowercase + strip everything but ASCII `[a-z0-9]` — the comparison space in
    /// which "C L S C I", "clsci", and "CLSCI" all collapse to the same key.
    private static func normalizeKey(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.count)
        for character in value {
            guard let ascii = character.asciiValue else { continue }
            switch ascii {
            case 48...57, 97...122:                       // 0-9, a-z
                out.unicodeScalars.append(UnicodeScalar(ascii))
            case 65...90:                                  // A-Z → lower
                out.unicodeScalars.append(UnicodeScalar(ascii + 32))
            default:
                continue
            }
        }
        return out
    }

    // MARK: - Tokenization

    /// A maximal ASCII-alphanumeric run, with its range in the original string.
    private struct Token {
        let range: Range<String.Index>
    }

    /// Maximal `[A-Za-z0-9]+` runs — the same token shape the backend regex used.
    /// CJK and other non-ASCII characters are not token characters, so a Latin term
    /// embedded in Chinese tokenizes cleanly without disturbing the surrounding text.
    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index].isASCIIAlphanumeric else {
                index = text.index(after: index)
                continue
            }
            let start = index
            var end = index
            while end < text.endIndex, text[end].isASCIIAlphanumeric {
                end = text.index(after: end)
            }
            tokens.append(Token(range: start..<end))
            index = end
        }
        return tokens
    }

    // MARK: - Candidate collection

    /// A window may only join adjacent tokens separated by ≤3 spacing/dot/underscore/
    /// hyphen characters (how an ASR splits an acronym or hyphenated term), never
    /// across other characters.
    private static func isJoinableGap(_ gap: Substring) -> Bool {
        guard gap.count <= 3 else { return false }
        return gap.allSatisfy { $0.isWhitespace || $0 == "." || $0 == "_" || $0 == "-" }
    }

    private struct Candidate {
        let range: Range<String.Index>
        let from: String
        let to: String
        let windowLen: Int
        let dist: Int
    }

    private static func collectCandidates(
        in text: String,
        tokens: [Token],
        terms: [Term],
        maxWindow: Int
    ) -> [Candidate] {
        var candidates: [Candidate] = []
        for i in tokens.indices {
            var length = 1
            while length <= maxWindow, i + length <= tokens.count {
                if length > 1 {
                    let previous = tokens[i + length - 2]
                    let current = tokens[i + length - 1]
                    if !isJoinableGap(text[previous.range.upperBound..<current.range.lowerBound]) {
                        break
                    }
                }
                let start = tokens[i].range.lowerBound
                let end = tokens[i + length - 1].range.upperBound
                let surface = String(text[start..<end])
                let windowKey = normalizeKey(surface)
                if !windowKey.isEmpty,
                   let match = matchTerm(windowKey, terms: terms),
                   surface != match.term.spelling {
                    candidates.append(Candidate(
                        range: start..<end,
                        from: surface,
                        to: match.term.spelling,
                        windowLen: length,
                        dist: match.dist
                    ))
                }
                length += 1
            }
        }
        return candidates
    }

    // MARK: - Near-miss matching

    /// An exact normalized hit always wins; otherwise the closest hotword within a
    /// length-tiered edit-distance budget. Short hotwords demand an exact match
    /// (budget 0) so common words are never clobbered.
    private static func matchTerm(_ windowKey: String, terms: [Term]) -> (term: Term, dist: Int)? {
        var best: (term: Term, dist: Int)?
        for term in terms {
            if term.key == windowKey { return (term, 0) }
            let budget = maxDistance(forLength: term.key.count)
            if budget == 0 || abs(term.key.count - windowKey.count) > budget { continue }
            let dist = levenshtein(windowKey, term.key)
            if dist <= budget, best == nil || dist < best!.dist {
                best = (term, dist)
            }
        }
        return best
    }

    private static func maxDistance(forLength length: Int) -> Int {
        switch length {
        case ...4: return 0
        case ...8: return 1
        case ...12: return 2
        default: return 3
        }
    }

    /// Classic two-row Levenshtein over the normalized (ASCII) keys.
    private static func levenshtein(_ a: String, _ b: String) -> Int {
        if a == b { return 0 }
        let aChars = Array(a)
        let bChars = Array(b)
        var row = Array(0...bChars.count)
        for i in 1...max(aChars.count, 1) where !aChars.isEmpty {
            var previous = row[0]
            row[0] = i
            for j in 1...bChars.count {
                let temp = row[j]
                row[j] = aChars[i - 1] == bChars[j - 1]
                    ? previous
                    : Swift.min(previous + 1, row[j] + 1, row[j - 1] + 1)
                previous = temp
            }
        }
        return row[bChars.count]
    }

    // MARK: - Overlap resolution + application

    /// Prefer exact over fuzzy, then longer windows, then leftmost; drop overlaps.
    private static func resolveOverlaps(_ candidates: [Candidate]) -> [Candidate] {
        let ranked = candidates.sorted { lhs, rhs in
            if lhs.dist != rhs.dist { return lhs.dist < rhs.dist }
            if lhs.windowLen != rhs.windowLen { return lhs.windowLen > rhs.windowLen }
            return lhs.range.lowerBound < rhs.range.lowerBound
        }
        var chosen: [Candidate] = []
        for candidate in ranked {
            let overlaps = chosen.contains { existing in
                candidate.range.lowerBound < existing.range.upperBound
                    && existing.range.lowerBound < candidate.range.upperBound
            }
            if !overlaps { chosen.append(candidate) }
        }
        return chosen.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    private static func applyReplacements(to text: String, chosen: [Candidate]) -> HotwordEnforcement {
        var output = ""
        var cursor = text.startIndex
        var replacements: [HotwordReplacement] = []
        for candidate in chosen {
            output += text[cursor..<candidate.range.lowerBound]
            output += candidate.to
            cursor = candidate.range.upperBound
            replacements.append(HotwordReplacement(from: candidate.from, to: candidate.to))
        }
        output += text[cursor...]
        return HotwordEnforcement(text: output, replacements: replacements)
    }
}

private extension Character {
    /// Matches the backend's `[A-Za-z0-9]` token class — ASCII letters/digits only.
    var isASCIIAlphanumeric: Bool {
        guard let ascii = asciiValue else { return false }
        return (ascii >= 48 && ascii <= 57)
            || (ascii >= 65 && ascii <= 90)
            || (ascii >= 97 && ascii <= 122)
    }
}
