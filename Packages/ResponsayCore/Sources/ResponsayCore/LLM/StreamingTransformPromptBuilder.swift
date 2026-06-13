import Foundation

/// Swift port of backend `buildStreamingTransformPrompt` (流式插入 232). Unlike the JSON-enveloped
/// coach routes, the model's ENTIRE output here is streamed token-by-token straight into the
/// user's document, so it MUST be raw insertable text. App-direct streaming increment (245).
enum StreamingTransformPromptBuilder {
    static func build(mode: String, text: String, targetLanguage: String? = nil) -> (system: String, user: String) {
        let m = mode.lowercased()
        let target = TranslationTargetLanguage(rawValue: targetLanguage ?? "en-US") ?? .englishUS
        let action: TextTransformPromptAssembler.Action
        let input: TextTransformPromptAssembler.InputEnvelope
        switch m {
        case "rewrite":
            action = .rewrite(style: .tone(.natural))
            input = .selectedText
        case "translate":
            action = .translate(target: target)
            input = .selectedText
        case "express":
            action = .express
            input = .selectedText
        case "polish":
            action = .polish
            input = .rawTranscript
        default:
            action = .custom(instruction: "Tidy this text for direct insertion without changing its meaning.")
            input = .selectedText
        }
        return TextTransformPromptAssembler.build(
            action: action,
            text: text,
            input: input,
            output: .plainTextInsert)
    }
}
