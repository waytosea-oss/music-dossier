import Foundation

public enum PlayerState: String, Codable, Sendable {
    case playing
    case paused
    case stopped
    case unknown
}

public enum ObservationStatus: Equatable, Sendable {
    case ok
    case notRunning
    case noTrack
    case permissionDenied
    case failed(String)
}

public struct MusicObservation: Equatable, Sendable {
    public let status: ObservationStatus
    public let playerState: PlayerState
    public let snapshot: TrackSnapshot?

    public init(status: ObservationStatus, playerState: PlayerState, snapshot: TrackSnapshot?) {
        self.status = status
        self.playerState = playerState
        self.snapshot = snapshot
    }
}

public struct TrackSnapshot: Codable, Sendable, Equatable {
    public let trackKey: String
    public let persistentId: String?
    public let databaseId: Int?
    public let title: String
    public let artist: String?
    public let album: String?
    public let albumArtist: String?
    public let composer: String?
    public let durationSeconds: Double?
    public let genre: String?
    public let year: Int?
    public let releaseDate: Date?
    public let lyrics: String?
    public let artworkData: Data?
    public let playerState: PlayerState
    public let kind: String?
    public let comment: String?
    public let cloudStatus: String?
    public let fetchedAt: Date

    public init(
        persistentId: String?,
        databaseId: Int?,
        title: String,
        artist: String?,
        album: String?,
        albumArtist: String?,
        composer: String?,
        durationSeconds: Double?,
        genre: String?,
        year: Int?,
        releaseDate: Date?,
        lyrics: String?,
        artworkData: Data?,
        playerState: PlayerState,
        kind: String?,
        comment: String?,
        cloudStatus: String?,
        fetchedAt: Date = .now
    ) {
        self.persistentId = persistentId?.trimmedNonEmpty
        self.databaseId = databaseId
        self.title = title
        self.artist = artist?.trimmedNonEmpty
        self.album = album?.trimmedNonEmpty
        self.albumArtist = albumArtist?.trimmedNonEmpty
        self.composer = composer?.trimmedNonEmpty
        self.durationSeconds = durationSeconds
        self.genre = genre?.trimmedNonEmpty
        self.year = year
        self.releaseDate = releaseDate
        self.lyrics = lyrics?.trimmedNonEmpty
        self.artworkData = artworkData
        self.playerState = playerState
        self.kind = kind?.trimmedNonEmpty
        self.comment = comment?.trimmedNonEmpty
        self.cloudStatus = cloudStatus?.trimmedNonEmpty
        self.fetchedAt = fetchedAt
        self.trackKey = Self.makeTrackKey(
            persistentId: persistentId,
            title: title,
            artist: artist,
            album: album,
            durationSeconds: durationSeconds
        )
    }

    public func withArtworkData(_ data: Data?) -> TrackSnapshot {
        TrackSnapshot(
            persistentId: persistentId,
            databaseId: databaseId,
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            composer: composer,
            durationSeconds: durationSeconds,
            genre: genre,
            year: year,
            releaseDate: releaseDate,
            lyrics: lyrics,
            artworkData: data,
            playerState: playerState,
            kind: kind,
            comment: comment,
            cloudStatus: cloudStatus,
            fetchedAt: fetchedAt
        )
    }

    public static func makeTrackKey(
        persistentId: String?,
        title: String,
        artist: String?,
        album: String?,
        durationSeconds: Double?
    ) -> String {
        if let persistentId, let cleaned = persistentId.trimmedNonEmpty {
            return "music:\(cleaned.lowercased())"
        }

        let durationBucket: String
        if let durationSeconds {
            durationBucket = String(Int(durationSeconds.rounded()))
        } else {
            durationBucket = "0"
        }

        let tokens = [
            title.normalizedTrackToken(),
            artist.normalizedTrackToken,
            album.normalizedTrackToken,
            durationBucket,
        ]

        return "fallback:\(tokens.joined(separator: "|"))"
    }
}

