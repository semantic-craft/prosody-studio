import Foundation

/// OpenAI `response_format` (json_schema) contracts for the App-direct path — the Swift mirror of
/// backend `coach_schemas.mjs`. Only sent to LOCAL endpoints (Ollama): a small local model needs
/// the schema to emit valid JSON, while several cloud providers 400 on json_schema, so the cloud
/// path relies on the prompt + tolerant parsing (`LLMChatRequestBuilder` gates this on
/// `endpoint.isLocal`, matching the backend which sent it only for Ollama).
enum LLMResponseFormat {
    private static var string: [String: Any] { ["type": "string"] }
    private static var stringArray: [String: Any] { ["type": "array", "items": ["type": "string"]] }

    private static func schema(_ name: String, _ properties: [String: Any]) -> [String: Any] {
        [
            "type": "json_schema",
            "json_schema": [
                "name": name,
                "strict": true,
                "schema": [
                    "type": "object",
                    "properties": properties,
                    "required": Array(properties.keys),
                    "additionalProperties": false,
                ],
            ],
        ]
    }

    /// 重改写 / 轻改写 → {text, changes}
    static var textChanges: [String: Any] { schema("rewrite_result", ["text": string, "changes": stringArray]) }
    /// 翻译 → {text, notes}
    static var textNotes: [String: Any] { schema("translate_result", ["text": string, "notes": stringArray]) }
    /// express → {idiomatic, alternatives, reasons, thinkingShift}
    static var express: [String: Any] {
        schema("express_coaching", [
            "idiomatic": string, "alternatives": stringArray, "reasons": stringArray, "thinkingShift": string,
        ])
    }
}
