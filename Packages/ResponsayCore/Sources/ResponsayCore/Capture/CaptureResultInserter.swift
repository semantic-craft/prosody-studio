import Foundation

@MainActor
public enum CaptureResultInserter {
    @discardableResult
    public static func insertIfNeeded(
        _ result: CaptureResult,
        using inserter: TextInserter
    ) async throws -> Bool {
        try result.validate()

        switch result.insertPolicy {
        case .insertImmediately, .replaceSelection:
            guard let text = result.insertText else { return false }
            let correctedText = TextCorrectionRules.apply(to: text)
            try await inserter.insert(correctedText)
            return true
        case .copyOnly, .noInsert:
            return false
        }
    }
}
