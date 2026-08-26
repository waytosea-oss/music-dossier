import Foundation

/// 应用侧检索：从维基百科抓取曲目相关条目的摘要，作为资料包喂给不带联网搜索的模型。
/// 这样便宜模型也能"言之有据"，而不是靠它自己检索。
public struct WikipediaContextFetcher: Sendable {
    private let session: URLSession
    private let language: AppLanguage

    public init(language: AppLanguage, session: URLSession = .shared) {
        self.language = language
        self.session = session
    }

    public struct ContextEntry: Sendable {
        public let query: String
        public let resolvedTitle: String
        public let lang: String
        public let extract: String
        public let pageURL: String
    }

    /// 为一个曲目快照抓资料包。串行、限次，整体超时约 25 秒，抓不到就返回已有的部分。
    public func fetchContext(for snapshot: TrackSnapshot) async -> [ContextEntry] {
        var queries = [String]()
        func add(_ s: String?) {
            guard let s = s?.trimmedNonEmpty else { return }
            if !queries.contains(s) { queries.append(s) }
        }
        add(snapshot.artist)
        add(snapshot.albumArtist)
        add(snapshot.composer)
        add(snapshot.album)
        // 曲名去掉括号里的版本说明后也查一次（作品条目常以主标题存在）
        let bareTitle = snapshot.title
            .replacingOccurrences(of: #"\s*[\(\[（【][^\)\]）】]*[\)\]）】]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        add(bareTitle)

        let langs: [String] = {
            let primary = language.wikipediaLang
            return primary == "en" ? ["en"] : [primary, "en"]
        }()

        var results = [ContextEntry]()
        for query in queries.prefix(5) {
            for lang in langs {
                if let entry = await fetchSummary(query: query, lang: lang) {
                    results.append(entry)
                    break  // 该查询词拿到一个语言版本即可
                }
            }
        }
        return results
    }

    private func fetchSummary(query: String, lang: String) async -> ContextEntry? {
        // 先用搜索 API 解析条目名（容错别名、译名），再取摘要
        guard let searchURL = URL(string:
            "https://\(lang).wikipedia.org/w/api.php?action=query&list=search&srlimit=1&format=json&srsearch="
            + (query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query))
        else { return nil }

        guard let searchData = await get(searchURL),
              let root = try? JSONSerialization.jsonObject(with: searchData) as? [String: Any],
              let q = root["query"] as? [String: Any],
              let hits = q["search"] as? [[String: Any]],
              let first = hits.first,
              let title = first["title"] as? String
        else { return nil }

        guard let sumURL = URL(string:
            "https://\(lang).wikipedia.org/api/rest_v1/page/summary/"
            + (title.replacingOccurrences(of: " ", with: "_")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title))
        else { return nil }

        guard let data = await get(sumURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let extract = (obj["extract"] as? String)?.trimmedNonEmpty
        else { return nil }

        let pageURL = ((obj["content_urls"] as? [String: Any])?["desktop"] as? [String: Any])?["page"] as? String
            ?? "https://\(lang).wikipedia.org/wiki/\(title)"
        return ContextEntry(query: query, resolvedTitle: title, lang: lang,
                            extract: String(extract.prefix(1600)), pageURL: pageURL)
    }

    private func get(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("MusicDossier/1.0 (https://github.com/waytosea-oss/music-dossier)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode)
        else { return nil }
        return data
    }

    /// 拼成给模型看的资料包文本。
    public static func renderContext(_ entries: [ContextEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        var lines = ["以下是从维基百科检索到的资料（可信来源，可在 citations 中引用其 URL）："]
        for (i, e) in entries.enumerated() {
            lines.append("")
            lines.append("【资料 \(i + 1)】\(e.resolvedTitle)（\(e.lang) 维基百科，检索词：\(e.query)）")
            lines.append("URL: \(e.pageURL)")
            lines.append(e.extract)
        }
        return lines.joined(separator: "\n")
    }
}
