import Foundation

/// Swift port of backend `buildProsodyPrompt` (韵律分析). App-direct path (244, epic 238).
/// "Cloud-only" per ADR-0026 means a STRONG model (a small local model can't produce a valid
/// `ProsodyAnalysis`), NOT "must go through our server" — so BYOK-direct to a cloud provider
/// satisfies it. Faithful to `backend/prompts.mjs`.
enum ProsodyPromptBuilder {
    static func build(text: String) -> (system: String, user: String) {
        let system = [
            "Role:\nYou are an expert English pronunciation coach specializing in General American prosody.",
            "Task:\nAnalyze the given English text for word stress, sentence stress, intonation (rising/falling tones per thought group), rhythm, and connected-speech linking so the learner can practice it aloud.",
            [
                "Prosody rules:",
                "- Content words (nouns, main verbs, adjectives, adverbs, wh-words) are usually stressed.",
                "- Function words (articles, prepositions, auxiliaries, pronouns) are usually reduced.",
                "- Use short, natural thought groups at real speech or breath boundaries.",
                "- Each thought group has exactly one nuclear word, normally its last content word.",
                "- The nuclear word must be marked stressed.",
                "- stressIndex must be a valid index into that word's syllables array.",
                "- Use General American IPA.",
            ].joined(separator: "\n"),
            fidelityRules,
            outputUse,
            validationGate,
            schemaHint,
            exampleOutput,
        ].joined(separator: "\n\n")

        let user = ["Input: \"\(text)\".", "Task: Analyze this text. Set isGeneratedExample=false."].joined(separator: "\n")
        return (system, user)
    }

    static let schemaHint = """
    Output format:
    Return exactly one JSON object as raw text (first character "{", last character "}") with this exact shape:
    {
      "text": string,                 // the sentence analyzed
      "isGeneratedExample": boolean,
      "sourceWord"?: string,
      "ipa": string,                  // whole-sentence IPA, General American, wrapped in / /
      "thoughtGroups": [              // short, natural speech groups for shadowing practice
        { "tone": "fall"|"rise"|"fall-rise"|"rise-fall"|"level",
          "words": [
            { "text": string,
              "syllables": string[],          // e.g. ["fin","ish"]
              "stressIndex": number|null,     // index of the lexically stressed syllable; null for reduced function words
              "stressed": boolean,            // sentence prominence: true for content words, false for reduced function words
              "nuclear": boolean,             // the tonic/nuclear word of its thought group (carries the tone); must be stressed
              "ipa"?: string,
              "linkToNext"?: "liaison"|"elision"|"intrusion"|null
            }
          ]
        }
      ],
      "notes"?: string                // ONE short coaching tip
    }
    """

    static let fidelityRules = """
    Accuracy requirements:
    - Analyze exactly the words given, in their original order, keeping each word's original spelling even if it looks misspelled.
    - Each word's "syllables" must spell that word exactly when concatenated (orthographic split, e.g. "finish" -> ["fin","ish"]); keep phonetic detail in "ipa" only.
    - Set "stressIndex" to the primary-stress syllable for that word per a standard General American dictionary; use null only for reduced function words.
    - "ipa" is the whole sentence in General American IPA, wrapped in / /, using ˈ for primary and ˌ for secondary stress.
    - Base stress and intonation on standard General American usage as found in a standard dictionary.
    """

    static let validationGate = """
    SkillOpt-style validation gate:
    Before final output, internally check the candidate JSON against these gates and repair it once if any gate fails:
    - Schema gate: output is exactly one JSON object matching the requested shape, as raw text only.
    - Fidelity gate: the analyzed words exactly match the input words in order.
    - Syllable gate: concatenating every syllables array reproduces that word's spelling.
    - Prosody gate: every thought group has exactly one nuclear word, and every nuclear word is stressed.
    - Stress gate: stressed=true requires a non-null valid stressIndex; reduced function words may use null.
    - Speakability gate: notes give one concrete coaching tip a learner can apply while speaking.
    """

    static let outputUse = """
    Output use:
    The JSON drives a pronunciation-practice UI and text-to-speech shadowing flow.
    Use short, natural thought groups that a learner can repeat aloud.
    """

    static let exampleOutput = """
    Example:
    For input "I'll call you.", return exactly:
    {"text":"I'll call you.","isGeneratedExample":false,"ipa":"/aɪl ˈkɔl ju/","thoughtGroups":[{"tone":"fall","words":[{"text":"I'll","syllables":["I'll"],"stressIndex":null,"stressed":false,"nuclear":false},{"text":"call","syllables":["call"],"stressIndex":0,"stressed":true,"nuclear":true},{"text":"you","syllables":["you"],"stressIndex":null,"stressed":false,"nuclear":false}]}]}
    """
}
