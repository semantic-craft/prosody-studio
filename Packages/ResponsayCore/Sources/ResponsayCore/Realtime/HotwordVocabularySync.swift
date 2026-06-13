import Foundation
import OSLog

/// Turns the local hotword list into DashScope vocabulary entries, enforcing
/// the documented rules (custom-hot-words-user-guide):
/// - non-ASCII text ≤ 15 total characters; pure-ASCII ≤ 7 space-separated parts
/// - ≤ 500 entries per vocabulary; weight 4 (the documented starting point)
/// - lang inferred per word (CJK → zh, pure ASCII → en, else omitted)
/// Pure logic — unit-testable without network.
public enum HotwordVocabularyPlanner {
    public static let maxEntries = 500

    public static func plan(_ rawHotwords: [String]) -> [DashScopeHotword] {
        var seen = Set<String>()
        var result: [DashScopeHotword] = []
        for raw in rawHotwords {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, isWithinLengthRules(text) else { continue }
            let key = text.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(DashScopeHotword(text: text, weight: 4, lang: inferLang(text)))
            if result.count >= maxEntries { break }
        }
        return result
    }

    /// Stable fingerprint of a planned vocabulary — when unchanged, the cached
    /// vocabulary_id is reused with zero network cost.
    public static func fingerprint(_ planned: [DashScopeHotword]) -> String {
        var hasher = Hasher()
        for word in planned {
            hasher.combine(word.text)
            hasher.combine(word.lang ?? "")
        }
        return String(UInt(bitPattern: hasher.finalize()), radix: 36)
    }

    static func isWithinLengthRules(_ text: String) -> Bool {
        if text.allSatisfy(\.isASCII) {
            return text.split(separator: " ").count <= 7
        }
        return text.count <= 15
    }

    static func inferLang(_ text: String) -> String? {
        let scalars = text.unicodeScalars
        if scalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }) {
            return "zh"
        }
        if text.allSatisfy(\.isASCII) { return "en" }
        return nil
    }
}

/// Keeps one remote DashScope vocabulary in sync with the local hotword list,
/// eventually-consistent so dictation start never blocks on network:
/// - fingerprint unchanged → return the cached id instantly
/// - changed → return the *old* id (or nil) now, rebuild in the background;
///   the next session picks up the new id
/// - any failure → nil (recognition simply runs without hotwords; fail-open)
/// The old vocabulary is deleted after a successful create (10-per-account
/// quota); on create failure it retries once after sweeping same-prefix
/// leftovers so a stale quota can self-heal.
public actor HotwordVocabularySync {
    public static let targetModel = "fun-asr-realtime"
    public static let prefix = "rsay"
    private static let cacheKey = "dashscope.vocabulary.cache"  // "fingerprint|id"

    private let client: DashScopeVocabularyClient
    private let defaults: UserDefaults
    private let log = Logger(subsystem: "com.semanticcraft.responsay", category: "hotword-vocab")
    private var rebuildTask: Task<Void, Never>?

    public init(client: DashScopeVocabularyClient, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
    }

    /// Non-blocking resolve: instant answer from cache, background reconcile.
    public func currentVocabularyID(for rawHotwords: [String]) -> String? {
        let planned = HotwordVocabularyPlanner.plan(rawHotwords)
        guard !planned.isEmpty else { return nil }
        let fingerprint = HotwordVocabularyPlanner.fingerprint(planned)
        let cached = readCache()
        if cached?.fingerprint == fingerprint { return cached?.id }
        scheduleRebuild(planned: planned, fingerprint: fingerprint, replacing: cached?.id)
        return cached?.id  // stale id still helps this session; nil on first run
    }

    private func scheduleRebuild(planned: [DashScopeHotword], fingerprint: String, replacing oldID: String?) {
        guard rebuildTask == nil else { return }
        rebuildTask = Task { [weak self] in
            await self?.rebuild(planned: planned, fingerprint: fingerprint, replacing: oldID)
            await self?.clearRebuildTask()
        }
    }

    private func clearRebuildTask() { rebuildTask = nil }

    private func rebuild(planned: [DashScopeHotword], fingerprint: String, replacing oldID: String?) async {
        do {
            let id = try await createWithQuotaRecovery(planned)
            writeCache(fingerprint: fingerprint, id: id)
            if let oldID, oldID != id {
                try? await client.deleteVocabulary(id: oldID)
            }
            log.info("hotword vocabulary synced: \(planned.count, privacy: .public) entries")
        } catch {
            log.warning("hotword vocabulary sync failed (recognition continues without): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func createWithQuotaRecovery(_ planned: [DashScopeHotword]) async throws -> String {
        do {
            return try await client.createVocabulary(
                targetModel: Self.targetModel, prefix: Self.prefix, vocabulary: planned)
        } catch {
            // Possibly the 10-vocabulary quota — sweep our own leftovers, retry once.
            let leftovers = (try? await client.listVocabularyIDs(prefix: Self.prefix)) ?? []
            for id in leftovers { try? await client.deleteVocabulary(id: id) }
            return try await client.createVocabulary(
                targetModel: Self.targetModel, prefix: Self.prefix, vocabulary: planned)
        }
    }

    // MARK: cache

    private func readCache() -> (fingerprint: String, id: String)? {
        guard let raw = defaults.string(forKey: Self.cacheKey) else { return nil }
        let parts = raw.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    private func writeCache(fingerprint: String, id: String) {
        defaults.set("\(fingerprint)|\(id)", forKey: Self.cacheKey)
    }
}
