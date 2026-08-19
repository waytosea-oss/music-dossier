import Foundation

public struct AppConfiguration: Codable, Sendable {
    public let researchProvider: String?
    public let claudeModel: String?
    public let claudeExecutablePath: String?
    public let claudeEffort: String?
    public let openAIAPIKey: String?
    public let openAIModel: String
    public let openAIBaseURL: String
    public let cacheMaxAgeDays: Int
    public let cacheMaxTotalMB: Int?
    public let pollIntervalSeconds: Double
    public let enableFavoritesPrewarm: Bool?
    public let favoritesPrewarmLimit: Int?
    public let enableObsidianMirror: Bool?
    public let obsidianVaultPath: String?
    public let obsidianExportRelativePath: String?

    public static func load(fileManager: FileManager = .default) throws -> AppConfiguration {
        let env = ProcessInfo.processInfo.environment
        // 1. 先读配置文件（有就用）
        var fileConfig: AppConfiguration?
        let candidatePaths = [
            fileManager.homeDirectoryForCurrentUser
                .appendingDirectory(".config")
                .appendingDirectory("music-dossier")
                .appendingFile("config.json"),
            fileManager.homeDirectoryForCurrentUser
                .appendingDirectory("Library")
                .appendingDirectory("Application Support")
                .appendingDirectory("MusicDossier")
                .appendingFile("config.json"),
        ]
        for path in candidatePaths where fileManager.fileExists(atPath: path.path) {
            let data = try Data(contentsOf: path)
            fileConfig = try JSONCoding.makeDecoder().decode(AppConfiguration.self, from: data)
            break
        }

        // 2. 环境变量只在“显式设置”时覆盖文件；都没有才用内置默认
        func envString(_ key: String) -> String? { env[key]?.trimmedNonEmpty }
        func envInt(_ key: String) -> Int? { env[key].flatMap { Int($0) } }
        func envDouble(_ key: String) -> Double? { env[key].flatMap { Double($0) } }

        return AppConfiguration(
            researchProvider: envString("MUSIC_DOSSIER_RESEARCH_PROVIDER") ?? fileConfig?.researchProvider,
            claudeModel: envString("MUSIC_DOSSIER_CLAUDE_MODEL") ?? fileConfig?.claudeModel,
            claudeExecutablePath: envString("MUSIC_DOSSIER_CLAUDE_PATH") ?? fileConfig?.claudeExecutablePath,
            claudeEffort: envString("MUSIC_DOSSIER_CLAUDE_EFFORT") ?? fileConfig?.claudeEffort,
            openAIAPIKey: envString("OPENAI_API_KEY") ?? fileConfig?.openAIAPIKey,
            openAIModel: envString("OPENAI_MODEL") ?? fileConfig?.openAIModel ?? "gpt-5.4",
            openAIBaseURL: envString("OPENAI_RESPONSES_URL") ?? fileConfig?.openAIBaseURL ?? "https://api.openai.com/v1/responses",
            cacheMaxAgeDays: envInt("MUSIC_DOSSIER_CACHE_DAYS") ?? fileConfig?.cacheMaxAgeDays ?? 30,
            cacheMaxTotalMB: envInt("MUSIC_DOSSIER_CACHE_MAX_MB") ?? fileConfig?.cacheMaxTotalMB,
            pollIntervalSeconds: envDouble("MUSIC_DOSSIER_POLL_INTERVAL") ?? fileConfig?.pollIntervalSeconds ?? 1.5,
            enableFavoritesPrewarm: Self.parseBool(env["MUSIC_DOSSIER_FAVORITES_PREWARM"]) ?? fileConfig?.enableFavoritesPrewarm,
            favoritesPrewarmLimit: envInt("MUSIC_DOSSIER_FAVORITES_PREWARM_LIMIT") ?? fileConfig?.favoritesPrewarmLimit,
            enableObsidianMirror: Self.parseBool(env["MUSIC_DOSSIER_OBSIDIAN_MIRROR"]) ?? fileConfig?.enableObsidianMirror,
            // Obsidian 镜像是可选功能：只有配置了 obsidianVaultPath 才会写
            obsidianVaultPath: envString("MUSIC_DOSSIER_OBSIDIAN_VAULT") ?? fileConfig?.obsidianVaultPath,
            obsidianExportRelativePath: envString("MUSIC_DOSSIER_OBSIDIAN_EXPORT_PATH") ?? fileConfig?.obsidianExportRelativePath ?? "20_Music Dossier"
        )
    }

    /// 图片 + HTML 缓存总量上限，默认 300MB。
    public var resolvedCacheMaxTotalBytes: Int64 {
        Int64(max(50, cacheMaxTotalMB ?? 300)) * 1024 * 1024
    }

    public var cacheMaxAge: TimeInterval {
        TimeInterval(cacheMaxAgeDays) * 24 * 60 * 60
    }

    public var normalizedResearchProvider: String {
        researchProvider?.trimmedNonEmpty?.lowercased() ?? "auto"
    }

    public static let defaultClaudeModel = "claude-opus-4-8"

    public var resolvedClaudeModel: String {
        claudeModel?.trimmedNonEmpty ?? Self.defaultClaudeModel
    }

    public var resolvedClaudeEffort: String {
        claudeEffort?.trimmedNonEmpty?.lowercased() ?? "medium"
    }

    public var shouldMirrorToObsidian: Bool {
        enableObsidianMirror ?? true
    }

    /// 预热收藏曲目会在后台花钱跑研究，默认关闭，需在配置里显式打开。
    public var shouldPrewarmFavorites: Bool {
        enableFavoritesPrewarm ?? false
    }

    public var resolvedFavoritesPrewarmLimit: Int {
        max(0, favoritesPrewarmLimit ?? 24)
    }

    private static func parseBool(_ value: String?) -> Bool? {
        guard let normalized = value?.trimmedNonEmpty?.lowercased() else { return nil }
        switch normalized {
        case "1", "true", "yes", "y", "on":
            return true
        case "0", "false", "no", "n", "off":
            return false
        default:
            return nil
        }
    }
}
