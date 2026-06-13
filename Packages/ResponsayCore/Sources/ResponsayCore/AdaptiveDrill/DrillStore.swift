import Foundation

/// Local persistence for the drill engine: the mistake corpus + each mistake's
/// SM-2 spacing and attempt history. Local-only (ADR-0006).
public protocol DrillStore: Sendable {
    /// Add or update a mistake's content. Existing `DrillProgress` is preserved.
    func upsert(_ mistake: MistakeRecord) throws
    func all() throws -> [MistakeRecord]
    /// Mistakes whose SM-2 due date has arrived, soonest first.
    func due(now: Date, limit: Int) throws -> [MistakeRecord]
    /// Record one practice outcome → advance SM-2 + bump attempt/success counts.
    func recordResult(mistakeID: UUID, correct: Bool, reviewedAt: Date) throws
    func progress(for mistakeID: UUID) throws -> DrillProgress?
    func delete(id: UUID) throws
}