public enum FactConfidence: String, Codable, Sendable {
    case verified
    case inferred
}

public struct DossierPerson: Codable, Sendable, Equatable {
    public let name: String
    public let role: String
    public let summary: String
    /// 人物小传（3–6 句），比 summary 更完整。
    public let bio: String?
    /// 维基百科词条标题（用于取头像与链接），如 "Glenn Gould"。
    public let wikipediaTitle: String?
    public let wikipediaLang: String?
    /// 已缓存到本地 visuals 目录的头像文件名。
    public let imageFileName: String?
    public let imageSourceURL: String?
    public let confidence: FactConfidence

    private enum CodingKeys: String, CodingKey {
        case name, role, summary, bio, wikipediaTitle, wikipediaLang, imageFileName, imageSourceURL, confidence
    }

    public init(
        name: String,
        role: String,
        summary: String,
        bio: String? = nil,
        wikipediaTitle: String? = nil,
        wikipediaLang: String? = nil,
        imageFileName: String? = nil,
        imageSourceURL: String? = nil,
        confidence: FactConfidence
    ) {
        self.name = name
        self.role = role
        self.summary = summary
        self.bio = bio?.trimmedNonEmpty
        self.wikipediaTitle = wikipediaTitle?.trimmedNonEmpty
        self.wikipediaLang = wikipediaLang?.trimmedNonEmpty
        self.imageFileName = imageFileName?.trimmedNonEmpty
        self.imageSourceURL = imageSourceURL?.trimmedNonEmpty
        self.confidence = confidence
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        bio = try c.decodeIfPresent(String.self, forKey: .bio)?.trimmedNonEmpty
        wikipediaTitle = try c.decodeIfPresent(String.self, forKey: .wikipediaTitle)?.trimmedNonEmpty
        wikipediaLang = try c.decodeIfPresent(String.self, forKey: .wikipediaLang)?.trimmedNonEmpty
        imageFileName = try c.decodeIfPresent(String.self, forKey: .imageFileName)?.trimmedNonEmpty
        imageSourceURL = try c.decodeIfPresent(String.self, forKey: .imageSourceURL)?.trimmedNonEmpty
        confidence = try c.decodeIfPresent(FactConfidence.self, forKey: .confidence) ?? .inferred
    }

    public func withImage(fileName: String?, sourceURL: String?) -> DossierPerson {
        DossierPerson(
            name: name, role: role, summary: summary, bio: bio,
            wikipediaTitle: wikipediaTitle, wikipediaLang: wikipediaLang,
            imageFileName: fileName, imageSourceURL: sourceURL, confidence: confidence
        )
    }
}

public struct DossierFact: Codable, Sendable, Equatable {
    public let title: String
    public let body: String
    public let confidence: FactConfidence

    public init(title: String, body: String, confidence: FactConfidence) {
        self.title = title
        self.body = body
        self.confidence = confidence
    }
}

public struct DossierTimelineEvent: Codable, Sendable, Equatable {
    public let dateLabel: String
    public let title: String
    public let body: String
    public let confidence: FactConfidence

    public init(dateLabel: String, title: String, body: String, confidence: FactConfidence) {
        self.dateLabel = dateLabel
        self.title = title
        self.body = body
        self.confidence = confidence
    }
}

public struct DossierRelatedWork: Codable, Sendable, Equatable {
    public let title: String
    public let artist: String
    public let reason: String
    /// 已缓存的封面缩略图文件名（由 iTunes Search API 补齐）。
    public let artworkFileName: String?
    public let confidence: FactConfidence

    private enum CodingKeys: String, CodingKey {
        case title, artist, reason, artworkFileName, confidence
    }

    public init(title: String, artist: String, reason: String, artworkFileName: String? = nil, confidence: FactConfidence) {
        self.title = title
        self.artist = artist
        self.reason = reason
        self.artworkFileName = artworkFileName?.trimmedNonEmpty
        self.confidence = confidence
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        artworkFileName = try c.decodeIfPresent(String.self, forKey: .artworkFileName)?.trimmedNonEmpty
        confidence = try c.decodeIfPresent(FactConfidence.self, forKey: .confidence) ?? .inferred
    }

