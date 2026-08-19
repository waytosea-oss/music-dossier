import Foundation
import SQLite3

private func sqliteTransientDestructor() -> sqlite3_destructor_type {
    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

public final class CacheStore: @unchecked Sendable {
    private let fileManager: FileManager
    public let rootURL: URL
    public let htmlDirectoryURL: URL
    public let artworkDirectoryURL: URL
    public let visualsDirectoryURL: URL
    private let databaseURL: URL
    private var database: OpaquePointer?

    public init(rootURL: URL, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.rootURL = rootURL
        self.htmlDirectoryURL = rootURL.appendingDirectory("html")
        self.artworkDirectoryURL = rootURL.appendingDirectory("artwork")
        self.visualsDirectoryURL = rootURL.appendingDirectory("visuals")
        self.databaseURL = rootURL.appendingFile("cache.sqlite3")

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: htmlDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: artworkDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: visualsDirectoryURL, withIntermediateDirectories: true)

        var database: OpaquePointer?
        if sqlite3_open(databaseURL.path, &database) != SQLITE_OK {
            let message = Self.lastSQLiteError(database)
            if let database {
                sqlite3_close(database)
            }
            throw MusicDossierError.cacheFailure(message)
        }

        self.database = database
        try Self.createTables(in: database)
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    public func loadLatestDossier(for trackKey: String) throws -> CachedDossier? {
        let query = """
        SELECT json_blob, html_path, updated_at, expires_at
        FROM dossier_cache
        WHERE track_key = ?
        LIMIT 1;
        """

        guard let statement = try prepare(query) else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, trackKey, -1, sqliteTransientDestructor())

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        let jsonBlob = try readColumnBlob(statement, index: 0)
        let htmlPath = try readColumnText(statement, index: 1)
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
        let expiresAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
        let dossier = try JSONCoding.makeDecoder().decode(ResearchDossier.self, from: jsonBlob)
        let htmlURL = URL(fileURLWithPath: htmlPath)

        // The live app re-renders from cached JSON on every load, so avoid
        // pulling potentially multi-megabyte HTML blobs into memory during
        // track polling.
        return CachedDossier(dossier: dossier, html: "", htmlURL: htmlURL, updatedAt: updatedAt, expiresAt: expiresAt)
    }

    public func isDossierFresh(_ cached: CachedDossier, maxAge: TimeInterval, now: Date = .now) -> Bool {
        min(cached.expiresAt, cached.updatedAt.addingTimeInterval(maxAge)) > now
    }

    /// 只更新 JSON（例如展示时补齐了图片缓存），不动 html/过期时间。
    public func updateDossierJSON(_ dossier: ResearchDossier, trackKey: String) throws {
        let query = "UPDATE dossier_cache SET json_blob = ? WHERE track_key = ?;"
        guard let statement = try prepare(query) else {
            throw MusicDossierError.cacheFailure("无法创建 dossier_cache 更新语句")
        }
        defer { sqlite3_finalize(statement) }
        let json = try JSONCoding.makeEncoder().encode(dossier)
        _ = json.withUnsafeBytes { rawBuffer in
            sqlite3_bind_blob(statement, 1, rawBuffer.baseAddress, Int32(rawBuffer.count), sqliteTransientDestructor())
        }
        sqlite3_bind_text(statement, 2, trackKey, -1, sqliteTransientDestructor())
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw MusicDossierError.cacheFailure("更新 dossier_cache 失败")
        }
    }

    public func saveDossier(
        _ dossier: ResearchDossier,
        html: String,
        trackKey: String,
        maxAge: TimeInterval
    ) throws -> CachedDossier {
        let now = Date()
        let expiresAt = now.addingTimeInterval(maxAge)
        let htmlURL = htmlURL(for: trackKey)
        try html.write(to: htmlURL, atomically: true, encoding: .utf8)

        let query = """
        INSERT INTO dossier_cache(track_key, json_blob, html_path, updated_at, expires_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(track_key) DO UPDATE SET
            json_blob = excluded.json_blob,
            html_path = excluded.html_path,
            updated_at = excluded.updated_at,
            expires_at = excluded.expires_at;
        """

        guard let statement = try prepare(query) else {
            throw MusicDossierError.cacheFailure("无法创建 dossier_cache 语句")
        }
        defer { sqlite3_finalize(statement) }

        let json = try JSONCoding.makeEncoder().encode(dossier)
        sqlite3_bind_text(statement, 1, trackKey, -1, sqliteTransientDestructor())
        _ = json.withUnsafeBytes { rawBuffer in
            sqlite3_bind_blob(statement, 2, rawBuffer.baseAddress, Int32(rawBuffer.count), sqliteTransientDestructor())
        }
        sqlite3_bind_text(statement, 3, htmlURL.path, -1, sqliteTransientDestructor())
        sqlite3_bind_double(statement, 4, now.timeIntervalSince1970)
        sqlite3_bind_double(statement, 5, expiresAt.timeIntervalSince1970)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw MusicDossierError.cacheFailure(lastSQLiteError())
        }

        return CachedDossier(dossier: dossier, html: html, htmlURL: htmlURL, updatedAt: now, expiresAt: expiresAt)
    }

    public func saveArtwork(_ rawData: Data, fileExtension: String, trackKey: String) throws -> URL {
        let (data, downscaledExtension) = ImageDownscaler.downscale(rawData, maxPixel: 900)
        let resolvedExtension = ImageSniffing.detectedFileExtension(for: data) ?? downscaledExtension
        let url = artworkURL(for: trackKey, fileExtension: resolvedExtension)

        if let existing = artworkURL(for: trackKey), existing.path != url.path {
            try? fileManager.removeItem(at: existing)
        }
        try data.write(to: url, options: [.atomic])
        return url
    }

    public func artworkURL(for trackKey: String) -> URL? {
        let prefix = Hashing.sha256(trackKey)
        let contents = (try? fileManager.contentsOfDirectory(at: artworkDirectoryURL, includingPropertiesForKeys: nil)) ?? []
        guard let match = contents.first(where: { $0.deletingPathExtension().lastPathComponent == prefix }) else {
            return nil
        }

        if ImageSniffing.isRenderableImage(at: match) {
            return match
        }

        try? fileManager.removeItem(at: match)
        return nil
    }

    public func htmlURL(for trackKey: String) -> URL {
        htmlDirectoryURL.appendingFile("\(Hashing.sha256(trackKey)).html")
    }

    public func artworkURL(for trackKey: String, fileExtension: String) -> URL {
        artworkDirectoryURL.appendingFile("\(Hashing.sha256(trackKey)).\(fileExtension)")
    }

    public func saveVisualAsset(
        _ rawData: Data,
        trackKey: String,
        remoteURL: String,
        fileExtension: String? = nil
    ) throws -> String {
        let (data, downscaledExtension) = ImageDownscaler.downscale(rawData, maxPixel: 1200)
        let resolvedExtension = ImageSniffing.detectedFileExtension(for: data) ?? downscaledExtension
        let fileName = visualFileName(trackKey: trackKey, remoteURL: remoteURL, fileExtension: resolvedExtension)
        let url = visualsDirectoryURL.appendingFile(fileName)
        try data.write(to: url, options: [.atomic])
        return fileName
    }

    // MARK: - 存储清理

    public struct PruneReport: Sendable {
        public let removedFiles: Int
        public let removedBytes: Int64
        public let removedEntries: Int
        public let totalBytesAfter: Int64
    }

    /// 清理：① 删掉没有任何缓存条目引用的图片/HTML；② 删掉旧版残留的超大 HTML（内嵌 base64）；
    /// ③ 总量仍超过上限时，按更新时间从旧到新删除整条记录及其文件，直到低于上限。
    @discardableResult
    public func pruneStorage(maxTotalBytes: Int64) throws -> PruneReport {
        var removedFiles = 0
        var removedBytes: Int64 = 0
        var removedEntries = 0

        // 读出所有条目
        struct Entry { let trackKey: String; let updatedAt: Double; let htmlPath: String; let dossier: ResearchDossier? }
        var entries: [Entry] = []
        if let statement = try prepare("SELECT track_key, updated_at, html_path, json_blob FROM dossier_cache;") {
            defer { sqlite3_finalize(statement) }
            while sqlite3_step(statement) == SQLITE_ROW {
                let key = (try? readColumnText(statement, index: 0)) ?? ""
                let updated = sqlite3_column_double(statement, 1)
                let html = (try? readColumnText(statement, index: 2)) ?? ""
                let blob = (try? readColumnBlob(statement, index: 3)) ?? Data()
                let dossier = try? JSONCoding.makeDecoder().decode(ResearchDossier.self, from: blob)
                entries.append(Entry(trackKey: key, updatedAt: updated, htmlPath: html, dossier: dossier))
            }
        }

        func referencedFiles(_ dossier: ResearchDossier?) -> Set<String> {
            guard let dossier else { return [] }
            var set = Set<String>()
            for v in dossier.visuals { if let f = v.cachedFileName { set.insert(f) } }
            for c in dossier.creators { if let f = c.imageFileName { set.insert(f) } }
            for r in dossier.relatedWorks { if let f = r.artworkFileName { set.insert(f) } }
            return set
        }

        var referencedVisuals = Set<String>()
        var referencedArtworkStems = Set<String>()
        var referencedHTML = Set<String>()
        for entry in entries {
            referencedVisuals.formUnion(referencedFiles(entry.dossier))
            referencedArtworkStems.insert(Hashing.sha256(entry.trackKey))
            referencedHTML.insert(URL(fileURLWithPath: entry.htmlPath).lastPathComponent)
        }

        func remove(_ url: URL) {
            let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            if (try? fileManager.removeItem(at: url)) != nil {
                removedFiles += 1
                removedBytes += size
            }
        }
        func files(in directory: URL) -> [URL] {
            (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        }
        func size(of url: URL) -> Int64 {
            (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        }

        // ① 孤儿文件 + ② 超大 HTML（顺便把早期存下的大图就地压小）
        for url in files(in: visualsDirectoryURL) {
            if !referencedVisuals.contains(url.lastPathComponent) {
                remove(url)
            } else if size(of: url) > 1_500_000, let data = try? Data(contentsOf: url) {
                let (small, _) = ImageDownscaler.downscale(data, maxPixel: 1200)
                if small.count < data.count {
                    try? small.write(to: url, options: [.atomic])
                    removedBytes += Int64(data.count - small.count)
                }
            }
        }
        for url in files(in: artworkDirectoryURL) where referencedArtworkStems.contains(url.deletingPathExtension().lastPathComponent) && size(of: url) > 1_000_000 {
            if let data = try? Data(contentsOf: url) {
                let (small, _) = ImageDownscaler.downscale(data, maxPixel: 900)
                if small.count < data.count { try? small.write(to: url, options: [.atomic]); removedBytes += Int64(data.count - small.count) }
            }
        }
        for url in files(in: artworkDirectoryURL) where !referencedArtworkStems.contains(url.deletingPathExtension().lastPathComponent) {
            remove(url)
        }
        for url in files(in: htmlDirectoryURL) {
            if !referencedHTML.contains(url.lastPathComponent) || size(of: url) > 400_000 {
                remove(url)
            }
        }

        // ③ 总量上限
        func totalBytes() -> Int64 {
            [visualsDirectoryURL, artworkDirectoryURL, htmlDirectoryURL]
                .flatMap { files(in: $0) }
                .reduce(Int64(0)) { $0 + size(of: $1) }
        }
        var total = totalBytes()
        if total > maxTotalBytes {
            let oldestFirst = entries.sorted { $0.updatedAt < $1.updatedAt }
            for entry in oldestFirst where total > maxTotalBytes {
                for name in referencedFiles(entry.dossier) {
                    let url = visualsDirectoryURL.appendingFile(name)
                    if fileManager.fileExists(atPath: url.path) { remove(url) }
                }
                if let art = artworkURL(for: entry.trackKey) { remove(art) }
                let html = URL(fileURLWithPath: entry.htmlPath)
                if fileManager.fileExists(atPath: html.path) { remove(html) }
                if let statement = try prepare("DELETE FROM dossier_cache WHERE track_key = ?;") {
                    sqlite3_bind_text(statement, 1, entry.trackKey, -1, sqliteTransientDestructor())
                    _ = sqlite3_step(statement)
                    sqlite3_finalize(statement)
                    removedEntries += 1
                }
                total = totalBytes()
            }
        }

        return PruneReport(removedFiles: removedFiles, removedBytes: removedBytes, removedEntries: removedEntries, totalBytesAfter: total)
    }

    public func visualURL(fileName: String) -> URL? {
        let url = visualsDirectoryURL.appendingFile(fileName)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        if ImageSniffing.isRenderableImage(at: url) {
            return url
        }
        try? fileManager.removeItem(at: url)
        return nil
    }

    private func visualFileName(trackKey: String, remoteURL: String, fileExtension: String) -> String {
        let trackPrefix = String(Hashing.sha256(trackKey).prefix(12))
        let remotePrefix = String(Hashing.sha256(remoteURL).prefix(12))
        return "\(trackPrefix)-\(remotePrefix).\(fileExtension)"
    }

    private static func createTables(in database: OpaquePointer?) throws {
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS dossier_cache(
                track_key TEXT PRIMARY KEY,
                json_blob BLOB NOT NULL,
                html_path TEXT NOT NULL,
                updated_at REAL NOT NULL,
                expires_at REAL NOT NULL
            );
            """,
        ]

        for statement in statements {
            guard sqlite3_exec(database, statement, nil, nil, nil) == SQLITE_OK else {
                throw MusicDossierError.cacheFailure(lastSQLiteError(database))
            }
        }
    }

    private func prepare(_ query: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            throw MusicDossierError.cacheFailure(lastSQLiteError())
        }
        return statement
    }

    private func readColumnText(_ statement: OpaquePointer?, index: Int32) throws -> String {
        guard let cString = sqlite3_column_text(statement, index) else {
            throw MusicDossierError.cacheFailure("SQLite text 列为空")
        }
        return String(cString: cString)
    }

    private func readColumnBlob(_ statement: OpaquePointer?, index: Int32) throws -> Data {
        let count = Int(sqlite3_column_bytes(statement, index))
        guard let bytes = sqlite3_column_blob(statement, index) else {
            throw MusicDossierError.cacheFailure("SQLite blob 列为空")
        }
        return Data(bytes: bytes, count: count)
    }

    private func lastSQLiteError() -> String {
        Self.lastSQLiteError(database)
    }

    private static func lastSQLiteError(_ database: OpaquePointer?) -> String {
        if let database, let cString = sqlite3_errmsg(database) {
            return String(cString: cString)
        }
        return "unknown sqlite error"
    }
}
