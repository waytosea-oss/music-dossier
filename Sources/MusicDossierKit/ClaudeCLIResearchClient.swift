import Foundation

/// 通过本机已登录的 Claude Code CLI（`claude -p`）做联网研究，输出结构化 JSON。
/// 默认模型 `claude-opus-4-8`，可在 config.json 的 `claudeModel` 覆盖。
public actor ClaudeCLIResearchClient {
    private let configuration: AppConfiguration
    private let workspaceURL: URL
    private let timeoutSeconds: TimeInterval

    public init(
        configuration: AppConfiguration,
        workspaceURL: URL,
        timeoutSeconds: TimeInterval = 300
    ) {
        self.configuration = configuration
        self.workspaceURL = workspaceURL
        self.timeoutSeconds = timeoutSeconds
    }

    public static func resolvedClaudeExecutablePath(
        configuredPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String? {
        if let configuredPath = configuredPath?.trimmedNonEmpty {
            let expanded = (configuredPath as NSString).expandingTildeInPath
            if fileManager.isExecutableFile(atPath: expanded) {
                return expanded
            }
        }

        let home = fileManager.homeDirectoryForCurrentUser.path
        let fixedCandidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        for candidate in fixedCandidates where fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }

        let searchPaths = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        for directory in searchPaths {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("claude").path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    public func buildDossier(for snapshot: TrackSnapshot) async throws -> ResearchDossier {
        guard let claudePath = Self.resolvedClaudeExecutablePath(configuredPath: configuration.claudeExecutablePath) else {
            throw MusicDossierError.invalidConfiguration("没有找到可用的 Claude Code CLI（claude）。请先安装并登录。")
        }

        try? FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        // 网络抖动（"Connection closed mid-response" 之类）会让 CLI 半途报错，这里最多重试 2 次。
        var lastError: Error?
        for attempt in 1 ... maxAttempts {
            do {
                return try await runOnce(claudePath: claudePath, snapshot: snapshot, attempt: attempt)
            } catch let error as MusicDossierError where Self.isTransient(error) && attempt < maxAttempts {
                lastError = error
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: UInt64(3 * attempt) * 1_000_000_000)
            }
        }
        throw lastError ?? MusicDossierError.network("Claude CLI 多次尝试均失败。")
    }

    private let maxAttempts = 3

    private static func isTransient(_ error: MusicDossierError) -> Bool {
        let text = String(describing: error).lowercased()
        return text.contains("connection closed")
            || text.contains("mid-response")
            || text.contains("api_error")
            || text.contains("overloaded")
            || text.contains("529")
            || text.contains("timed out")
            || text.contains("没有返回可解析的结果")
    }

    private func runOnce(claudePath: String, snapshot: TrackSnapshot, attempt: Int) async throws -> ResearchDossier {
        let result = try await runClaude(
            executablePath: claudePath,
            systemPrompt: Self.systemPrompt,
            userPrompt: makeUserPrompt(for: snapshot)
        )

        Self.writeRunLog(result, workspaceURL: workspaceURL, snapshot: snapshot, attempt: attempt)

        guard let root = Self.parseResultFrame(result.output) else {
            let stderr = result.errorOutput.trimmedNonEmpty ?? "无错误输出"
            let stdoutTail = String(result.output.suffix(600))
            throw MusicDossierError.decoding("Claude CLI 没有返回可解析的结果。exit=\(result.exitCode) stderr=\(stderr) stdout=\(stdoutTail)")
        }

        if let isError = root["is_error"] as? Bool, isError {
            let message = (root["result"] as? String)?.trimmedNonEmpty ?? "未知错误"
            throw MusicDossierError.network("Claude CLI 报错：\(message)")
        }

        let dossierData: Data
        if let structured = root["structured_output"] as? [String: Any] {
            dossierData = try JSONSerialization.data(withJSONObject: structured)
        } else if let text = (root["result"] as? String)?.trimmedNonEmpty {
            let cleaned = Self.stripCodeFence(text)
            guard let data = cleaned.data(using: .utf8) else {
                throw MusicDossierError.decoding("Claude CLI 返回的文本不是 UTF-8")
            }
            dossierData = data
        } else {
            throw MusicDossierError.decoding("Claude CLI 结果里没有 structured_output 或 result 字段。")
        }

        do {
            let dossier = try JSONCoding.makeDecoder().decode(ResearchDossier.self, from: dossierData)
            return Self.normalizeHeadline(dossier, to: snapshot.title)
        } catch {
            let raw = String(data: dossierData, encoding: .utf8) ?? ""
            throw MusicDossierError.decoding("Claude 研究档案解码失败：\(error.localizedDescription)\n原始输出：\(raw.prefix(1200))")
        }
    }

    // MARK: - Prompt

    private static let systemPrompt = """
    你是一位资深的中文音乐编辑，为一款 macOS 桌面小窗写“正在播放这首歌”的研究档案。读者是一位有品味的成年乐迷，边听歌边看，喜欢人物故事、创作背景、图片和有趣的细节。
    你的输出会被直接渲染成页面，所以只输出符合给定 JSON Schema 的对象，简体中文，不要 Markdown。

    工作方法：
    1. 先用 WebSearch/WebFetch 核实歌曲身份（歌名 + 艺人 + 专辑 + 年份），再查创作背景、人物、录制细节、乐评、轶事与文化影响。至少做 4 次不同角度的搜索（歌曲/作品词条、艺人生平与访谈、专辑评论或录音史、中文乐评或维基百科中文条目）。
    2. 严禁编造。搜不到就少写，并在 confidenceNote 说明。推断内容标 inferred，确证内容标 verified。
    3. 不要把翻唱、live、demo、remaster、同名异曲混为一谈；如有歧义，写清楚是哪个版本。

    写作标准（关键）：
    - story：页面主体，3 段左右、350–600 字的中文编辑手记，像高水平乐评人写的短文——有具体细节（谁在什么处境下写的、录音时的关键选择、发行后发生了什么、为什么今天仍值得听），有观点，不堆形容词，不写空话。段落之间用一个空行分隔。
    - oneLiner：30 字以内的引子，点出这首歌最独特的一点。
    - listeningNotes：2–4 条“听点”，每条一句话，指向具体可以听到的东西。
    - album：这首歌所属专辑的介绍。title/artist/year/label 照实填；summary 写 3–5 句（这张专辑在艺人生涯中的位置、录制背景、当年反响或后世评价、与本曲的关系）；highlights 列 2–5 首同专辑其他值得听的曲目，每条格式“曲名 — 一句话为什么值得听”；wikipediaTitle 给专辑英文维基条目名（没有就空字符串）；sourceURL 给一个可打开的专辑介绍页。合辑/精选集也照写，说明它是合辑即可。
    - creators：2–4 个真正重要的人（作曲/词曲/主唱/演奏者/制作人）。summary 一句话说此人与这首歌的关系；bio 是 100–180 字的人物小传（出身年代、风格标签、代表作、一个鲜明的个人细节、与本曲的关系）；wikipediaTitle 必须给出该人物**英文维基百科词条的准确标题**（如 "Glenn Gould"、"Richard Wagner"、"Thom Yorke"），程序会用它取人物照片；若只有中文条目，给中文标题并把 wikipediaLang 设为 "zh"。
    - visuals：3–6 张“图集”，每张对应一个维基百科词条（程序会取该词条的首图）：例如作曲家/艺人肖像、原作（歌剧/专辑/电影）词条、首演剧院或录音地点、相关乐器、关键合作者、与本曲有关的历史事件或人物。wikipediaTitle 写准确的英文条目标题；title 是图片小标题；caption 一两句话说明这张图与这首歌的关系（这是读者最爱看的部分，要写出信息量）；kind 用 portrait/band_photo/album/venue/document/event/instrument 之一。imageURL 可以留空字符串。不要重复选同一个词条。
    - background：3–5 条“要点卡”，title 短标题、body 一两句话，写 story 里放不下的硬信息（榜单成绩、被谁采样/翻唱、影视使用、奖项、版本差异、录音技术细节等）。
    - anecdotes：2–4 条真正好玩、有来源的轶事（人物怪癖、录音室意外、首演风波、乐迷传说、名人评价……），每条 title 像标题党一样吸引人但准确，body 60–120 字。没有可靠来源就少写。
    - timeline：4–7 个关键节点，dateLabel 用“1980年4月”“2005”这类简洁写法。
    - relatedWorks：4–6 首延伸聆听，title 是曲名或专辑名、artist 是艺人；reason 说清和这首歌的关系（同专辑、同题材、被它影响、它致敬的对象、同一演奏者的对照版本等）。程序会自动补封面。
    - citations：至少 4 条真实可打开的 URL（含至少 1 条维基百科），note 一句话说这条来源支撑了什么。
    - headline 必须与本地曲目标题一致。
    - 排版细节：引号用中文“”和《》，不要用英文单引号 ' 包裹中文；人名首次出现可附原文，如“格伦·古尔德（Glenn Gould）”。
    """

    private func makeUserPrompt(for snapshot: TrackSnapshot) -> String {
        let trackSummary = """
        标题: \(snapshot.title)
        艺人: \(snapshot.artist ?? "未知")
        专辑: \(snapshot.album ?? "未知")
        专辑艺人: \(snapshot.albumArtist ?? "未知")
        作曲: \(snapshot.composer ?? "未知")
        类型: \(snapshot.genre ?? "未知")
        年份: \(snapshot.year.map(String.init) ?? "未知")
        时长: \(snapshot.durationSeconds.map { String(Int($0.rounded())) + " 秒" } ?? "未知")
        """

        return """
        请为 Music.app 里正在播放的这首歌写研究档案。本地元数据如下：
        \(trackSummary)

        先搜索核实，再按 Schema 输出 JSON。headline 必须严格等于：\(snapshot.title)
        """
    }

    // MARK: - JSON Schema

    private static var confidenceSchema: [String: Any] { ["type": "string", "enum": ["verified", "inferred"]] }

    private static func objectSchema(_ properties: [String: Any]) -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": Array(properties.keys).sorted(),
            "properties": properties,
        ]
    }

    static func makeJSONSchema() -> [String: Any] {
        let fact = objectSchema(["title": ["type": "string"], "body": ["type": "string"], "confidence": confidenceSchema])
        return objectSchema([
            "headline": ["type": "string"],
            "oneLiner": ["type": "string"],
            "story": ["type": "string"],
            "listeningNotes": ["type": "array", "items": ["type": "string"]],
            "album": objectSchema([
                "title": ["type": "string"],
                "artist": ["type": "string"],
                "year": ["type": "string"],
                "label": ["type": "string"],
                "summary": ["type": "string"],
                "highlights": ["type": "array", "items": ["type": "string"]],
                "wikipediaTitle": ["type": "string"],
                "wikipediaLang": ["type": "string", "enum": ["en", "zh"]],
                "sourceURL": ["type": "string"],
                "confidence": confidenceSchema,
            ]),
            "visuals": [
                "type": "array",
                "items": objectSchema([
                    "title": ["type": "string"],
                    "subject": ["type": "string"],
                    "caption": ["type": "string"],
                    "kind": ["type": "string"],
                    "wikipediaTitle": ["type": "string"],
                    "wikipediaLang": ["type": "string", "enum": ["en", "zh"]],
                    "imageURL": ["type": "string"],
                    "sourceURL": ["type": "string"],
                    "confidence": confidenceSchema,
                ]),
            ],
            "creators": [
                "type": "array",
                "items": objectSchema([
                    "name": ["type": "string"],
                    "role": ["type": "string"],
                    "summary": ["type": "string"],
                    "bio": ["type": "string"],
                    "wikipediaTitle": ["type": "string"],
                    "wikipediaLang": ["type": "string", "enum": ["en", "zh"]],
                    "confidence": confidenceSchema,
                ]),
            ],
            "background": ["type": "array", "items": fact],
            "anecdotes": ["type": "array", "items": fact],
            "timeline": [
                "type": "array",
                "items": objectSchema([
                    "dateLabel": ["type": "string"],
                    "title": ["type": "string"],
                    "body": ["type": "string"],
                    "confidence": confidenceSchema,
                ]),
            ],
            "relatedWorks": [
                "type": "array",
                "items": objectSchema([
                    "title": ["type": "string"],
                    "artist": ["type": "string"],
                    "reason": ["type": "string"],
                    "confidence": confidenceSchema,
                ]),
            ],
            "confidenceNote": ["type": "string"],
            "citations": [
                "type": "array",
                "items": objectSchema([
                    "title": ["type": "string"],
                    "url": ["type": "string"],
                    "publisher": ["type": "string"],
                    "note": ["type": "string"],
                    "confidence": confidenceSchema,
                ]),
            ],
        ])
    }

    // MARK: - Process

    private func runClaude(executablePath: String, systemPrompt: String, userPrompt: String) async throws -> ShellResult {
        try Task.checkCancellation()
        let schemaData = try JSONSerialization.data(withJSONObject: Self.makeJSONSchema(), options: [.sortedKeys])
        let schemaString = String(decoding: schemaData, as: UTF8.self)

        let arguments = [
            "-p",
            "--model", configuration.resolvedClaudeModel,
            "--effort", configuration.resolvedClaudeEffort,
            "--output-format", "json",
            "--json-schema", schemaString,
            "--tools", "WebSearch,WebFetch",
            "--allowedTools", "WebSearch,WebFetch",
            "--setting-sources", "",
            "--max-turns", "40",
            "--system-prompt", systemPrompt,
            userPrompt,
        ]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.currentDirectoryURL = workspaceURL
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extraPath = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        let currentPath = environment["PATH"] ?? ""
        environment["PATH"] = (extraPath + currentPath.split(separator: ":").map(String.init))
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .joined(separator: ":")
        environment["TERM"] = "dumb"
        environment["HOME"] = environment["HOME"] ?? home
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice

        let timeout = timeoutSeconds
        let gate = CompletionGate()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ShellResult, Error>) in
                process.terminationHandler = { process in
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    guard gate.tryFinish() else { return }
                    continuation.resume(returning: ShellResult(
                        output: String(data: outputData, encoding: .utf8) ?? "",
                        errorOutput: String(data: errorData, encoding: .utf8) ?? "",
                        exitCode: process.terminationStatus
                    ))
                }

                do {
                    try process.run()
                } catch {
                    guard gate.tryFinish() else { return }
                    continuation.resume(throwing: error)
                    return
                }

                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if !gate.isFinished, process.isRunning {
                        process.terminate()
                    }
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private final class CompletionGate: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false

        var isFinished: Bool {
            lock.lock(); defer { lock.unlock() }
            return finished
        }

        /// 第一次调用返回 true，之后都返回 false。
        func tryFinish() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if finished { return false }
            finished = true
            return true
        }
    }

    // MARK: - Diagnostics

    /// 把最近一次 CLI 调用的退出码 / stderr / stdout 尾部写到 workspace/last-run.log，方便排查。
    private static func writeRunLog(_ result: ShellResult, workspaceURL: URL, snapshot: TrackSnapshot, attempt: Int) {
        let logURL = workspaceURL.appendingPathComponent("last-run.log", isDirectory: false)
        let text = """
        time: \(DateFormatting.displayString(from: .now))
        attempt: \(attempt)
        track: \(snapshot.title) — \(snapshot.artist ?? "")
        exit: \(result.exitCode)
        --- stderr ---
        \(result.errorOutput.suffix(4000))
        --- stdout (tail) ---
        \(result.output.suffix(4000))

        """
        try? text.write(to: logURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Parsing

    /// `--output-format json` 正常只输出一个 JSON 对象；保险起见，取最后一个能解析出 type=result 的对象。
    private static func parseResultFrame(_ stdout: String) -> [String: Any]? {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            return object
        }

        var last: [String: Any]?
        for rawLine in trimmed.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("{"), let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if (object["type"] as? String) == "result" || object["result"] != nil || object["structured_output"] != nil {
                last = object
            }
        }
        return last
    }

    private static func stripCodeFence(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.replacingOccurrences(of: "^```[a-zA-Z0-9_-]*\\n", with: "", options: .regularExpression)
            cleaned = cleaned.replacingOccurrences(of: "\\n```$", with: "", options: .regularExpression)
        }
        return cleaned
    }

    private static func normalizeHeadline(_ dossier: ResearchDossier, to title: String) -> ResearchDossier {
        guard dossier.headline != title else { return dossier }
        return ResearchDossier(
            headline: title,
            oneLiner: dossier.oneLiner,
            story: dossier.story,
            listeningNotes: dossier.listeningNotes,
            album: dossier.album,
            visuals: dossier.visuals,
            creators: dossier.creators,
            background: dossier.background,
            anecdotes: dossier.anecdotes,
            timeline: dossier.timeline,
            relatedWorks: dossier.relatedWorks,
            confidenceNote: dossier.confidenceNote,
            citations: dossier.citations
        )
    }
}