    public func withArtworkFileName(_ fileName: String?) -> DossierRelatedWork {
        DossierRelatedWork(title: title, artist: artist, reason: reason, artworkFileName: fileName, confidence: confidence)
    }
}

public struct DossierVisual: Codable, Sendable, Equatable {
    public let title: String
    public let subject: String
    public let caption: String
    public let kind: String
    /// 图片直链；可为空，此时由 wikipediaTitle 解析。
    public let imageURL: String
    public let sourceURL: String
    /// 维基百科词条标题：取该词条的首图作为本图。
    public let wikipediaTitle: String?
    public let wikipediaLang: String?
    public let confidence: FactConfidence
    public let cachedFileName: String?
    /// 实际取到图的来源页（维基词条页或原 sourceURL）。
    public let resolvedSourceURL: String?

    private enum CodingKeys: String, CodingKey {
        case title, subject, caption, kind, imageURL, sourceURL, wikipediaTitle, wikipediaLang, confidence, cachedFileName, resolvedSourceURL
    }

    public init(
        title: String,
        subject: String,
        caption: String,
        kind: String,
        imageURL: String,
        sourceURL: String,
        wikipediaTitle: String? = nil,
        wikipediaLang: String? = nil,
        confidence: FactConfidence,
        cachedFileName: String? = nil,
        resolvedSourceURL: String? = nil
    ) {
        self.title = title
        self.subject = subject
        self.caption = caption
        self.kind = kind
        self.imageURL = imageURL
        self.sourceURL = sourceURL
        self.wikipediaTitle = wikipediaTitle?.trimmedNonEmpty
        self.wikipediaLang = wikipediaLang?.trimmedNonEmpty
        self.confidence = confidence
        self.cachedFileName = cachedFileName
        self.resolvedSourceURL = resolvedSourceURL?.trimmedNonEmpty
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? ""
        caption = try c.decodeIfPresent(String.self, forKey: .caption) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        imageURL = try c.decodeIfPresent(String.self, forKey: .imageURL) ?? ""
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL) ?? ""
        wikipediaTitle = try c.decodeIfPresent(String.self, forKey: .wikipediaTitle)?.trimmedNonEmpty
        wikipediaLang = try c.decodeIfPresent(String.self, forKey: .wikipediaLang)?.trimmedNonEmpty
        confidence = try c.decodeIfPresent(FactConfidence.self, forKey: .confidence) ?? .inferred
        cachedFileName = try c.decodeIfPresent(String.self, forKey: .cachedFileName)
        resolvedSourceURL = try c.decodeIfPresent(String.self, forKey: .resolvedSourceURL)?.trimmedNonEmpty
    }

    public func withCachedFileName(_ cachedFileName: String?, resolvedSourceURL: String? = nil) -> DossierVisual {
        DossierVisual(
            title: title,
            subject: subject,
            caption: caption,
            kind: kind,
            imageURL: imageURL,
            sourceURL: sourceURL,
            wikipediaTitle: wikipediaTitle,
            wikipediaLang: wikipediaLang,
            confidence: confidence,
            cachedFileName: cachedFileName,
            resolvedSourceURL: resolvedSourceURL ?? self.resolvedSourceURL
        )
    }

    /// 页面上"打开来源"用的链接。
    public var displaySourceURL: String {
        resolvedSourceURL ?? sourceURL
    }
}

public struct Citation: Codable, Sendable, Equatable, Hashable {
    public let title: String
    public let url: String
    public let publisher: String
    public let note: String
    public let confidence: FactConfidence

    public init(title: String, url: String, publisher: String, note: String, confidence: FactConfidence) {
        self.title = title
        self.url = url
        self.publisher = publisher
        self.note = note
        self.confidence = confidence
    }
}

