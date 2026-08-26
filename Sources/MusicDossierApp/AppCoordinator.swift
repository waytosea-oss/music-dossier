import AppKit
import Foundation
import MusicDossierKit

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var html: String
    @Published var bannerText: String
    @Published var trackLine: String?
    @Published var displayTheme: DossierTheme
    /// 界面文案（启动时按系统语言，读到配置后按配置语言）
    @Published var strings: L10n = .system
    private var language: AppLanguage = AppLanguage.resolve(nil)
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
            language: AppLanguage.resolve(nil),
            statusHeadline: L10n.system.t("st.waiting.title"),
            statusDetail: L10n.system.t("st.waiting.detail"),
            cachedAt: nil,
            isPinned: false,
            isStale: false
        )
        self.html = HTMLRenderer.render(payload: initialPayload)
        self.bannerText = L10n.system.t("st.waiting.title")
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
            render(statusHeadline: strings.t("st.unpinned.title"), detail: strings.t("st.unpinned.detail"))
            return
        }

        isPinned = true
        pinnedSnapshot = activeSnapshot
        render(statusHeadline: strings.t("st.pinned.title"), detail: strings.t("st.pinned.detail"))
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
            self.language = configuration.resolvedLanguage
            self.strings = L10n(configuration.resolvedLanguage)
            let rootURL = try cacheRootURL()
            let cacheStore = try CacheStore(rootURL: rootURL)
            let musicClient = try AppleScriptMusicClient()
            let obsidianExporter = try ObsidianExporter(configuration: configuration)
            let buildDossier = try makeResearchBuilder(configuration: configuration, workspaceURL: rootURL)
            let pipeline = DossierPipeline(
                cacheStore: cacheStore,
                buildDossier: buildDossier,
                obsidianExporter: obsidianExporter,
                language: configuration.resolvedLanguage
            )

            self.configuration = configuration
            self.cacheStore = cacheStore
            self.musicClient = musicClient
            self.pipeline = pipeline
            self.baseURL = rootURL
            self.canRefresh = true
            render(statusHeadline: strings.t("st.started"), detail: strings.t("st.waiting.detail"))
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
            let isSetupIssue = (error as? MusicDossierError).map {
                if case .needsSetup = $0 { return true } else { return false }
            } ?? false
            render(
                statusHeadline: isSetupIssue ? "欢迎使用 · 还差一步" : strings.t("st.startFail.title"),
                detail: isSetupIssue ? "请在弹出的设置窗里选择 AI 服务商并粘贴 API Key。" : strings.t("st.startFail.detail"),
                lastError: error.localizedDescription
            )
            if isSetupIssue {
                NotificationCenter.default.post(name: .musicDossierNeedsSetup, object: nil)
            }
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
        let chatClient = ChatCompletionsResearchClient(configuration: configuration)
        func makeChatAPI() -> @Sendable (TrackSnapshot) async throws -> ResearchDossier {
            { snapshot in try await chatClient.buildDossier(for: snapshot) }
        }
        let hasChatAPI = configuration.apiKey?.trimmedNonEmpty != nil

        switch provider {
        case "claude", "claude-cli", "claude-code":
            guard hasClaude else {
                throw MusicDossierError.invalidConfiguration("researchProvider is claude-cli but no `claude` executable was found on this Mac.")
            }
            return makeClaude()
        case "codex-cli":
            guard hasCodex else {
                throw MusicDossierError.invalidConfiguration("researchProvider is codex-cli but no `codex` executable was found.")
            }
            return makeCodex()
        case "openai-responses":
            return makeOpenAI()
        case "api", "chat-api", "deepseek", "qwen", "kimi", "glm":
            guard hasChatAPI else {
                throw MusicDossierError.needsSetup
            }
            return makeChatAPI()
        case "auto":
            // 优先级：Claude CLI > 通用 API（国产模型）> OpenAI Key > Codex CLI
            if hasClaude { return makeClaude() }
            if hasChatAPI { return makeChatAPI() }
            if hasUsableAPIKey { return makeOpenAI() }
            if hasCodex { return makeCodex() }
            fallthrough
        default:
            throw MusicDossierError.needsSetup
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
                statusHeadline: strings.t("st.automationUnavailable.title"),
                detail: strings.t("st.automationUnavailable.detail"),
                lastError: error.localizedDescription
            )
        }
    }

    private func handleObservation(_ observation: MusicObservation) {
        if isPinned {
            let pinnedText = strings.t("st.pinned.title")
            if bannerText != pinnedText {
                bannerText = pinnedText
            }
            return
        }

        switch observation.status {
        case .notRunning:
            startFavoritesPrewarmIfNeeded()
            if hasRenderableContent {
                render(statusHeadline: strings.t("st.musicNotRunning.title"), detail: strings.t("st.musicNotRunning.keep"))
            } else {
                clearCurrentContent()
                render(statusHeadline: strings.t("st.musicNotRunning.title"), detail: strings.t("st.musicNotRunning.hint"))
            }
        case .noTrack:
            startFavoritesPrewarmIfNeeded()
            let detail = hasRenderableContent ? strings.t("st.noTrack.keep") : strings.t("st.noTrack.hint")
            render(statusHeadline: strings.t("st.noTrack.title"), detail: detail)
        case .permissionDenied:
            if !hasRenderableContent {
                clearCurrentContent()
            }
            render(
                statusHeadline: strings.t("st.noPermission.title"),
                detail: strings.t("st.noPermission.detail"),
                lastError: strings.t("st.noPermission.error")
            )
        case .failed(let message):
            if !hasRenderableContent {
                clearCurrentContent()
            }
            render(
                statusHeadline: strings.t("st.readFail.title"),
                detail: strings.t("st.readFail.detail"),
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
            statusHeadline: forceRefresh ? strings.t("st.forceRefresh.title") : strings.t("st.reading.title"),
            detail: forceRefresh ? strings.t("st.forceRefresh.detail") : strings.t("st.reading.detail")
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
                    statusHeadline: fresh ? self.strings.t("st.cachedStale.title") : self.strings.t("st.cachedHit.title"),
                    detail: fresh ? self.strings.t("st.cachedStale.detail") : self.strings.t("st.cachedHit.detail"),
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
                self.render(statusHeadline: self.strings.t("st.updated.title"), detail: self.strings.t("st.updated.detail"))
            } catch is CancellationError {
                return
            } catch {
                guard self.isStillCurrent(generation: generation, snapshot: snapshot) else { return }
                self.currentError = error.localizedDescription
                self.render(
                    statusHeadline: self.currentDossier == nil ? self.strings.t("st.fallback.title") : self.strings.t("st.keep.title"),
                    detail: self.currentDossier == nil ? self.strings.t("st.fallback.detail") : self.strings.t("st.keep.detail"),
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
            language: language,
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
            return currentIsStale ? strings.t("st.cachedStale.title") : strings.t("st.ready.title")
        }
        return strings.t("st.preparing.title")
    }

    private func detailForCurrentState() -> String {
        if currentDossier != nil {
            return currentIsStale ? strings.t("st.staleShown.detail") : strings.t("st.ready.detail")
        }
        return strings.t("st.preparing.detail")
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
