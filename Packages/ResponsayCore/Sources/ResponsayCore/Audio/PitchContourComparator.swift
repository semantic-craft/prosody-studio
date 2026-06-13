import Foundation

public enum PitchContourComparator {
    public static func evaluate(target: PitchContour, learner: PitchContour) -> PitchFeedback {
        let normalizedTarget = normalize(target.points)
        let normalizedLearner = normalize(learner.points)
        guard normalizedTarget.count >= 2, normalizedLearner.count >= 2 else {
            // 306: curves stay empty here on purpose — the overlay must not
            // draw an axis for data this branch just declared unusable.
            return PitchFeedback(
                similarity: 0,
                targetTrend: trendLabel(normalizedTarget),
                learnerTrend: trendLabel(normalizedLearner),
                message: "音高数据不足,先完成一次清晰跟读。")
        }

        let distance = dtwDistance(normalizedTarget, normalizedLearner)
        let similarity = max(0, min(1, 1 - distance / Double(max(normalizedTarget.count, normalizedLearner.count))))
        let targetTrend = trendLabel(normalizedTarget)
        let learnerTrend = trendLabel(normalizedLearner)
        let message: String

        if similarity >= 0.82 {
            message = "升降调轮廓很接近。"
        } else if targetTrend == learnerTrend {
            message = "整体升降方向对了,再把重音附近的高低变化读清楚。"
        } else {
            message = "升降方向不一致,先跟着示范的高低走向慢读一遍。"
        }

        return PitchFeedback(
            similarity: similarity,
            targetTrend: targetTrend,
            learnerTrend: learnerTrend,
            message: message,
            // 306: hand the already-normalized curves through so the feedback
            // card can draw the「示范 vs 你的」overlay (previously discarded).
            targetCurve: normalizedTarget,
            learnerCurve: normalizedLearner)
    }

    public static func targetContour(from analysis: ProsodyAnalysis) -> PitchContour {
        let points = analysis.thoughtGroups.flatMap { group in
            let count = max(1, group.words.count)
            return (0..<count).map { pitch(for: group.tone, index: $0, count: count) }
        }
        return PitchContour(points: points)
    }

    private static func normalize(_ points: [Double]) -> [Double] {
        let finite = points.filter(\.isFinite)
        guard let minValue = finite.min(), let maxValue = finite.max() else { return [] }
        let span = maxValue - minValue
        guard span > 0.0001 else { return Array(repeating: 0.5, count: finite.count) }
        return finite.map { ($0 - minValue) / span }
    }

    private static func dtwDistance(_ lhs: [Double], _ rhs: [Double]) -> Double {
        var previous = Array(repeating: Double.infinity, count: rhs.count + 1)
        var current = Array(repeating: Double.infinity, count: rhs.count + 1)
        previous[0] = 0

        for left in lhs {
            current[0] = Double.infinity
            for (rightIndex, right) in rhs.enumerated() {
                let cost = abs(left - right)
                current[rightIndex + 1] = cost + min(
                    previous[rightIndex + 1],
                    current[rightIndex],
                    previous[rightIndex])
            }
            swap(&previous, &current)
        }

        return previous[rhs.count]
    }

    private static func trendLabel(_ points: [Double]) -> String {
        guard let first = points.first, let last = points.last else { return "unknown" }
        let delta = last - first
        if delta > 0.12 { return "rise" }
        if delta < -0.12 { return "fall" }
        return "level"
    }

    private static func pitch(for tone: Tone, index: Int, count: Int) -> Double {
        guard count > 1 else {
            return switch tone {
            case .rise: 0.75
            case .fall: 0.25
            case .level: 0.5
            case .fallRise, .riseFall: 0.65
            }
        }
        let progress = Double(index) / Double(count - 1)
        switch tone {
        case .fall:
            return 0.85 - progress * 0.6
        case .rise:
            return 0.25 + progress * 0.6
        case .fallRise:
            return progress < 0.5
                ? 0.85 - progress * 1.0
                : 0.35 + (progress - 0.5) * 0.9
        case .riseFall:
            return progress < 0.5
                ? 0.25 + progress * 1.0
                : 0.75 - (progress - 0.5) * 0.9
        case .level:
            return 0.5
        }
    }
}