public struct DossierAlbum: Codable, Sendable, Equatable {
    public let title: String
    public let artist: String
    public let year: String
    public let label: String
    /// 2–4 句专辑介绍：定位、录制背景、评价。
    public let summary: String
    /// 同专辑值得听的其他曲目，每条 "曲名 — 一句话"。
    public let highlights: [String]
    public let wikipediaTitle: String?
    public let wikipediaLang: String?
    public let sourceURL: String?
    public let confidence: FactConfidence

    private enum CodingKeys: String, CodingKey {
        case title, artist, year, label, summary, highlights, wikipediaTitle, wikipediaLang, sourceURL, confidence
    }

    public init(
        title: String, artist: String, year: String, label: String, summary: String,
        highlights: [String], wikipediaTitle: String? = nil, wikipediaLang: String? = nil,
        sourceURL: String? = nil, confidence: FactConfidence
    ) {
        self.title = title
        self.artist = artist
        self.year = year
        self.label = label
        self.summary = summary
        self.highlights = highlights.compactMap { $0.trimmedNonEmpty }
        self.wikipediaTitle = wikipediaTitle?.trimmedNonEmpty
        self.wikipediaLang = wikipediaLang?.trimmedNonEmpty
        self.sourceURL = sourceURL?.trimmedNonEmpty
        self.confidence = confidence
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        year = try c.decodeIfPresent(String.self, forKey: .year) ?? ""
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        highlights = (try c.decodeIfPresent([String].self, forKey: .highlights) ?? []).compactMap { $0.trimmedNonEmpty }
        wikipediaTitle = try c.decodeIfPresent(String.self, forKey: .wikipediaTitle)?.trimmedNonEmpty
        wikipediaLang = try c.decodeIfPresent(String.self, forKey: .wikipediaLang)?.trimmedNonEmpty
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL)?.trimmedNonEmpty
        confidence = try c.decodeIfPresent(FactConfidence.self, forKey: .confidence) ?? .inferred
    }

    public var isMeaningful: Bool {
        summary.trimmedNonEmpty != nil || !highlights.isEmpty
    }
}

public struct ResearchDossier: Codable, Sendable, Equatable {
    public let headline: String
    public let oneLiner: String
    /// 编辑手记：2–4 段有观点、有细节的短文，是页面的主叙事。
    public let story: String?
    /// 听点：这首歌值得留意的段落/编曲/演唱细节，每条一句话。
    public let listeningNotes: [String]
    /// 所属专辑介绍。
    public let album: DossierAlbum?
    public let visuals: [DossierVisual]
    public let creators: [DossierPerson]
    public let background: [DossierFact]
    public let anecdotes: [DossierFact]
    public let timeline: [DossierTimelineEvent]
    public let relatedWorks: [DossierRelatedWork]
    public let confidenceNote: String
    public let citations: [Citation]

    private enum CodingKeys: String, CodingKey {
        case headline
        case oneLiner
        case story
        case listeningNotes
        case album
        case visuals
        case creators
        case background
        case anecdotes
        case timeline
        case relatedWorks
        case confidenceNote
        case citations
    }

