import Foundation

/// 通过维基百科 REST API 取词条首图（及词条页链接）。图片来自 Wikimedia Commons，可信且稳定。
public enum WikipediaImageResolver {
    public struct Resolved: Sendable {
        /// 首选图片 URL（按优先级排列的候选，下载时依次尝试）
        public let imageCandidates: [String]
        public var imageURL: String { imageCandidates.first ?? "" }
        public let pageURL: String
        public let title: String
        public let extract: String
    }

    private static let userAgent = "MusicDossier/1.1 (macOS; personal research widget)"

    public static func resolve(
        title rawTitle: String,
        lang rawLang: String? = nil,
        fallbackLang: String? = nil,
        session: URLSession = .shared
    ) async -> Resolved? {
        guard let title = rawTitle.trimmedNonEmpty else { return nil }
        let langs = preferredLangs(rawLang, fallbackLang: fallbackLang)
        for lang in langs {
            if let resolved = await fetchSummary(title: title, lang: lang, session: session) {
                return resolved
            }
        }
        return nil
    }

    private static func preferredLangs(_ rawLang: String?, fallbackLang: String?) -> [String] {
        var ordered: [String] = []
        func push(_ value: String?) {
            guard var code = value?.trimmedNonEmpty?.lowercased() else { return }
            if code.hasPrefix("zh") { code = "zh" }
            code = String(code.split(separator: "-").first ?? Substring(code))
            if !ordered.contains(code) { ordered.append(code) }
        }
        push(rawLang)      // 模型指定的词条语言
        push(fallbackLang) // 应用语言
        push("en")
        return ordered
    }

    private static func fetchSummary(title: String, lang: String, session: URLSession) async -> Resolved? {
        let normalized = title.replacingOccurrences(of: " ", with: "_")
        guard let encoded = normalized.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))),
              let url = URL(string: "https://\(lang).wikipedia.org/api/rest_v1/page/summary/\(encoded)?redirect=true")
        else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // 消歧义页没有意义
        if (root["type"] as? String) == "disambiguation" { return nil }

        let pageURL = ((root["content_urls"] as? [String: Any])?["desktop"] as? [String: Any])?["page"] as? String
            ?? "https://\(lang).wikipedia.org/wiki/\(encoded)"
        let displayTitle = (root["title"] as? String) ?? title
        let extract = (root["extract"] as? String) ?? ""

        var candidates: [String] = []
        let original = (root["originalimage"] as? [String: Any])
        let originalURL = original?["source"] as? String
        let originalWidth = original?["width"] as? Int ?? 0
        if let thumb = (root["thumbnail"] as? [String: Any])?["source"] as? String {
            // 放大缩略图，但不能超过原图宽度（超过会 400）
            let target = originalWidth > 0 ? min(900, originalWidth) : 640
            let upscaled = upscaledThumbnail(thumb, width: target)
            candidates.append(upscaled)
            candidates.append(stripTracking(thumb))
        }
        if let originalURL, originalWidth <= 3000 {
            candidates.append(stripTracking(originalURL))
        }
        candidates = candidates.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        guard !candidates.isEmpty else { return nil }
        if candidates.allSatisfy({ $0.lowercased().contains(".svg") }) { return nil }

        return Resolved(imageCandidates: candidates.filter { !$0.lowercased().contains(".svg") }, pageURL: pageURL, title: displayTitle, extract: extract)
    }

    /// 缩略图 URL 形如 …/thumb/x/xy/File.jpg/330px-File.jpg，把 330px 换成更大的尺寸。
    private static func upscaledThumbnail(_ url: String, width: Int) -> String {
        let cleaned = stripTracking(url)
        guard let regex = try? NSRegularExpression(pattern: #"/(\d{2,4})px-"#) else { return cleaned }
        let range = NSRange(cleaned.startIndex ..< cleaned.endIndex, in: cleaned)
        return regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "/\(width)px-")
    }

    private static func stripTracking(_ url: String) -> String {
        guard var components = URLComponents(string: url) else { return url }
        components.query = nil
        return components.url?.absoluteString ?? url
    }
}
