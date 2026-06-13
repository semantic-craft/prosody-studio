import Foundation

public struct ReviewCard: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public let sourceText: String
    public let language: String
    public let idiomatic: String
    public let reasons: [String]
    public let dueAt: Date
    public let intervalDays: Int
    public let repetitions: Int
    public let easeFactor: Double

    public var masteryStars: Int {
        MasteryStars.rating(repetitions: repetitions, easeFactor: easeFactor)
    }

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sourceText: String,
        language: String,
        idiomatic: String,
        reasons: [String],
        dueAt: Date = Date(),
        intervalDays: Int = 0,
        repetitions: Int = 0,
        easeFactor: Double = 2.5
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceText = sourceText
        self.language = language
        self.idiomatic = idiomatic
        self.reasons = reasons
        self.dueAt = dueAt
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.easeFactor = easeFactor
    }

    public init(capture: CaptureItem) {
        self.init(
            id: capture.id,
            createdAt: capture.createdAt,
            sourceText: capture.sourceText,
            language: capture.language,
            idiomatic: capture.idiomatic,
            reasons: capture.reasons,
            dueAt: capture.createdAt)
    }

    public func scheduled(
        dueAt: Date,
        intervalDays: Int,
        repetitions: Int,
        easeFactor: Double
    ) -> ReviewCard {
        ReviewCard(
            id: id,
            createdAt: createdAt,
            sourceText: sourceText,
            language: language,
            idiomatic: idiomatic,
            reasons: reasons,
            dueAt: dueAt,
            intervalDays: intervalDays,
            repetitions: repetitions,
            easeFactor: easeFactor)
    }

    public var captureItem: CaptureItem {
        CaptureItem(
            id: id,
            createdAt: createdAt,
            sourceText: sourceText,
            language: language,
            idiomatic: idiomatic,
            reasons: reasons)
    }
}
