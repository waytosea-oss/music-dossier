import Foundation

public actor OpenAIResearchClient {
    private let configuration: AppConfiguration
    private let session: URLSession

    public init(configuration: AppConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func buildDossier(for snapshot: TrackSnapshot) async throws -> ResearchDossier {
        guard
            let apiKey = configuration.openAIAPIKey?.trimmedNonEmpty,
            apiKey != "sk-your-key-here"
        else {
            throw MusicDossierError.missingAPIKey
        }

        guard let url = URL(string: configuration.openAIBaseURL) else {
            throw MusicDossierError.invalidConfiguration("OpenAI Responses URL 无效")
        }

        let systemPrompt = """
        你是一名音乐研究编辑，负责生成简体中文的结构化档案页面数据。
        你的目标不是写成散文，而是写成可以直接渲染成信息图页面的 JSON。
        所有事实必须尽量由搜索结果支撑；如果是合理推断，要明确标记为 inferred。
        任何来源都不要编造。至少返回 3 条 citations。不要返回 Markdown，不要返回 HTML。
        最重要的约束是“不要错认歌曲”：
        1. 必须优先依据 title + artist + album 组合确认对象。
        2. 不要把翻唱、live、remaster、demo、同名异曲、同名专辑混为一谈。
        3. 如果无法确认就是这首歌，就保持保守：不要编背景，不要编轶事，可以返回空数组，并在 confidenceNote 里明确写“存在歧义/待确认”。
        4. 不确定时，绝对不要把猜测写成 verified。
        5. headline 必须与本地曲目标题保持一致，不要替换成别的歌名。
        6. anecdotes 如果没有可靠来源支撑，可以为空。
        7. visuals 只收录可直接使用的图片，不要返回网页 URL 冒充图片 URL；优先返回人物肖像、乐队合照、档案照，避免重复返回专辑封面。
        """

        let trackSummary = """
        标题: \(snapshot.title)
        艺人: \(snapshot.artist ?? "未知")
        专辑: \(snapshot.album ?? "未知")
        专辑艺人: \(snapshot.albumArtist ?? "未知")
        作曲: \(snapshot.composer ?? "未知")
        类型: \(snapshot.genre ?? "未知")
        年份: \(snapshot.year.map(String.init) ?? "未知")
        时长秒数: \(snapshot.durationSeconds.map { String(Int($0.rounded())) } ?? "未知")
        Music 持久 ID: \(snapshot.persistentId ?? "无")
        Music 数据库 ID: \(snapshot.databaseId.map(String.init) ?? "无")
        """

        let userPrompt = """
        请围绕这首歌整理一个研究档案风的信息页内容，面向中文读者。
        页面应突出：作品介绍、主要创作者/乐队成员、创作背景、人物轶事、时间线、延伸作品、来源、可用人物图片。
        每个段落都写得简洁但信息密度高，避免空话。
        如果搜索结果互相冲突，宁可减少内容，也不要写错。
        headline 必须直接使用这首歌在本地播放器中的标题：\(snapshot.title)
        visuals 最多返回 3 条：
        1. imageURL 必须是图片直链，最好是 jpg/png/webp/gif，不要 svg，不要网页地址。
        2. sourceURL 是这张图所属的文章、词条或官方页面。
        3. title 用于页面小标题，subject 写人物或乐队名，caption 用一句话说明为何值得看。
        4. 如果没有可靠可用的图，就返回空数组，不要编造。

        \(trackSummary)
        """

        let requestBody = makeRequestBody(systemPrompt: systemPrompt, userPrompt: userPrompt)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MusicDossierError.network("OpenAI 响应不可识别")
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw MusicDossierError.network("OpenAI \(httpResponse.statusCode): \(message)")
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MusicDossierError.decoding("OpenAI 响应不是对象")
        }

        guard let outputText = Self.extractOutputText(from: root)?.trimmedNonEmpty else {
            throw MusicDossierError.decoding("OpenAI 未返回 output_text")
        }

        let cleaned = Self.stripCodeFence(outputText)
        guard let dossierData = cleaned.data(using: .utf8) else {
            throw MusicDossierError.decoding("OpenAI output_text 不是 UTF-8")
        }

        do {
            let dossier = try JSONCoding.makeDecoder().decode(ResearchDossier.self, from: dossierData)
            if dossier.citations.count < 3 {
                throw MusicDossierError.decoding("citation 少于 3 条")
            }
            return dossier
        } catch {
            throw MusicDossierError.decoding("ResearchDossier 解码失败：\(error.localizedDescription)\n原始输出：\(cleaned)")
        }
    }

    private func makeRequestBody(systemPrompt: String, userPrompt: String) -> [String: Any] {
        [
            "model": configuration.openAIModel,
            "reasoning": [
                "effort": "low",
            ],
            "tools": [
                [
                    "type": "web_search_preview",
                    "search_context_size": "medium",
                ],
            ],
            "include": [
                "web_search_call.action.sources",
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "music_research_dossier",
                    "strict": true,
                    "schema": Self.makeJSONSchema(),
                ],
            ],
            "input": [
                [
                    "role": "system",
                    "content": [
                        [
                            "type": "input_text",
                            "text": systemPrompt,
                        ],
                    ],
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": userPrompt,
                        ],
                    ],
                ],
            ],
        ]
    }

    private static func extractOutputText(from root: [String: Any]) -> String? {
        if let outputText = root["output_text"] as? String, !outputText.isEmpty {
            return outputText
        }

        guard let output = root["output"] as? [[String: Any]] else {
            return nil
        }

        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content {
                if let text = part["text"] as? String, !text.isEmpty {
                    return text
                }
            }
        }

        return nil
    }

    private static func stripCodeFence(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.replacingOccurrences(of: "^```[a-zA-Z0-9_-]*\\n", with: "", options: .regularExpression)
            cleaned = cleaned.replacingOccurrences(of: "\\n```$", with: "", options: .regularExpression)
        }
        return cleaned
    }

    private static func makeJSONSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": [
                "headline",
                "oneLiner",
                "visuals",
                "creators",
                "background",
                "anecdotes",
                "timeline",
                "relatedWorks",
                "confidenceNote",
                "citations",
            ],
            "properties": [
                "headline": ["type": "string"],
                "oneLiner": ["type": "string"],
                "visuals": [
                    "type": "array",
                    "maxItems": 3,
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["title", "subject", "caption", "kind", "imageURL", "sourceURL", "confidence"],
                        "properties": [
                            "title": ["type": "string"],
                            "subject": ["type": "string"],
                            "caption": ["type": "string"],
                            "kind": ["type": "string"],
                            "imageURL": ["type": "string"],
                            "sourceURL": ["type": "string"],
                            "confidence": ["type": "string", "enum": ["verified", "inferred"]],
                        ],
                    ],
                ],
                "creators": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["name", "role", "summary", "confidence"],
                        "properties": [
                            "name": ["type": "string"],
                            "role": ["type": "string"],
                            "summary": ["type": "string"],
                            "confidence": ["type": "string", "enum": ["verified", "inferred"]],
                        ],
                    ],
                ],
                "background": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["title", "body", "confidence"],
                        "properties": [
                            "title": ["type": "string"],
                            "body": ["type": "string"],
                            "confidence": ["type": "string", "enum": ["verified", "inferred"]],
                        ],
                    ],
                ],
                "anecdotes": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["title", "body", "confidence"],
                        "properties": [
                            "title": ["type": "string"],
                            "body": ["type": "string"],
                            "confidence": ["type": "string", "enum": ["verified", "inferred"]],
                        ],
                    ],
                ],
                "timeline": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["dateLabel", "title", "body", "confidence"],
                        "properties": [
                            "dateLabel": ["type": "string"],
                            "title": ["type": "string"],
                            "body": ["type": "string"],
                            "confidence": ["type": "string", "enum": ["verified", "inferred"]],
                        ],
                    ],
                ],
                "relatedWorks": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["title", "artist", "reason", "confidence"],
                        "properties": [
                            "title": ["type": "string"],
                            "artist": ["type": "string"],
                            "reason": ["type": "string"],
                            "confidence": ["type": "string", "enum": ["verified", "inferred"]],
                        ],
                    ],
                ],
                "confidenceNote": ["type": "string"],
                "citations": [
                    "type": "array",
                    "minItems": 3,
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["title", "url", "publisher", "note", "confidence"],
                        "properties": [
                            "title": ["type": "string"],
                            "url": ["type": "string"],
                            "publisher": ["type": "string"],
                            "note": ["type": "string"],
                            "confidence": ["type": "string", "enum": ["verified", "inferred"]],
                        ],
                    ],
                ],
            ],
        ]
    }
}
