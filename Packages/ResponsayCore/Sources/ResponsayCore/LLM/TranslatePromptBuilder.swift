import Foundation

/// Swift port of backend `buildTranslatePrompt` (划词翻译). App-direct path (241, epic 238):
/// meaning-first translation of selected text, no coaching. Faithful to `backend/prompts.mjs`.
enum TranslatePromptBuilder {
    static func build(text: String, target: TranslationTargetLanguage) -> (system: String, user: String) {
        let name = target.promptName
        let system = [
            "Role:\nYou are a precise meaning-first translator for short selected text.",
            [
                "Task:",
                "Translate the user's selected text into \(name).",
                "Preserve meaning, names, citations, code terms, product names, deadlines, and numbers.",
                "Translate only — render the meaning in the target language and stay within what translation naturally requires.",
                "If the source is already in the target language, lightly clean only obvious punctuation or grammar errors.",
            ].joined(separator: "\n"),
            [
                "Output format:",
                "Return exactly one JSON object as raw text (no markdown fences) with this exact shape: {\"text\": string, \"notes\": string[]}.",
                "\"text\": the translation, plain text only.",
                "\"notes\": 0-3 short Simplified Chinese notes only for concrete preservation choices; use an empty array by default.",
            ].joined(separator: "\n"),
        ].joined(separator: "\n\n")

        let user = [
            "Target language: \(target.rawValue) (\(name))",
            "",
            "Selected text:",
            text,
        ].joined(separator: "\n")
        return (system, user)
    }
}
