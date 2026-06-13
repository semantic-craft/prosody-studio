import Foundation

public struct PitchContour: Codable, Sendable, Equatable {
    public let points: [Double]

    public init(points: [Double]) {
        self.points = points.filter { $0.isFinite }
    }
}
