import Foundation
import Testing
@testable import ResponsayCore

struct RewriteEvalCorpusTests {
    private struct Sample: Decodable {
        let id: String
        let action: String
        let style: String
        let inputEnvelope: String
        let input: String
        let tags: [String]
        let constraints: [String]
        let mustPreserve: [String]
        let forbiddenOutputFragments: [String]
    }

    @Test func corpusCoversRewriteRedLines() throws {
        let samples = try Self.loadCorpus()
        #expect(samples.count >= 6)

        let tags = Set(samples.flatMap(\.tags))
        for required in [
            "same-language",
            "do-not-answer",
            "no-new-facts",
            "preserve-terms",
            "preserve-paths",
            "preserve-versions",
            "structured",
            "formal",
            "concise",
        ] {
            #expect(tags.contains(required))
        }
    }

    @Test func corpusPromptsUseRuntimeAssemblerContract() throws {
        for sample in try Self.loadCorpus() {
            let prompt = TextTransformPromptAssembler.build(
                action: .rewrite(style: .tone(try Self.tone(sample.style))),
                text: sample.input,
                input: try Self.envelope(sample.inputEnvelope),
                output: .jsonTextChanges)

            #expect(prompt.system.contains("THE SAME language"))
            #expect(prompt.system.contains("Do not add facts"))
            #expect(prompt.system.contains("Do not make a decision"))
            #expect(prompt.system.contains("{\"text\": string, \"changes\": string[]}"))
            #expect(prompt.user.contains("<\(sample.inputEnvelope)>"))
            #expect(prompt.user.contains("</\(sample.inputEnvelope)>"))
            for fragment in sample.mustPreserve where sample.input.contains(fragment) {
                #expect(prompt.user.contains(fragment))
            }
        }
    }

    @Test func corpusRequestsStayPlainChatCompletionsWithoutToolsSearchOrResponsesFields() throws {
        let endpoint = LLMEndpoint(
            providerId: "qwen",
            baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            model: "qwen-flash",
            apiKey: "sk-test")

        for sample in try Self.loadCorpus() {
            let prompt = TextTransformPromptAssembler.build(
                action: .rewrite(style: .tone(try Self.tone(sample.style))),
                text: sample.input,
                input: try Self.envelope(sample.inputEnvelope),
                output: .jsonTextChanges)
            let request = try LLMChatRequestBuilder.makeRequest(
                endpoint: endpoint,
                system: prompt.system,
                user: prompt.user,
                generationAction: .rewrite)
            let requestBody = try #require(request.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])

            #expect(request.url?.absoluteString == "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")
            #expect(body["model"] as? String == "qwen-flash")
            #expect(body["stream"] as? Bool == false)
            #expect(body["enable_thinking"] as? Bool == false)
            #expect(body["temperature"] as? Double == 0.2)
            #expect(body["top_p"] as? Double == 0.8)
            for field in ["tools", "tool_choice", "enable_search", "mcp", "input", "instructions", "modalities", "response_format"] {
                #expect(body[field] == nil)
            }

            let messages = try #require(body["messages"] as? [[String: String]])
            #expect(messages.count == 2)
            #expect(messages[0]["role"] == "system")
            #expect(messages[1]["role"] == "user")
            #expect(messages[1]["content"]?.contains("<\(sample.inputEnvelope)>") == true)
        }
    }

    private static func loadCorpus() throws -> [Sample] {
        let data = try String(contentsOf: corpusURL, encoding: .utf8)
        return try data
            .split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { line in
                try JSONDecoder().decode(Sample.self, from: Data(String(line).utf8))
            }
    }

    private static var corpusURL: URL {
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/evals/rewrite_eval_corpus.jsonl")
        if FileManager.default.fileExists(atPath: current.path) {
            return current
        }

        var fromFile = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { fromFile.deleteLastPathComponent() }
        return fromFile.appendingPathComponent("scripts/evals/rewrite_eval_corpus.jsonl")
    }

    private static func tone(_ raw: String) throws -> RewriteTone {
        guard let tone = RewriteTone(rawValue: raw) else {
            throw CorpusError.unsupportedStyle(raw)
        }
        return tone
    }

    private static func envelope(_ raw: String) throws -> TextTransformPromptAssembler.InputEnvelope {
        switch raw {
        case "selected_text": return .selectedText
        case "raw_transcript": return .rawTranscript
        default: throw CorpusError.unsupportedEnvelope(raw)
        }
    }

    private enum CorpusError: Error {
        case unsupportedStyle(String)
        case unsupportedEnvelope(String)
    }
}