    public init(
        headline: String,
        oneLiner: String,
        story: String? = nil,
        listeningNotes: [String] = [],
        album: DossierAlbum? = nil,
        visuals: [DossierVisual],
        creators: [DossierPerson],
        background: [DossierFact],
        anecdotes: [DossierFact],
        timeline: [DossierTimelineEvent],
        relatedWorks: [DossierRelatedWork],
        confidenceNote: String,
        citations: [Citation]
    ) {
        self.headline = headline
        self.oneLiner = oneLiner
        self.story = story?.trimmedNonEmpty
        self.listeningNotes = listeningNotes.compactMap { $0.trimmedNonEmpty }
        self.album = album
        self.visuals = visuals
        self.creators = creators
        self.background = background
        self.anecdotes = anecdotes
        self.timeline = timeline
        self.relatedWorks = relatedWorks
        self.confidenceNote = confidenceNote
        self.citations = citations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        headline = try container.decode(String.self, forKey: .headline)
        oneLiner = try container.decode(String.self, forKey: .oneLiner)
        story = try container.decodeIfPresent(String.self, forKey: .story)?.trimmedNonEmpty
        listeningNotes = (try container.decodeIfPresent([String].self, forKey: .listeningNotes) ?? []).compactMap { $0.trimmedNonEmpty }
        album = try container.decodeIfPresent(DossierAlbum.self, forKey: .album)
        visuals = try container.decodeIfPresent([DossierVisual].self, forKey: .visuals) ?? []
        creators = try container.decode([DossierPerson].self, forKey: .creators)
        background = try container.decode([DossierFact].self, forKey: .background)
        anecdotes = try container.decode([DossierFact].self, forKey: .anecdotes)
        timeline = try container.decode([DossierTimelineEvent].self, forKey: .timeline)
        relatedWorks = try container.decode([DossierRelatedWork].self, forKey: .relatedWorks)
        confidenceNote = try container.decode(String.self, forKey: .confidenceNote)
        citations = try container.decode([Citation].self, forKey: .citations)
    }

    public func withHydration(
        visuals: [DossierVisual]? = nil,
        creators: [DossierPerson]? = nil,
        relatedWorks: [DossierRelatedWork]? = nil
    ) -> ResearchDossier {
        ResearchDossier(
            headline: headline,
            oneLiner: oneLiner,
            story: story,
            listeningNotes: listeningNotes,
            album: album,
            visuals: visuals ?? self.visuals,
            creators: creators ?? self.creators,
            background: background,
            anecdotes: anecdotes,
            timeline: timeline,
            relatedWorks: relatedWorks ?? self.relatedWorks,
            confidenceNote: confidenceNote,
            citations: citations
        )
    }

    public func withVisuals(_ visuals: [DossierVisual]) -> ResearchDossier {
        ResearchDossier(
            headline: headline,
            oneLiner: oneLiner,
            story: story,
            listeningNotes: listeningNotes,
            album: album,
            visuals: visuals,
            creators: creators,
            background: background,
            anecdotes: anecdotes,
            timeline: timeline,
            relatedWorks: relatedWorks,
            confidenceNote: confidenceNote,
            citations: citations
        )
    }
}

public struct CachedDossier: Sendable {
    public let dossier: ResearchDossier
    public let html: String
    public let htmlURL: URL
    public let updatedAt: Date
    public let expiresAt: Date
}

public enum DossierTheme: String, Codable, Sendable {
    case day
    case night
}

public struct RenderPayload: Sendable {
    public let snapshot: TrackSnapshot?
    public let dossier: ResearchDossier?
    public let artworkURL: URL?
    public let visualAssetRootURL: URL?
    public let theme: DossierTheme
    public let language: AppLanguage
    public let statusHeadline: String
    public let statusDetail: String
    public let cachedAt: Date?
    public let isPinned: Bool
    public let isStale: Bool
    public let lastError: String?

    public init(
        snapshot: TrackSnapshot?,
        dossier: ResearchDossier?,
        artworkURL: URL?,
        visualAssetRootURL: URL? = nil,
        theme: DossierTheme = .day,
        language: AppLanguage = .en,
        statusHeadline: String,
        statusDetail: String,
        cachedAt: Date? = nil,
        isPinned: Bool,
        isStale: Bool,
        lastError: String? = nil
    ) {
        self.snapshot = snapshot
        self.dossier = dossier
        self.artworkURL = artworkURL
        self.visualAssetRootURL = visualAssetRootURL
        self.theme = theme
        self.language = language
        self.statusHeadline = statusHeadline
        self.statusDetail = statusDetail
        self.cachedAt = cachedAt
        self.isPinned = isPinned
        self.isStale = isStale
        self.lastError = lastError
    }
}
