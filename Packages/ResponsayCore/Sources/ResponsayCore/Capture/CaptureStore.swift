import Foundation

public protocol CaptureStore: Sendable {
    func save(_ item: CaptureItem) throws
    func recent(_ limit: Int) throws -> [CaptureItem]
}

/// M1 极简实现:整本错题以 JSON 数组存单文件。
public struct FileCaptureStore: CaptureStore {
    let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    private func loadAll() throws -> [CaptureItem] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([CaptureItem].self, from: data)
    }

    public func save(_ item: CaptureItem) throws {
        var all = try loadAll()
        all.append(item)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(all)
        try data.write(to: fileURL, options: .atomic)
    }

    public func recent(_ limit: Int) throws -> [CaptureItem] {
        try loadAll().sorted { $0.createdAt > $1.createdAt }.prefix(limit).map { $0 }
    }
}

extension CaptureStore where Self == FileCaptureStore {
    /// 默认落 Application Support/Responsay/captures.json
    public static func defaultStore() -> FileCaptureStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FileCaptureStore(fileURL: base
            .appendingPathComponent(AppBrand.appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("captures.json"))
    }
}
