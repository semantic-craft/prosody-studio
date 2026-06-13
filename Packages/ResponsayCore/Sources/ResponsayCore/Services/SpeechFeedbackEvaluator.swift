import Foundation

public enum SpeechFeedbackEvaluator {
    public static func evaluate(target: String, recognized: String) -> SpeechFeedback {
        let targetWords = words(in: target)
        let recognizedWords = words(in: recognized)
        let similarity = wordSimilarity(targetWords, recognizedWords)
        let message: String

        if recognizedWords.isEmpty {
            message = "没有识别到英文。"
        } else if similarity >= 0.9 {
            message = "识别文本很接近目标句。"
        } else if similarity >= 0.65 {
            message = "大意接近,再注意缺失或顺序不一致的词。"
        } else {
            message = "识别文本和目标句差距较大,先慢速跟读一遍。"
        }

        return SpeechFeedback(
            targetText: target,
            recognizedText: recognized,
            similarity: similarity,
            message: message)
    }

    private static func words(in text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "'" }
            .map(String.init)
    }

    private static func wordSimilarity(_ lhs: [String], _ rhs: [String]) -> Double {
        guard !lhs.isEmpty || !rhs.isEmpty else { return 1 }
        guard !lhs.isEmpty && !rhs.isEmpty else { return 0 }
        let distance = levenshtein(lhs, rhs)
        return max(0, 1 - Double(distance) / Double(max(lhs.count, rhs.count)))
    }

    private static func levenshtein(_ lhs: [String], _ rhs: [String]) -> Int {
        var previous = Array(0...rhs.count)
        var current = Array(repeating: 0, count: rhs.count + 1)

        for (leftIndex, leftWord) in lhs.enumerated() {
            current[0] = leftIndex + 1
            for (rightIndex, rightWord) in rhs.enumerated() {
                let cost = leftWord == rightWord ? 0 : 1
                current[rightIndex + 1] = min(
                    previous[rightIndex + 1] + 1,
                    current[rightIndex] + 1,
                    previous[rightIndex] + cost)
            }
            previous = current
        }
        return previous[rhs.count]
    }
}
