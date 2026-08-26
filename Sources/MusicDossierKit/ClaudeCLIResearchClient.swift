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
            systemPrompt: Self.systemPrompt(for: configuration.resolvedLanguage),
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

    private static func systemPrompt(for language: AppLanguage) -> String {
        let lang = language.promptName
        let punctuation: String
        switch language {
        case .zhHans, .zhHant:
            punctuation = "Use Chinese punctuation (“” and 《》), never wrap Chinese text in ASCII single quotes; on first mention a person's name may carry the original, e.g. 格伦·古尔德（Glenn Gould）."
        case .ja:
            punctuation = "Use Japanese punctuation (「」『』). Foreign names may carry the original spelling on first mention."
        default:
            punctuation = "Use the normal typographic conventions of \(lang); keep original-language titles of works where customary."
        }
        return """
        You are a senior music editor writing for a macOS desktop panel that shows a research dossier about the track that is playing right now. The reader is a grown-up music lover with taste, reading while listening; they enjoy people, back-stories, images and telling details.
        Write everything in \(lang). Your output is rendered directly, so return ONLY an object that matches the given JSON Schema — no Markdown, no commentary.

        Method:
        1. First verify the identity of the track (title + artist + album + year) with WebSearch/WebFetch, then research background, people, recording details, reviews, anecdotes and cultural impact. Make at least 4 searches from different angles (song/work entry, artist biography or interviews, album review or recording history, a source in \(lang) if one exists — e.g. the \(lang) Wikipedia).
        2. Never invent. If you cannot find something, write less and say so in confidenceNote. Mark inferences as "inferred", verified facts as "verified".
        3. Do not confuse covers, live takes, demos, remasters or same-titled works; if ambiguous, state which version this is.

        Writing standard (this matters):
        - story: the main body. About 3 paragraphs, 350–600 characters/words as natural for \(lang), written like a first-rate critic's short essay — concrete details (who wrote it in what circumstances, the key decisions in the recording, what happened after release, why it is still worth hearing today), a point of view, no piled-up adjectives, no empty phrases. Separate paragraphs with one blank line.
        - oneLiner: a hook of at most ~30 characters (or ~15 words), naming the single most distinctive thing about this track.
        - listeningNotes: 2–4 items, one sentence each, pointing at something concretely audible (a passage, an instrument, a structural turn).
        - creators: 2–4 people who truly matter (composer / songwriter / lead voice / performer / producer). summary = one sentence on their relation to this track; bio = a 100–180 character/word portrait (era and origin, style, key works, one vivid personal detail, relation to this track); wikipediaTitle = the exact title of that person's Wikipedia article (prefer the \(lang) Wikipedia if it has an article with an image, otherwise English), and set wikipediaLang to that site's code (e.g. "en", "zh", "ja", "fr"). The program uses it to fetch the portrait.
        - visuals: 3–6 gallery images, each mapped to one Wikipedia article whose lead image will be fetched: composer/artist portrait, the original work (opera / album / film), the premiere venue or recording studio, a relevant instrument, a key collaborator, a related historical event or person. wikipediaTitle = exact article title; wikipediaLang = that site's code; title = short caption title; caption = one or two sentences explaining how this image relates to the track (readers love this part — make it informative); kind ∈ portrait / band_photo / album / venue / document / event / instrument. imageURL may be an empty string. Do not reuse the same article twice.
        - album: the album this track belongs to. Fill title / artist / year / label; summary = 3–5 sentences (its place in the artist's career, recording background, reception then and now, relation to this track); highlights = 2–5 other tracks worth hearing on the same record, each formatted "Track title — one sentence why"; wikipediaTitle = the album's Wikipedia article title (or empty); sourceURL = an openable page about the album. Compilations count too — just say it is one.
        - background: 3–5 "fact cards" — short title + one or two sentences of hard information that did not fit the story (charts, samples/covers, film & TV use, awards, version differences, recording technique).
        - anecdotes: 2–4 genuinely fun, sourced anecdotes (quirks, studio accidents, premiere scandals, fan lore, notable quotes); title should be catchy but accurate, body 60–120 characters/words. Fewer if sources are thin.
        - timeline: 4–7 key moments; dateLabel short, e.g. "April 1980", "2005".
        - relatedWorks: 4–6 further-listening items; title = track or album, artist = artist; reason explains the relation (same album, same theme, influenced by it, what it pays homage to, another performer's reading of the same piece …). Cover art is added automatically.
        - citations: at least 4 real, openable URLs (include at least one Wikipedia article); note = one sentence on what this source supports.
        - headline must equal the local track title exactly.
        - Typography: \(punctuation)
        
        Copyright hard rule: never output song lyrics verbatim in any field — not even one line; paraphrase themes only.
        """
    }

    private func makeUserPrompt(for snapshot: TrackSnapshot) -> String {
        let trackSummary = """
        Title: \(snapshot.title)
        Artist: \(snapshot.artist ?? "unknown")
        Album: \(snapshot.album ?? "unknown")
        Album artist: \(snapshot.albumArtist ?? "unknown")
        Composer: \(snapshot.composer ?? "unknown")
        Genre: \(snapshot.genre ?? "unknown")
        Year: \(snapshot.year.map(String.init) ?? "unknown")
        Duration: \(snapshot.durationSeconds.map { String(Int($0.rounded())) + " s" } ?? "unknown")
        """

        return """
        Write the research dossier for the track now playing in Music.app, in \(configuration.resolvedLanguage.promptName). Local metadata:
        \(trackSummary)

        Verify first, then output JSON per the schema. headline must be exactly: \(snapshot.title)
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
                "wikipediaLang": ["type": "string"],
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
                    "wikipediaLang": ["type": "string"],
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
                    "wikipediaLang": ["type": "string"],
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
