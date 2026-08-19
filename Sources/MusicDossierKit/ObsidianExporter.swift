import Foundation

public actor ObsidianExporter {
    private let fileManager: FileManager
    private let vaultURL: URL
    private let exportRootURL: URL
    private let notesDirectoryURL: URL
    private let assetsDirectoryURL: URL
    private let L: L10n

    public init?(configuration: AppConfiguration, fileManager: FileManager = .default) throws {
        guard
            configuration.shouldMirrorToObsidian,
            let vaultPath = configuration.obsidianVaultPath?.trimmedNonEmpty
        else {
            return nil
        }

        let vaultURL = URL(fileURLWithPath: vaultPath, isDirectory: true)
        guard fileManager.fileExists(atPath: vaultURL.path) else {
            return nil
        }

        self.fileManager = fileManager
        self.vaultURL = vaultURL

        self.L = L10n(configuration.resolvedLanguage)
        let relativeRoot = configuration.obsidianExportRelativePath?.trimmedNonEmpty ?? "20_Music Dossier"
        self.exportRootURL = vaultURL.appendingPathComponent(relativeRoot, isDirectory: true)
        self.notesDirectoryURL = exportRootURL.appendingPathComponent("Notes", isDirectory: true)
        self.assetsDirectoryURL = exportRootURL.appendingPathComponent("_assets", isDirectory: true)

        try fileManager.createDirectory(at: exportRootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: notesDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: assetsDirectoryURL, withIntermediateDirectories: true)
    }

    @discardableResult
    public func export(
        snapshot: TrackSnapshot,
        dossier: ResearchDossier,
        artworkURL: URL?,
        visualAssetRootURL: URL?
    ) throws -> URL {
        let noteURL = notesDirectoryURL.appendingPathComponent(noteFileName(for: snapshot), isDirectory: false)
        let artworkEmbed = try copyArtworkIfNeeded(snapshot: snapshot, artworkURL: artworkURL)
        let visualEntries = try copyVisualsIfNeeded(dossier: dossier, visualAssetRootURL: visualAssetRootURL)
        let markdown = makeMarkdown(snapshot: snapshot, dossier: dossier, artworkEmbed: artworkEmbed, visualEntries: visualEntries)
        try markdown.write(to: noteURL, atomically: true, encoding: .utf8)
        return noteURL
    }

    private func copyArtworkIfNeeded(snapshot: TrackSnapshot, artworkURL: URL?) throws -> String? {
        guard let artworkURL else { return nil }

        let fileExtension = artworkURL.pathExtension.trimmedNonEmpty ?? "jpg"
        let assetFileName = "\(Hashing.sha256(snapshot.trackKey)).\(fileExtension)"
        let targetURL = assetsDirectoryURL.appendingPathComponent(assetFileName, isDirectory: false)

        if fileManager.fileExists(atPath: targetURL.path) {
            try? fileManager.removeItem(at: targetURL)
        }
        try fileManager.copyItem(at: artworkURL, to: targetURL)

        let relativePath = "\(exportRootURL.lastPathComponent)/_assets/\(assetFileName)"
        return "![[\(relativePath)]]"
    }

    private func copyVisualsIfNeeded(
        dossier: ResearchDossier,
        visualAssetRootURL: URL?
    ) throws -> [(visual: DossierVisual, embed: String)] {
        guard !dossier.visuals.isEmpty else { return [] }

        return try dossier.visuals.compactMap { visual in
            if let cachedFileName = visual.cachedFileName?.trimmedNonEmpty,
               let visualAssetRootURL
            {
                let sourceURL = visualAssetRootURL.appendingPathComponent(cachedFileName, isDirectory: false)
                guard fileManager.fileExists(atPath: sourceURL.path) else { return nil }

                let targetURL = assetsDirectoryURL.appendingPathComponent(cachedFileName, isDirectory: false)
                if fileManager.fileExists(atPath: targetURL.path) {
                    try? fileManager.removeItem(at: targetURL)
                }
                try fileManager.copyItem(at: sourceURL, to: targetURL)
                let relativePath = "\(exportRootURL.lastPathComponent)/_assets/\(cachedFileName)"
                return (visual, "![[\(relativePath)]]")
            }

            guard let remoteURL = visual.imageURL.trimmedNonEmpty else { return nil }
            return (visual, "![\(visual.title)](\(remoteURL))")
        }
    }

    private func noteFileName(for snapshot: TrackSnapshot) -> String {
        let artist = sanitizedFileComponent(snapshot.artist ?? "Unknown Artist")
        let title = sanitizedFileComponent(snapshot.title)
        return "\(title) - \(artist).md"
    }

    private func sanitizedFileComponent(_ value: String) -> String {
        let trimmed = value.trimmedNonEmpty ?? "Untitled"
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleanedScalars = trimmed.unicodeScalars.map { scalar -> Character in
            forbidden.contains(scalar) ? "-" : Character(scalar)
        }
        let cleaned = String(cleanedScalars)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    private func makeMarkdown(
        snapshot: TrackSnapshot,
        dossier: ResearchDossier,
        artworkEmbed: String?,
        visualEntries: [(visual: DossierVisual, embed: String)]
    ) -> String {
        var lines = [String]()
        lines.append("---")
        lines.append("music_dossier: true")
        lines.append("track_key: \"\(snapshot.trackKey.replacingOccurrences(of: "\"", with: "\\\""))\"")
        lines.append("title: \"\(snapshot.title.replacingOccurrences(of: "\"", with: "\\\""))\"")
        if let artist = snapshot.artist?.trimmedNonEmpty {
            lines.append("artist: \"\(artist.replacingOccurrences(of: "\"", with: "\\\""))\"")
        }
        if let album = snapshot.album?.trimmedNonEmpty {
            lines.append("album: \"\(album.replacingOccurrences(of: "\"", with: "\\\""))\"")
        }
        lines.append("generated_at: \"\(ISO8601DateFormatter().string(from: .now))\"")
        lines.append("---")
        lines.append("")
        lines.append("# \(snapshot.title)")
        lines.append("")
        lines.append("> \(dossier.oneLiner)")
        lines.append("")

        if let artworkEmbed {
            lines.append(artworkEmbed)
            lines.append("")
        }

        if !visualEntries.isEmpty {
            lines.append("## \(L.t("sec.gallery"))")
            for entry in visualEntries {
                lines.append("### \(entry.visual.title)")
                lines.append(entry.embed)
                lines.append("")
                lines.append("> \(entry.visual.subject) · \(entry.visual.caption) · \(entry.visual.confidence.rawValue.uppercased())")
                lines.append("> [\(L.t("link.source"))](\(entry.visual.sourceURL))")
                lines.append("")
            }
        }

        if let story = dossier.story?.trimmedNonEmpty {
            lines.append("## \(L.t("sec.story"))")
            lines.append(story)
            lines.append("")
        }

        if !dossier.listeningNotes.isEmpty {
            lines.append("## \(L.t("sec.notes"))")
            for (index, note) in dossier.listeningNotes.enumerated() {
                lines.append("\(index + 1). \(note)")
            }
            lines.append("")
        }

        if let album = dossier.album, album.isMeaningful {
            lines.append("## \(L.t("sec.album"))")
            lines.append("**\(album.title)** · \(album.artist) · \(album.year) · \(album.label)")
            lines.append("")
            lines.append(album.summary)
            for item in album.highlights { lines.append("- \(item)") }
            lines.append("")
        }

        lines.append("## \(L.t("md.trackInfo"))")
        lines.append("- \(L.t("md.artist")): \(snapshot.artist ?? L.t("md.unknown"))")
        lines.append("- \(L.t("sec.album")): \(snapshot.album ?? L.t("md.unknown"))")
        lines.append("- \(L.t("pending.albumArtist")): \(snapshot.albumArtist ?? L.t("md.unknown"))")
        lines.append("- \(L.t("pending.composer")): \(snapshot.composer ?? L.t("md.unknown"))")
        lines.append("- \(L.t("pending.genre")): \(snapshot.genre ?? L.t("md.unknown"))")
        lines.append("- \(L.t("md.year")): \(snapshot.year.map(String.init) ?? L.t("md.unknown"))")
        lines.append("")

        lines.append("## \(L.t("sec.people"))")
        if dossier.creators.isEmpty {
            lines.append("- —")
        } else {
            for creator in dossier.creators {
                lines.append("- **\(creator.name)** · \(creator.role) · \(creator.bio ?? creator.summary)")
            }
        }
        lines.append("")

        lines.append("## \(L.t("sec.facts"))")
        if dossier.background.isEmpty {
            lines.append("- —")
        } else {
            for fact in dossier.background {
                lines.append("- **\(fact.title)**：\(fact.body) · \(fact.confidence.rawValue.uppercased())")
            }
        }
        lines.append("")

        lines.append("## \(L.t("sec.anecdotes"))")
        if dossier.anecdotes.isEmpty {
            lines.append("- —")
        } else {
            for fact in dossier.anecdotes {
                lines.append("- **\(fact.title)**：\(fact.body) · \(fact.confidence.rawValue.uppercased())")
            }
        }
        lines.append("")

        lines.append("## \(L.t("sec.timeline"))")
        if dossier.timeline.isEmpty {
            lines.append("- —")
        } else {
            for event in dossier.timeline {
                lines.append("- **\(event.dateLabel)** · \(event.title)：\(event.body) · \(event.confidence.rawValue.uppercased())")
            }
        }
        lines.append("")

        lines.append("## \(L.t("sec.related"))")
        if dossier.relatedWorks.isEmpty {
            lines.append("- —")
        } else {
            for work in dossier.relatedWorks {
                lines.append("- **\(work.title)** · \(work.artist)：\(work.reason) · \(work.confidence.rawValue.uppercased())")
            }
        }
        lines.append("")

        lines.append("## \(L.t("md.note"))")
        lines.append(dossier.confidenceNote)
        lines.append("")

        lines.append("## \(L.t("sec.sources", String(dossier.citations.count)))")
        if dossier.citations.isEmpty {
            lines.append("- —")
        } else {
            for citation in dossier.citations {
                lines.append("- [\(citation.title)](\(citation.url)) · \(citation.publisher) · \(citation.note) · \(citation.confidence.rawValue.uppercased())")
            }
        }
        lines.append("")

        return lines.joined(separator: "\n")
    }
}
