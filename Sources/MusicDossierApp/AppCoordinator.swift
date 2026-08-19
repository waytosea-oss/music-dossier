import AppKit
import Foundation
import MusicDossierKit

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var html: String
    @Published var bannerText: String
    @Published var trackLine: String?
    @Published var displayTheme: DossierTheme
    @Published var isPinned = false
    @Published var canOpenSources = false
    @Published var canRefresh = false

    var baseURL: URL?

    private var configuration: AppConfiguration?
    private var cacheStore: CacheStore?
    private var musicClient: AppleScriptMusicClient?
    private var pipeline: DossierPipeline?

    private var currentSnapshot: TrackSnapshot?
    private var pinnedSnapshot: TrackSnapshot?
    private var currentDossier: ResearchDossier?
    private var currentArtworkURL: URL?
    private var currentCachedAt: Date?
    private var currentIsStale = false
    private var currentError: String?

    private var pollingTask: Task<Void, Never>?
    private var researchTask: Task<Void, Never>?
    private var favoritesPrewarmTask: Task<Void, Never>?
    private var hasCompletedFavoritesPrewarm = false
    private var generation = 0
    private static let themeDefaultsKey = "musicdossier.theme"

    init() {
        let theme = Self.loadThemePreference()
        self.displayTheme = theme
        let initialPayload = RenderPayload(
            snapshot: nil,
            dossier: nil,
            artworkURL: nil,
            theme: theme,
            statusHeadline: "等待 Music 当前曲目",
            statusDetail: "启动后会自动监听播放状态，并在切歌时整理背景信息。",
            cachedAt: nil,
            isPinned: false,
            isStale: false
        )
        self.html = HTMLRenderer.render(payload: initialPayload)
        self.bannerText = "等待 Music 当前曲目"
        self.trackLine = nil
        self.canOpenSources = false
        self.canRefresh = false
    }

    deinit {
        pollingTask?.cancel()
        researchTask?.cancel()
        favoritesPrewarmTask?.cancel()
    }

    func bootstrap() {
        Task {
            await initializeServices()
        }
    }

    func toggleTheme() {
        displayTheme = displayTheme == .day ? .night : .day
        Self.storeThemePreference(displayTheme)
        render(
            statusHeadline: headlineForCurrentState(),
            detail: detailForCurrentState(),
            lastError: currentError
        )
    }

    func togglePin() {
        guard let activeSnapshot = currentSnapshot ?? pinnedSnapshot else { return }

        if isPinned {
            isPinned = false
            pinnedSnapshot = nil
            render(statusHeadline: "已恢复跟随 Music", detail: "现在会继续跟随当前播放歌曲自动刷新。")
            return
        }

        isPinned = true
        pinnedSnapshot = activeSnapshot
        render(statusHeadline: "已固定当前歌曲", detail: "此窗口暂时不会跟随切歌。需要时可以手动刷新。")
    }

    func refreshCurrent() {
        guard let snapshot = pinnedSnapshot ?? currentSnapshot else { return }
        launchTrackTask(for: snapshot, forceRefresh: true)
    }

    func openSources() {
        guard let dossier = currentDossier else { return }
        dossier.citations.prefix(5).forEach { citation in
            guard let url = URL(string: citation.url) else { return }
            NSWorkspace.shared.open(url)
        }
    }

    private func initializeServices() async {
        do {
            let configuration = try AppConfiguration.load()
            let rootURL = try cacheRootURL()
            let cacheStore = try CacheStore(rootURL: rootURL)
            let musicClient = try AppleScriptMusicClient()
            let obsidianExporter = try ObsidianExporter(configuration: configuration)
            let buildDossier = try makeResearchBuilder(configuration: configuration, workspaceURL: rootURL)
            let pipeline = DossierPipeline(
                cacheStore: cacheStore,
                buildDossier: buildDossier,
                obsidianExporter: obsidianExporter
            )

            self.configuration = configuration
            self.cacheStore = cacheStore
            self.musicClient = musicClient
            self.pipeline = pipeline
            self.baseURL = rootURL
            self.canRefresh = true
            render(statusHeadline: "服务已启动", detail: "开始监听 Music.app，并在切歌时懒加载研究档案。")
            startPolling()

            // 启动后在后台清一次缓存（孤儿文件、旧版超大 HTML、总量超限）
            let maxBytes = configuration.resolvedCacheMaxTotalBytes
            Task.detached(priority: .utility) {
                if let report = try? cacheStore.pruneStorage(maxTotalBytes: maxBytes), report.removedFiles > 0 {
                    let mb = Double(report.removedBytes) / 1_048_576
                    NSLog("MusicDossier cache prune: removed %d files (%.1f MB), %d entries; now %.1f MB",
                          report.removedFiles, mb, report.removedEntries, Double(report.totalBytesAfter) / 1_048_576)
                }
            }
        } catch {
            currentError = error.localizedDescription
            render(
                statusHeadline: "启动失败",
                detail: "暂时无法初始化缓存或 Music 通道。",
                lastError: error.localizedDescription
            )
        }
    }

    private func makeResearchBuilder(
        configuration: AppConfiguration,
        workspaceURL: URL
    ) throws -> @Sendable (TrackSnapshot) async throws -> ResearchDossier {
        let provider = configuration.normalizedResearchProvider
        let hasUsableAPIKey = {
            guard let key = configuration.openAIAPIKey?.trimmedNonEmpty else { return false }
            return key != "sk-your-key-here"
        }()
        let hasCodex = CodexCLIResearchClient.resolvedCodexExecutablePath() != nil
        let hasClaude = ClaudeCLIResearchClient.resolvedClaudeExecutablePath(configuredPath: configuration.claudeExecutablePath) != nil
        let claudeWorkspaceURL = workspaceURL.appendingPathComponent("workspace", isDirectory: true)

        func makeClaude() -> @Sendable (TrackSnapshot) async throws -> ResearchDossier {
            let client = ClaudeCLIResearchClient(configuration: configuration, workspaceURL: claudeWorkspaceURL)
            return { snapshot in try await client.buildDossier(for: snapshot) }
        }
        func makeCodex() -> @Sendable (TrackSnapshot) async throws -> ResearchDossier {
            let client = CodexCLIResearchClient(configuration: configuration, workspaceURL: workspaceURL)
            return { snapshot in try await client.buildDossier(for: snapshot) }
        }
        func makeOpenAI() -> @Sendable (TrackSnapshot) async throws -> ResearchDossier {
            let client = OpenAIResearchClient(configuration: configuration)
            return { snapshot in try await client.buildDossier(for: snapshot) }
        }

        switch provider {
        case "claude", "claude-cli", "claude-code":
            guard hasClaude else {
                throw MusicDossierError.invalidConfiguration("配置要求使用 Claude Code CLI，但当前机器上没有找到 claude。")
            }
            return makeClaude()
        case "codex-cli":
            guard hasCodex else {
                throw MusicDossierError.invalidConfiguration("配置要求使用 Codex CLI，但当前机器上没有可用的 codex。")
            }
            return makeCodex()
        case "openai-responses":
            return makeOpenAI()
        case "auto":
            // 优先级：Claude CLI > OpenAI Key > Codex CLI
            if hasClaude { return makeClaude() }
            if hasUsableAPIKey { return makeOpenAI() }
            if hasCodex { return makeCodex() }
            fallthrough
        default:
            throw MusicDossierError.invalidConfiguration("没有可用的研究引擎：没有找到 Claude Code CLI，也没有有效 OpenAI Key 或 Codex CLI。")
        }
    }

    private func cacheRootURL() throws -> URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingDirectory("Library")
            .appendingDirectory("Application Support")
            .appendingDirectory("MusicDossier")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollOnce()
                let interval = self.configuration?.pollIntervalSeconds ?? 1.5
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private func pollOnce() async {
        guard let musicClient else { return }

        do {
            let observation = try await musicClient.fetchObservation()
            handleObservation(observation)
        } catch {
            render(
                statusHeadline: "Music 自动化不可用",
                detail: "当前无法读取播放状态。",
                lastError: error.localizedDescription
            )
        }
    }

    private func handleObservation(_ observation: MusicObservation) {
        if isPinned {
            if bannerText != "已固定当前歌曲" {
                bannerText = "已固定当前歌曲"
            }
            return
        }

        switch observation.status {
        case .notRunning:
            startFavoritesPrewarmIfNeeded()
            if hasRenderableContent {
                render(statusHeadline: "Music 未启动", detail: "Music 已关闭，暂时保留上一首资料页。")
            } else {
                clearCurrentContent()
                render(statusHeadline: "Music 未启动", detail: "打开 Music 并播放歌曲后，会自动生成研究档案。")
            }
        case .noTrack:
            startFavoritesPrewarmIfNeeded()
            let detail: String
            switch observation.playerState {
            case .paused:
                detail = hasRenderableContent ? "Music 当前已暂停，暂时保留上一首资料页。" : "Music 当前已暂停，没有可读取的当前曲目。"
            case .stopped:
                detail = hasRenderableContent ? "Music 当前处于停止状态，暂时保留上一首资料页。" : "Music 当前处于停止状态。"
            default:
                detail = hasRenderableContent ? "当前暂时读不到曲目，先保留上一首资料页。" : "等待下一首曲目。"
            }

            if !hasRenderableContent {
                clearCurrentContent()
            }
            render(statusHeadline: "没有可读取的曲目", detail: detail)
        case .permissionDenied:
            if !hasRenderableContent {
                clearCurrentContent()
            }
            render(
                statusHeadline: "缺少自动化权限",
                detail: hasRenderableContent ? "当前先保留已打开的资料页；请在系统设置里允许本应用控制 Music。" : "请在系统设置里允许本应用控制 Music。",
                lastError: "没有获得 Automation 权限，无法读取当前曲目。"
            )
        case .failed(let message):
            if !hasRenderableContent {
                clearCurrentContent()
            }
            render(
                statusHeadline: "读取 Music 失败",
                detail: hasRenderableContent ? "暂时保留上一首资料页，等待下次轮询恢复。" : "暂时回退到只显示已有内容。",
                lastError: message
            )
        case .ok:
            stopFavoritesPrewarmIfNeeded()
            guard let snapshot = observation.snapshot else { return }

            if currentSnapshot?.trackKey == snapshot.trackKey {
                currentSnapshot = snapshot.withArtworkData(currentSnapshot?.artworkData)
                render(statusHeadline: headlineForCurrentState(), detail: detailForCurrentState(), lastError: currentError)
                return
            }

            currentSnapshot = snapshot
            currentDossier = nil
            currentArtworkURL = nil
            currentCachedAt = nil
            currentIsStale = false
            currentError = nil
            launchTrackTask(for: snapshot, forceRefresh: false)
        }
    }

    private func startFavoritesPrewarmIfNeeded() {
        guard
            favoritesPrewarmTask == nil,
            !hasCompletedFavoritesPrewarm,
            let configuration,
            configuration.shouldPrewarmFavorites,
            configuration.resolvedFavoritesPrewarmLimit > 0,
            let pipeline,
            let musicClient
        else {
            return
        }

        favoritesPrewarmTask = Task { [weak self] in
            guard let self else { return }

            do {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                try await self.prewarmFavoritedTracks(
                    configuration: configuration,
                    pipeline: pipeline,
                    musicClient: musicClient
                )
                self.hasCompletedFavoritesPrewarm = true
            } catch is CancellationError {
                return
            } catch {
                self.hasCompletedFavoritesPrewarm = false
            }

            self.favoritesPrewarmTask = nil
        }
    }

    private func stopFavoritesPrewarmIfNeeded() {
        favoritesPrewarmTask?.cancel()
        favoritesPrewarmTask = nil
    }

    private func prewarmFavoritedTracks(
        configuration: AppConfiguration,
        pipeline: DossierPipeline,
        musicClient: AppleScriptMusicClient
    ) async throws {
        let favorites = try await musicClient.fetchFavoritedSnapshots(limit: configuration.resolvedFavoritesPrewarmLimit)
        guard !favorites.isEmpty else { return }

        for snapshot in favorites {
            try Task.checkCancellation()

            if shouldPausePrewarm {
                return
            }

            if snapshot.trackKey == currentSnapshot?.trackKey || snapshot.trackKey == pinnedSnapshot?.trackKey {
                continue
            }

            let cached = try? await pipeline.loadCachedDossier(for: snapshot.trackKey)
            let shouldRefresh = await pipeline.shouldRefresh(cached, maxAge: configuration.cacheMaxAge)
            let existingArtworkURL = await pipeline.loadArtworkURL(for: snapshot.trackKey)

            if existingArtworkURL == nil,
               let exportedArtwork = try? await musicClient.exportArtworkForLibraryTrack(snapshot)
            {
                _ = try? await pipeline.storeArtwork(
                    exportedArtwork.data,
                    fileExtension: exportedArtwork.fileExtension,
                    trackKey: snapshot.trackKey
                )
            }

            if !shouldRefresh, let cached {
                await pipeline.ensureObsidianMirror(snapshot: snapshot, dossier: cached.dossier)
                continue
            }

            _ = try? await pipeline.buildDossier(for: snapshot, maxAge: configuration.cacheMaxAge)
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
    }

    private var shouldPausePrewarm: Bool {
        if isPinned {
            return true
        }

        guard let snapshot = currentSnapshot else {
            return false
        }

        return snapshot.playerState == .playing
    }

    private func launchTrackTask(for snapshot: TrackSnapshot, forceRefresh: Bool) {
        guard let configuration, let pipeline, let musicClient else { return }

        researchTask?.cancel()
        generation += 1
        let generation = generation

        render(
            statusHeadline: forceRefresh ? "正在强制刷新档案" : "正在读取本地元数据",
            detail: forceRefresh
                ? "忽略旧缓存，重新抓取背景和轶事；首轮联网研究通常需要 1 到 3 分钟。"
                : "先显示歌曲卡片，再后台补全研究内容；首轮联网研究通常需要 1 到 3 分钟。"
        )

        researchTask = Task { [weak self] in
            guard let self else { return }

            let cached = try? await pipeline.loadCachedDossier(for: snapshot.trackKey)
            let fresh = await pipeline.shouldRefresh(cached, maxAge: configuration.cacheMaxAge)

            if Task.isCancelled || !self.isStillCurrent(generation: generation, snapshot: snapshot) {
                return
            }

            if let cached {
                self.currentDossier = cached.dossier
                self.currentCachedAt = cached.updatedAt
                self.currentIsStale = fresh
                self.canOpenSources = !cached.dossier.citations.isEmpty
                Task { [weak self] in
                    let hydrated = await pipeline.hydrateDossierForDisplay(cached.dossier, trackKey: snapshot.trackKey)
                    await pipeline.ensureObsidianMirror(snapshot: snapshot, dossier: hydrated)

                    guard let self else { return }
                    await MainActor.run {
                        guard self.isStillCurrent(generation: generation, snapshot: snapshot) else { return }
                        if self.currentDossier != hydrated {
                            self.currentDossier = hydrated
                            self.canOpenSources = !hydrated.citations.isEmpty
                            self.render(
                                statusHeadline: self.headlineForCurrentState(),
                                detail: self.detailForCurrentState(),
                                lastError: self.currentError
                            )
                        }
                    }
                }
                self.render(
                    statusHeadline: fresh ? "缓存偏旧，后台更新中" : "已命中缓存档案",
                    detail: fresh ? "先显示旧缓存，再懒加载最新资料；更新过程通常需要 1 到 3 分钟。" : "本首歌已有新鲜缓存，不再重复消耗检索。",
                    lastError: self.currentError
                )
            }

            if let artworkURL = await pipeline.loadArtworkURL(for: snapshot.trackKey),
               self.isStillCurrent(generation: generation, snapshot: snapshot) {
                self.currentArtworkURL = artworkURL
                self.render(statusHeadline: self.headlineForCurrentState(), detail: self.detailForCurrentState(), lastError: self.currentError)
            } else if !self.isPinned {
                do {
                    var exportedArtwork = try await musicClient.exportArtwork(for: snapshot)
                    if exportedArtwork == nil {
                        // 流媒体曲目常拿不到本地封面，退而用 iTunes Search API 找一张
                        exportedArtwork = await ITunesArtworkLookup.fetchArtwork(for: snapshot)
                    }
                    if let exportedArtwork,
                       self.isStillCurrent(generation: generation, snapshot: snapshot) {
                        let storedURL = try await pipeline.storeArtwork(
                            exportedArtwork.data,
                            fileExtension: exportedArtwork.fileExtension,
                            trackKey: snapshot.trackKey
                        )
                        self.currentArtworkURL = storedURL
                        self.currentSnapshot = snapshot.withArtworkData(exportedArtwork.data)
                        self.render(statusHeadline: self.headlineForCurrentState(), detail: self.detailForCurrentState(), lastError: self.currentError)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    self.currentError = error.localizedDescription
                    self.render(statusHeadline: self.headlineForCurrentState(), detail: self.detailForCurrentState(), lastError: error.localizedDescription)
                }
            }

            if !forceRefresh, let cached, !(await pipeline.shouldRefresh(cached, maxAge: configuration.cacheMaxAge)) {
                return
            }

            do {
                let result = try await pipeline.buildDossier(for: snapshot, maxAge: configuration.cacheMaxAge)
                guard self.isStillCurrent(generation: generation, snapshot: snapshot) else { return }
                self.currentDossier = result.dossier
                self.currentCachedAt = result.cached.updatedAt
                self.currentIsStale = false
                self.currentError = nil
                self.canOpenSources = !result.dossier.citations.isEmpty
                self.render(statusHeadline: "研究档案已更新", detail: "新的背景、人物与来源已经写入缓存。")
            } catch is CancellationError {
                return
            } catch {
                guard self.isStillCurrent(generation: generation, snapshot: snapshot) else { return }
                self.currentError = error.localizedDescription
                self.render(
                    statusHeadline: self.currentDossier == nil ? "回退到本地元数据" : "保留现有档案",
                    detail: self.currentDossier == nil ? "网络或模型不可用时，会继续显示歌曲卡片。" : "缓存内容仍可阅读，稍后可以手动刷新。",
                    lastError: error.localizedDescription
                )
            }
        }
    }

    private func isStillCurrent(generation: Int, snapshot: TrackSnapshot) -> Bool {
        if self.generation != generation {
            return false
        }

        let active = pinnedSnapshot ?? currentSnapshot
        return active?.trackKey == snapshot.trackKey
    }

    private var hasRenderableContent: Bool {
        currentSnapshot != nil || currentDossier != nil || currentArtworkURL != nil
    }

    private func clearCurrentContent() {
        currentSnapshot = nil
        currentDossier = nil
        currentArtworkURL = nil
        currentCachedAt = nil
        currentIsStale = false
    }

    private func render(statusHeadline: String, detail: String, lastError: String? = nil) {
        let activeSnapshot = pinnedSnapshot ?? currentSnapshot
        let payload = RenderPayload(
            snapshot: activeSnapshot,
            dossier: currentDossier,
            artworkURL: currentArtworkURL,
            visualAssetRootURL: cacheStore?.visualsDirectoryURL,
            theme: displayTheme,
            statusHeadline: statusHeadline,
            statusDetail: detail,
            cachedAt: currentCachedAt,
            isPinned: isPinned,
            isStale: currentIsStale,
            lastError: lastError
        )
        let nextHTML = HTMLRenderer.render(payload: payload)
        let nextTrackLine = activeSnapshot.map { snapshot in
            [
                snapshot.title.decodingHTMLEntities(),
                snapshot.artist?.decodingHTMLEntities(),
                snapshot.album?.decodingHTMLEntities(),
                snapshot.playerState.rawValue.uppercased(),
            ]
            .compactMap { $0?.trimmedNonEmpty }
            .joined(separator: " · ")
        }
        let nextCanOpenSources = !(currentDossier?.citations.isEmpty ?? true)

        if html != nextHTML {
            html = nextHTML
        }
        if bannerText != detail {
            bannerText = detail
        }
        if trackLine != nextTrackLine {
            trackLine = nextTrackLine
        }
        if canOpenSources != nextCanOpenSources {
            canOpenSources = nextCanOpenSources
        }
    }

    private func headlineForCurrentState() -> String {
        if currentDossier != nil {
            return currentIsStale ? "缓存偏旧，后台更新中" : "研究档案已就绪"
        }
        return "正在整理本地元数据"
    }

    private func detailForCurrentState() -> String {
        if currentDossier != nil {
            return currentIsStale ? "当前先展示旧缓存，稍后会补齐最新来源。" : "本首歌的故事和时间线已经可读。"
        }
        return "歌曲切换后会先显示作品卡，再继续补全背景信息。"
    }

    private static func loadThemePreference() -> DossierTheme {
        guard
            let rawValue = UserDefaults.standard.string(forKey: themeDefaultsKey),
            let theme = DossierTheme(rawValue: rawValue)
        else {
            return .day
        }
        return theme
    }

    private static func storeThemePreference(_ theme: DossierTheme) {
        UserDefaults.standard.set(theme.rawValue, forKey: themeDefaultsKey)
    }
}
