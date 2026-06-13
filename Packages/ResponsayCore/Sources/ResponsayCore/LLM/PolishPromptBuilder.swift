import Foundation

/// Swift port of backend `buildPolishPrompt` (轻改写). App-direct path (epic 238, tracer
/// 239): the polish prompt now lives on the client so the app can call the provider straight.
/// 轻改写 = tidy the raw ASR transcript: remove fillers, add punctuation, straighten slips,
/// but do NOT rewrite or change words unnecessarily. Keep the same language.
enum PolishPromptBuilder {
    static func build(text: String) -> (system: String, user: String) {
        TextTransformPromptAssembler.build(
            action: .polish,
            text: text,
            input: .rawTranscript,
            output: .jsonTextChanges)
    }
}
