import Foundation

public struct PipelineResult: Sendable {
    public let snapshot: TrackSnapshot
    public let dossier: ResearchDossier
    public let cached: CachedDossier
}

public actor DossierPipeline {
    private let cacheStore: CacheStore
    private let buildDossierClosure: @Sendable (TrackSnapshot) async throws -> ResearchDossier
    private let obsidianExporter: ObsidianExporter?
    private let session: URLSession
    private let language: AppLanguage

    public init(
        cacheStore: CacheStore,
        buildDossier: @escaping @Sendable (TrackSnapshot) async throws -> ResearchDossier,
        obsidianExporter: ObsidianExporter? = nil,
        session: URLSession = .shared,
        language: AppLanguage = .en
    ) {
        self.cacheStore = cacheStore
        self.buildDossierClosure = buildDossier
        self.obsidianExporter = obsidianExporter
        self.session = session
        self.language = language
    }

    public func loadCachedDossier(for trackKey: String) async throws -> CachedDossier? {
        try cacheStore.loadLatestDossier(for: trackKey)
    }

    public func hydrateDossierForDisplay(_ dossier: ResearchDossier, trackKey: String) async -> ResearchDossier {
        let hydrated = await hydrateAll(in: dossier, trackKey: trackKey)
        if hydrated != dossier {
            try? cacheStore.updateDossierJSON(hydrated, trackKey: trackKey)
        }
        return hydrated
    }

    public func loadArtworkURL(for trackKey: String) async -> URL? {
        cacheStore.artworkURL(for: trackKey)
    }

    public func storeArtwork(_ data: Data, fileExtension: String, trackKey: String) async throws -> URL {
        try cacheStore.saveArtwork(data, fileExtension: fileExtension, trackKey: trackKey)
    }

    public func shouldRefresh(_ cached: CachedDossier?, maxAge: TimeInterval) async -> Bool {
        guard let cached else { return true }
        return !cacheStore.isDossierFresh(cached, maxAge: maxAge)
    }

    public func buildDossier(for snapshot: TrackSnapshot, maxAge: TimeInterval) async throws -> PipelineResult {
        let dossier = try await buildDossierClosure(snapshot)
        let hydratedDossier = await hydrateAll(in: dossier, trackKey: snapshot.trackKey)
        let artworkURL = cacheStore.artworkURL(for: snapshot.trackKey)
        let html = HTMLRenderer.render(
            payload: RenderPayload(
                snapshot: snapshot,
                dossier: hydratedDossier,
                artworkURL: artworkURL,
                visualAssetRootURL: cacheStore.visualsDirectoryURL,
                language: language,
                statusHeadline: L10n(language).t("st.updated.title"),
                statusDetail: L10n(language).t("st.byClaude"),
                cachedAt: .now,
                isPinned: false,
                isStale: false
            )
        )
        let cached = try cacheStore.saveDossier(hydratedDossier, html: html, trackKey: snapshot.trackKey, maxAge: maxAge)
        _ = try? await obsidianExporter?.export(
            snapshot: snapshot,
            dossier: hydratedDossier,
            artworkURL: artworkURL,
            visualAssetRootURL: cacheStore.visualsDirectoryURL
        )
        return PipelineResult(snapshot: snapshot, dossier: hydratedDossier, cached: cached)
    }

    public func ensureObsidianMirror(
        snapshot: TrackSnapshot,
        dossier: ResearchDossier
    ) async {
        let artworkURL = cacheStore.artworkURL(for: snapshot.trackKey)
        _ = try? await obsidianExporter?.export(
            snapshot: snapshot,
            dossier: dossier,
            artworkURL: artworkURL,
            visualAssetRootURL: cacheStore.visualsDirectoryURL
        )
    }

    // MARK: - Hydration（把图片落到本地缓存）

    private func hydrateAll(in dossier: ResearchDossier, trackKey: String) async -> ResearchDossier {
        async let visuals = hydrateVisuals(dossier.visuals, trackKey: trackKey)
        async let creators = hydrateCreators(dossier.creators, trackKey: trackKey)
        async let relatedWorks = hydrateRelatedWorks(dossier.relatedWorks, trackKey: trackKey)
        return await dossier.withHydration(visuals: visuals, creators: creators, relatedWorks: relatedWorks)
    }

    private func hydrateVisuals(_ visuals: [DossierVisual], trackKey: String) async -> [DossierVisual] {
        guard !visuals.isEmpty else { return [] }
        let limited = Array(visuals.prefix(6))
        let results: [DossierVisual?] = await withTaskGroup(of: (Int, DossierVisual).self) { group in
            for (index, visual) in limited.enumerated() {
                group.addTask { [self] in
                    if let cachedFileName = visual.cachedFileName, await self.cacheStore.visualURL(fileName: cachedFileName) != nil {
                        return (index, visual)
                    }
                    let outcome = await self.cacheVisualAsset(for: visual, trackKey: trackKey)
                    return (index, visual.withCachedFileName(outcome?.fileName, resolvedSourceURL: outcome?.sourceURL))
                }
            }
            var ordered = [DossierVisual?](repeating: nil, count: limited.count)
            for await (index, visual) in group { ordered[index] = visual }
            return ordered
        }
        // 没拿到图的条目也保留（渲染时会跳过），下次展示时还会再试一次
        return results.compactMap { $0 }
    }

    private func hydrateCreators(_ creators: [DossierPerson], trackKey: String) async -> [DossierPerson] {
        guard !creators.isEmpty else { return [] }
        let limited = Array(creators.prefix(6))
        let results: [DossierPerson?] = await withTaskGroup(of: (Int, DossierPerson).self) { group in
            for (index, person) in limited.enumerated() {
                group.addTask { [self] in
                    if let fileName = person.imageFileName, await self.cacheStore.visualURL(fileName: fileName) != nil {
                        return (index, person)
                    }
                    let title = person.wikipediaTitle ?? person.name
                    guard let resolved = await WikipediaImageResolver.resolve(title: title, lang: person.wikipediaLang, fallbackLang: self.language.wikipediaLang, session: self.session),
                          let asset = await self.downloadFirstImageAsset(from: resolved.imageCandidates),
                          let fileName = try? await self.cacheStore.saveVisualAsset(asset.data, trackKey: trackKey, remoteURL: asset.cacheKey, fileExtension: asset.fileExtension)
                    else {
                        return (index, person)
                    }
                    return (index, person.withImage(fileName: fileName, sourceURL: resolved.pageURL))
                }
            }
            var ordered = [DossierPerson?](repeating: nil, count: limited.count)
            for await (index, person) in group { ordered[index] = person }
            return ordered
        }
        return results.compactMap { $0 }
    }

    private func hydrateRelatedWorks(_ works: [DossierRelatedWork], trackKey: String) async -> [DossierRelatedWork] {
        guard !works.isEmpty else { return [] }
        let limited = Array(works.prefix(6))
        let results: [DossierRelatedWork?] = await withTaskGroup(of: (Int, DossierRelatedWork).self) { group in
            for (index, work) in limited.enumerated() {
                group.addTask { [self] in
                    if let fileName = work.artworkFileName, await self.cacheStore.visualURL(fileName: fileName) != nil {
                        return (index, work)
                    }
                    guard let artwork = await ITunesArtworkLookup.fetchArtwork(
                        title: work.title, artist: work.artist, album: nil, size: 300, session: self.session
                    ), let fileName = try? await self.cacheStore.saveVisualAsset(
                        artwork.data, trackKey: trackKey, remoteURL: "itunes:\(work.artist)|\(work.title)", fileExtension: artwork.fileExtension
                    ) else {
                        return (index, work)
                    }
                    return (index, work.withArtworkFileName(fileName))
                }
            }
            var ordered = [DossierRelatedWork?](repeating: nil, count: limited.count)
            for await (index, work) in group { ordered[index] = work }
            return ordered
        }
        return results.compactMap { $0 }
    }

    private func cacheVisualAsset(for visual: DossierVisual, trackKey: String) async -> (fileName: String, sourceURL: String?)? {
        // 1. 维基百科词条首图（最可靠）
        if let title = visual.wikipediaTitle,
           let resolved = await WikipediaImageResolver.resolve(title: title, lang: visual.wikipediaLang, fallbackLang: language.wikipediaLang, session: session),
           let asset = await downloadFirstImageAsset(from: resolved.imageCandidates),
           let fileName = try? cacheStore.saveVisualAsset(asset.data, trackKey: trackKey, remoteURL: asset.cacheKey, fileExtension: asset.fileExtension)
        {
            return (fileName, resolved.pageURL)
        }

        // 2. 模型给的直链
        if let asset = await downloadImageAsset(from: visual.imageURL),
           let fileName = try? cacheStore.saveVisualAsset(asset.data, trackKey: trackKey, remoteURL: asset.cacheKey, fileExtension: asset.fileExtension)
        {
            return (fileName, visual.sourceURL.trimmedNonEmpty)
        }

        // 3. 来源页的 og:image
        if let fallbackURL = await resolveFallbackImageURL(from: visual.sourceURL, excluding: visual.imageURL),
           let asset = await downloadImageAsset(from: fallbackURL),
           let fileName = try? cacheStore.saveVisualAsset(asset.data, trackKey: trackKey, remoteURL: asset.cacheKey, fileExtension: asset.fileExtension)
        {
            return (fileName, visual.sourceURL.trimmedNonEmpty)
        }

        return nil
    }

    private func downloadFirstImageAsset(from candidates: [String]) async -> (data: Data, fileExtension: String?, cacheKey: String)? {
        for candidate in candidates {
            if let asset = await downloadImageAsset(from: candidate) { return asset }
        }
        return nil
    }

    private func downloadImageAsset(from urlString: String) async -> (data: Data, fileExtension: String?, cacheKey: String)? {
        guard let remoteURL = URL(string: urlString), let scheme = remoteURL.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else {
            return nil
        }

        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 30
        request.setValue("MusicDossier/1.1 (macOS; personal research widget)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ..< 300).contains(httpResponse.statusCode),
                  data.count > 800
            else {
                return nil
            }

            let contentType = (httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            let detectedExtension = ImageSniffing.detectedFileExtension(for: data)
            let remoteExtension = remoteURL.pathExtension.trimmedNonEmpty?.lowercased()
            guard detectedExtension != nil || remoteExtension != nil || contentType.hasPrefix("image/") else {
                return nil
            }

            return (data, detectedExtension ?? remoteExtension, remoteURL.absoluteString)
        } catch {
            return nil
        }
    }

    private func resolveFallbackImageURL(from sourceURLString: String, excluding originalURLString: String?) async -> String? {
        guard let sourceURL = URL(string: sourceURLString), let scheme = sourceURL.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else {
            return nil
        }

        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = 30
        request.setValue("Mozilla/5.0 MusicDossier/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ..< 300).contains(httpResponse.statusCode),
                  let html = String(data: data, encoding: .utf8)
            else {
                return nil
            }

            let patterns = [
                #"<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']"#,
                #"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']"#,
                #"<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']+)["']"#,
                #"<meta[^>]+content=["']([^"']+)["'][^>]+name=["']twitter:image["']"#,
                #"<link[^>]+rel=["']preload["'][^>]+as=["']image["'][^>]+href=["']([^"']+)["']"#,
                #"<link[^>]+href=["']([^"']+)["'][^>]+rel=["']preload["'][^>]+as=["']image["']"#,
            ]

            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                    continue
                }
                let range = NSRange(html.startIndex ..< html.endIndex, in: html)
                guard let match = regex.firstMatch(in: html, range: range),
                      match.numberOfRanges > 1,
                      let captureRange = Range(match.range(at: 1), in: html)
                else {
                    continue
                }

                let rawCandidate = String(html[captureRange]).decodingHTMLEntities().trimmingCharacters(in: .whitespacesAndNewlines)
                guard let resolved = normalizedImageCandidate(rawCandidate, relativeTo: sourceURL) else {
                    continue
                }

                if resolved == originalURLString?.trimmedNonEmpty {
                    continue
                }

                return resolved
            }
        } catch {
            return nil
        }

        return nil
    }

    private func normalizedImageCandidate(_ value: String, relativeTo sourceURL: URL) -> String? {
        guard let candidate = value.trimmedNonEmpty else { return nil }
        if candidate.hasPrefix("//") {
            return "https:\(candidate)"
        }
        if let absolute = URL(string: candidate), let scheme = absolute.scheme?.lowercased(), scheme == "https" || scheme == "http" {
            return absolute.absoluteString
        }
        if candidate.hasPrefix("/") {
            var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false)
            components?.path = candidate
            components?.query = nil
            components?.fragment = nil
            return components?.url?.absoluteString
        }
        return URL(string: candidate, relativeTo: sourceURL)?.absoluteURL.absoluteString
    }
}
