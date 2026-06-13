import Foundation

public enum RepeatControllerError: LocalizedError, Equatable, Sendable {
    case emptySentences
    case invalidRange
    case sentenceNotFound(Int)

    public var errorDescription: String? {
        switch self {
        case .emptySentences:
            "没有可复读的句子。"
        case .invalidRange:
            "复读区间无效。"
        case .sentenceNotFound(let index):
            "找不到第 \(index + 1) 句。"
        }
    }
}
