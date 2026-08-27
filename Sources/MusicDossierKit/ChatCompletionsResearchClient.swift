import Foundation

/// 国产/通用大模型引擎：走 OpenAI 兼容的 Chat Completions 接口。
/// 模型不联网也没关系——应用先用 WikipediaContextFetcher 抓资料包，模型只负责写。
public actor ChatCompletionsResearchClient {

    /// 内置服务商预设。小白只需选一个、贴 Key。
    public struct ProviderPreset: Sendable {
        public let id: String
        public let displayName: String
        public let baseURL: String          // chat completions 完整地址
        public let defaultModel: String
        public let keyURL: String           // 去哪申请 Key
        public let supportsJSONMode: Bool
    }

    public static let presets: [ProviderPreset] = [
        .init(id: "deepseek", displayName: "DeepSeek 深度求索",
              baseURL: "https://api.deepseek.com/v1/chat/completions",
              defaultModel: "deepseek-chat",
              keyURL: "https://platform.deepseek.com/api_keys", supportsJSONMode: true),
        .init(id: "qwen", displayName: "通义千问（阿里）",
              baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
              defaultModel: "qwen-plus",
              keyURL: "https://bailian.console.aliyun.com/?apiKey=1", supportsJSONMode: true),
        .init(id: "kimi", displayName: "Kimi（月之暗面）",
              baseURL: "https://api.moonshot.cn/v1/chat/completions",
              defaultModel: "kimi-k2-0905-preview",
              keyURL: "https://platform.moonshot.cn/console/api-keys", supportsJSONMode: true),
        .init(id: "glm", displayName: "智谱 GLM（推荐：5.3-Flash 快且便宜）",
              baseURL: "https://open.bigmodel.cn/api/paas/v4/chat/completions",
              defaultModel: "glm-5.3-flash",
              keyURL: "https://open.bigmodel.cn/usercenter/apikeys", supportsJSONMode: false),
        .init(id: "openai-chat", displayName: "OpenAI（Chat Completions）",
              baseURL: "https://api.openai.com/v1/chat/completions",
              defaultModel: "gpt-5.4-mini",
              keyURL: "https://platform.openai.com/api-keys", supportsJSONMode: true),
        .init(id: "custom", displayName: "自定义（OpenAI 兼容）",
              baseURL: "", defaultModel: "", keyURL: "", supportsJSONMode: false),
    ]

    public static func preset(id: String?) -> ProviderPreset? {
        presets.first { $0.id == id?.trimmedNonEmpty?.lowercased() }
    }

    private let configuration: AppConfiguration
    private let session: URLSession

    public init(configuration: AppConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    private var resolved: (baseURL: String, model: String, key: String)? {
        guard let key = configuration.apiKey?.trimmedNonEmpty else { return nil }
        if let preset = Self.preset(id: configuration.apiProvider), preset.id != "custom" {
            return (configuration.apiBaseURL?.trimmedNonEmpty ?? preset.baseURL,
                    configuration.apiModel?.trimmedNonEmpty ?? preset.defaultModel, key)
        }
        guard let base = configuration.apiBaseURL?.trimmedNonEmpty,
              let model = configuration.apiModel?.trimmedNonEmpty else { return nil }
        return (base, model, key)
    }

    public var isConfigured: Bool { resolved != nil }

    public func buildDossier(for snapshot: TrackSnapshot) async throws -> ResearchDossier {
        guard let (baseURL, model, key) = resolved else {
            throw MusicDossierError.invalidConfiguration("尚未配置 API 服务商或 Key。请在「设置」里选择服务商并粘贴 API Key。")
        }
        let language = configuration.resolvedLanguage

        // 1. 应用侧检索资料包
        let fetcher = WikipediaContextFetcher(language: language, session: session)
        let context = await fetcher.fetchContext(for: snapshot)
        let contextText = WikipediaContextFetcher.renderContext(context)

        // 2. 组 prompt（复用 Claude 引擎的 JSON 骨架约定）
        let schemaData = try JSONSerialization.data(withJSONObject: ClaudeCLIResearchClient.makeJSONSchema(), options: [.sortedKeys])
        let schemaString = String(decoding: schemaData, as: UTF8.self)

        let systemPrompt = """
        你是一名资深音乐研究编辑，为一档"每首歌一份研究档案"的应用写内容，输出语言：\(language.promptName)。
        你只输出一个 JSON 对象（不带 markdown 代码块），字段必须符合下面的 JSON Schema：
        \(schemaString)

        写作纪律：
        1. 你没有联网能力。事实只能来自：用户提供的曲目元数据、下方检索资料包、以及你确有把握的公共音乐常识。
        2. 确凿的写 confidence="verified"，推断的写 "inferred"。宁可少写、标注推测，绝不编造具体日期、录音地点、人名事迹。
        3. headline 必须严格等于本地曲目标题。不要把翻唱、live、同名异曲混为一谈。
        4. story 为编辑手记：2-3 段、有细节有观点、给普通听众看。listeningNotes 2-4 条，讲耳朵该注意什么。
        5. creators 里 wikipediaTitle 填资料包对应的条目名（有就填，页面靠它抓人物照片）；visuals 同理，imageURL 一律留空字符串。
        6. citations 至少包含资料包里实际用到的 URL；没有可靠来源就少写内容。
        7. 版权红线：任何字段都绝对不要出现歌词原文（连一句都不行）；描述歌词只能用自己的话概述主题。
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
        """

        let userPrompt = """
        请为下面这首曲目写一份研究档案 JSON。

        本地元数据：
        \(trackSummary)

        \(contextText.isEmpty ? "（本次未检索到维基资料，请依据元数据与可靠常识保守撰写，多标 inferred。）" : contextText)
        """

        // 3. 调接口
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt],
            ],
            "temperature": 0.4,
            "max_tokens": 20000,
        ]
        if Self.preset(id: configuration.apiProvider)?.supportsJSONMode == true {
            body["response_format"] = ["type": "json_object"]
        }

        // 流式接收：长生成期间保持数据流动，避免网关/代理掐断空闲连接
        body["stream"] = true
        body["stream_options"] = ["include_usage": true]

        guard let url = URL(string: baseURL) else {
            throw MusicDossierError.invalidConfiguration("API 地址无效：\(baseURL)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 900

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MusicDossierError.network("API 响应不可识别")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            var text = ""
            for try await line in bytes.lines {
                text += line
                if text.count > 500 { break }
            }
            throw MusicDossierError.network(Self.friendlyHTTPError(status: http.statusCode, body: text))
        }

        var content = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let chunkData = payload.data(using: .utf8),
                  let chunk = try? JSONSerialization.jsonObject(with: chunkData) as? [String: Any],
                  let choices = chunk["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any]
            else { continue }
            if let piece = delta["content"] as? String {
                content += piece
            }
            if let usage = chunk["usage"] as? [String: Any],
               let total = usage["total_tokens"] as? Int, total > 0 {
                Self.logUsage(usage, model: model)
            }
        }
        guard content.trimmedNonEmpty != nil else {
            throw MusicDossierError.decoding("API 没有返回内容")
        }

        do {
            return try Self.decodeDossier(from: content)
        } catch {
            Self.dumpRawOutput(content, error: error)
            // 自动重试一次：把上次的问题反馈给模型
            let retryPrompt = userPrompt + "\n\n（你上一次的输出不是合法 JSON，解析报错：\(error.localizedDescription)。请重新输出：只输出一个严格合法的 JSON 对象，字符串内的换行必须写成 \\n，不要输出任何 JSON 之外的文字。）"
            let retryContent = try await streamOnce(baseURL: baseURL, key: key, model: model,
                                                    systemPrompt: systemPrompt, userPrompt: retryPrompt,
                                                    jsonMode: Self.preset(id: configuration.apiProvider)?.supportsJSONMode == true)
            do {
                return try Self.decodeDossier(from: retryContent)
            } catch {
                Self.dumpRawOutput(retryContent, error: error)
                throw MusicDossierError.decoding("档案解码失败（重试后仍失败）：\(error.localizedDescription)")
            }
        }
    }

    /// 单次流式调用，返回拼好的 content。
    private func streamOnce(baseURL: String, key: String, model: String,
                            systemPrompt: String, userPrompt: String, jsonMode: Bool) async throws -> String {
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt],
            ],
            "temperature": 0.3,
            "max_tokens": 20000,
            "stream": true,
            "stream_options": ["include_usage": true],
        ]
        if jsonMode { body["response_format"] = ["type": "json_object"] }
        guard let url = URL(string: baseURL) else { throw MusicDossierError.invalidConfiguration("API 地址无效") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 900
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw MusicDossierError.network("重试请求失败")
        }
        var content = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let chunkData = payload.data(using: .utf8),
                  let chunk = try? JSONSerialization.jsonObject(with: chunkData) as? [String: Any] else { continue }
            if let choices = chunk["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any],
               let piece = delta["content"] as? String { content += piece }
            if let usage = chunk["usage"] as? [String: Any],
               let total = usage["total_tokens"] as? Int, total > 0 { Self.logUsage(usage, model: model) }
        }
        return content
    }

    /// 解码：剥代码块 → 截取 JSON 对象 → 清洗常见毛病（裸控制字符、尾逗号）→ 严格解码
    static func decodeDossier(from content: String) throws -> ResearchDossier {
        let cleaned = stripCodeFence(content)
        guard var json = extractJSONObject(from: cleaned) else {
            throw MusicDossierError.decoding("模型输出不是 JSON：\(String(cleaned.prefix(200)))")
        }
        if let data = json.data(using: .utf8),
           let dossier = try? JSONCoding.makeDecoder().decode(ResearchDossier.self, from: data) {
            return dossier
        }
        // 清洗一：字符串字面量里的裸换行/裸制表符转义（思考型模型常见错误）
        json = sanitizeBareControlCharacters(in: json)
        // 清洗二：尾逗号
        json = json.replacingOccurrences(of: #",\s*([}\]])"#, with: "$1", options: .regularExpression)
        guard let data = json.data(using: .utf8) else {
            throw MusicDossierError.decoding("JSON 不是 UTF-8")
        }
        return try JSONCoding.makeDecoder().decode(ResearchDossier.self, from: data)
    }

    /// 把 JSON 字符串字面量内部的裸 \n \r \t 转成合法转义。
    static func sanitizeBareControlCharacters(in json: String) -> String {
        var out = String()
        out.reserveCapacity(json.count)
        var inString = false
        var escaped = false
        for ch in json {
            if inString {
                if escaped { out.append(ch); escaped = false; continue }
                switch ch {
                case "\\": out.append(ch); escaped = true
                case "\"": out.append(ch); inString = false
                case "\n": out.append("\\n")
                case "\r": out.append("\\r")
                case "\t": out.append("\\t")
                default: out.append(ch)
                }
            } else {
                if ch == "\"" { inString = true }
                out.append(ch)
            }
        }
        return out
    }

    private static func supportDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingDirectory("Library").appendingDirectory("Application Support").appendingDirectory("MusicDossier")
    }

    static func dumpRawOutput(_ content: String, error: Error) {
        let url = supportDirectory().appendingFile("last-api-output.txt")
        let text = "error: \(error.localizedDescription)\n---\n\(content)"
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    static func logUsage(_ usage: [String: Any], model: String) {
        let url = supportDirectory().appendingFile("api-usage.jsonl")
        var entry = usage
        entry["model"] = model
        entry["at"] = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: entry),
              let line = String(data: data, encoding: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write((line + "\n").data(using: .utf8)!)
            try? handle.close()
        } else {
            try? (line + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// 「测试连接」：发一个一句话请求，返回 nil 表示成功，否则返回给用户看的错误说明。
    public func testConnection() async -> String? {
        guard let (baseURL, model, key) = resolved else { return "还没有填写完整：需要选择服务商并粘贴 API Key。" }
        guard let url = URL(string: baseURL) else { return "API 地址无效" }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [["role": "user", "content": "回复：OK"]],
            "max_tokens": 512,
        ])
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return "响应不可识别" }
            if (200 ..< 300).contains(http.statusCode) {
                // 有的思考型模型在极小额度下 content 为空但 HTTP 200——只要 200 即视为连通
                return nil
            }
            return Self.friendlyHTTPError(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        } catch {
            return "网络错误：\(error.localizedDescription)"
        }
    }

    static func friendlyHTTPError(status: Int, body: String) -> String {
        switch status {
        case 401: return "API Key 不对或已失效（HTTP 401）。请回到服务商后台重新复制一遍 Key。"
        case 402: return "账户余额不足（HTTP 402）。请去服务商后台充值。"
        case 404: return "模型名或接口地址不对（HTTP 404）。试试恢复默认模型名。"
        case 429: return "请求太频繁或额度用完（HTTP 429）。稍等片刻再试。"
        default: return "服务商返回错误 HTTP \(status)：\(String(body.prefix(200)))"
        }
    }

    private static func stripCodeFence(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.replacingOccurrences(of: "^```[a-zA-Z0-9_-]*\\n", with: "", options: .regularExpression)
            cleaned = cleaned.replacingOccurrences(of: "\\n```$", with: "", options: .regularExpression)
        }
        return cleaned
    }

    /// 容错：截取第一个 { 到最后一个 } 之间的内容（有的模型爱在 JSON 前后加话）。
    private static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return String(text[start ... end])
    }
}
