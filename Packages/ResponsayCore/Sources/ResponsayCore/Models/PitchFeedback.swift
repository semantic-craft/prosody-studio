import Foundation

public struct PitchFeedback: Codable, Sendable, Equatable {
    public let similarity: Double
    public let targetTrend: String
    public let learnerTrend: String
    public let message: String
    /// 306 — normalized (0…1) pitch curves carried through to the feedback
    /// card so the「示范 vs 你的」overlay can render. Empty when the take had
    /// no usable pitch data; older serialized payloads decode to empty.
    public let targetCurve: [Double]
    public let learnerCurve: [Double]

    public init(
        similarity: Double,
        targetTrend: String,
        learnerTrend: String,
        message: String,
        targetCurve: [Double] = [],
        learnerCurve: [Double] = []
    ) {
        self.similarity = similarity
        self.targetTrend = targetTrend
        self.learnerTrend = learnerTrend
        self.message = message
        self.targetCurve = targetCurve
        self.learnerCurve = learnerCurve
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        similarity = try c.decode(Double.self, forKey: .similarity)
        targetTrend = try c.decode(String.self, forKey: .targetTrend)
        learnerTrend = try c.decode(String.self, forKey: .learnerTrend)
        message = try c.decode(String.self, forKey: .message)
        targetCurve = try c.decodeIfPresent([Double].self, forKey: .targetCurve) ?? []
        learnerCurve = try c.decodeIfPresent([Double].self, forKey: .learnerCurve) ?? []
    }
}
