import Foundation

/// 一条"随手记/错题本"记录:你说的原话 + 地道版本 + 为什么。
public struct CaptureItem: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public let sourceText: String
    public let language: String   // CaptureLocale.rawValue, e.g. "en-US"
    public let idiomatic: String
    public let reasons: [String]

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sourceText: String,
        language: String,
        idiomatic: String,
        reasons: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceText = sourceText
        self.language = language
        self.idiomatic = idiomatic
        self.reasons = reasons
    }
}
