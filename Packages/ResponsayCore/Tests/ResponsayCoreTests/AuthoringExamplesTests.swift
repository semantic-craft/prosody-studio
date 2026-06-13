import Testing
import Foundation
@testable import ResponsayCore

/// 237 — the two AUTHORING.md example skills must stay compilable, so the published
/// author spec never drifts from the real compiler gates.
struct AuthoringExamplesTests {

    private func examplesDir() -> URL {
        // <file>.swift → ResponsayCoreTests → Tests → ResponsayCore → Packages → repo root
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("docs/legal-skill-platform/examples", isDirectory: true)
    }

    @Test func rewriteExample_compilesAsRewrite() throws {
        let md = try String(contentsOf: examplesDir().appendingPathComponent("example.rewrite.LEGAL_SKILL.md"),
                            encoding: .utf8)
        let skill = try LegalSkillCompiler().compile(md)
        #expect(skill.metadata.kind == .rewrite)
        #expect(!skill.metadata.examples.isEmpty)
    }

    @Test func generationExample_compilesAsGeneration() throws {
        let md = try String(contentsOf: examplesDir().appendingPathComponent("example.generation.LEGAL_SKILL.md"),
                            encoding: .utf8)
        let skill = try LegalSkillCompiler().compile(md)
        #expect(skill.metadata.kind == .generation)
        #expect(!skill.metadata.reasoningKernel.mandatoryMapping.isEmpty)
    }
}
