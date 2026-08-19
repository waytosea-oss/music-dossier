import Foundation

/// 当 Music.app 拿不到封面（常见于流媒体曲目）时，用公开的 iTunes Search API 找一张专辑封面。
public enum ITunesArtworkLookup {
    public static func fetchArtwork(
        for snapshot: TrackSnapshot,
        session: URLSession = .shared
    ) async -> (data: Data, fileExtension: String)? {
        await fetchArtwork(title: snapshot.title, artist: snapshot.artist, album: snapshot.album, size: 600, session: session)
    }

    public static func fetchArtwork(
        title: String,
        artist: String?,
        album: String?,
        size: Int = 600,
        session: URLSession = .shared
    ) async -> (data: Data, fileExtension: String)? {
        let terms = [artist, title]
            .compactMap { $0?.trimmedNonEmpty }
            .joined(separator: " ")
        guard let term = Self.simplifiedSearchTerm(terms).trimmedNonEmpty else { return nil }

        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "limit", value: "8"),
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]], !results.isEmpty
        else {
            return nil
        }

        let albumKey = album?.normalizedTrackToken() ?? ""
        let titleKey = title.normalizedTrackToken()
        let ranked = results.sorted { lhs, rhs in
            score(lhs, albumKey: albumKey, titleKey: titleKey) > score(rhs, albumKey: albumKey, titleKey: titleKey)
        }

        for item in ranked {
            guard let raw = item["artworkUrl100"] as? String else { continue }
            let large = raw
                .replacingOccurrences(of: "100x100bb", with: "\(size)x\(size)bb")
                .replacingOccurrences(of: "100x100", with: "\(size)x\(size)")
            guard let artworkURL = URL(string: large) else { continue }
            var artworkRequest = URLRequest(url: artworkURL)
            artworkRequest.timeoutInterval = 20
            guard let (imageData, imageResponse) = try? await session.data(for: artworkRequest),
                  let imageHTTP = imageResponse as? HTTPURLResponse, (200 ..< 300).contains(imageHTTP.statusCode),
                  imageData.count > 1_000
            else { continue }
            let ext = ImageSniffing.detectedFileExtension(for: imageData) ?? "jpg"
            return (imageData, ext)
        }
        return nil
    }

    private static func score(_ item: [String: Any], albumKey: String, titleKey: String) -> Int {
        var score = 0
        if let album = (item["collectionName"] as? String)?.normalizedTrackToken(), !albumKey.isEmpty {
            if album == albumKey { score += 4 } else if album.contains(albumKey) || albumKey.contains(album) { score += 2 }
        }
        if let track = (item["trackName"] as? String)?.normalizedTrackToken() {
            if track == titleKey { score += 3 } else if track.contains(titleKey) || titleKey.contains(track) { score += 1 }
        }
        return score
    }

    /// 去掉括号里的 Remastered / Live 之类修饰，提高命中率。
    private static func simplifiedSearchTerm(_ value: String) -> String {
        var text = value
        for pattern in [#"\[[^\]]*\]"#, #"\([^)]*\)"#, #"（[^）]*）"#] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}
