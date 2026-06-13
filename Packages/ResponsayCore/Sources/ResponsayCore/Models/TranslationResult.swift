import Foundation

public enum TranslationTargetLanguage: String, CaseIterable, Identifiable, Sendable {
    case englishUS = "en-US"
    case german = "de-DE"
    case japanese = "ja-JP"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .englishUS: "英语（美国）"
        case .german: "德语"
        case .japanese: "日语"
        }
    }

    public var promptName: String {
        switch self {
        case .englishUS: "American English"
        case .german: "German"
        case .japanese: "Japanese"
        }
    }
}

public struct TranslationResult: Codable, Sendable, Equatable {
    public let text: String
    public let original: String
    public let targetLanguage: String
    public let notes: [String]

    public init(
        text: String,
        original: String,
        targetLanguage: String,
        notes: [String] = []
    ) {
        self.text = text
        self.original = original
        self.targetLanguage = targetLanguage
        self.notes = notes
    }
}
