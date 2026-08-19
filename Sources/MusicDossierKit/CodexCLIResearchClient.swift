import Foundation

public actor CodexCLIResearchClient {
    private let configuration: AppConfiguration
    private let workspaceURL: URL

    public init(configuration: AppConfiguration, workspaceURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.configuration = configuration
        self.workspaceURL = workspaceURL
    }

    public static func resolvedCodexExecutablePath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String? {
        let bundledPath = "/Applications/Codex.app/Contents/Resources/codex"
        if fileManager.isExecutableFile(atPath: bundledPath) {
            return bundledPath
        }

        let searchPaths = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        for directory in searchPaths {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("codex").path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    public func buildDossier(for snapshot: TrackSnapshot) async throws -> ResearchDossier {
        guard let codexPath = Self.resolvedCodexExecutablePath() else {
            throw MusicDossierError.invalidConfiguration("没有找到可用的 Codex CLI。")
        }

        let result = try await runCodexExec(
            executablePath: codexPath,
            prompt: makePrompt(for: snapshot)
        )

        guard let outputText = Self.extractFinalMessage(from: result.output)?.trimmedNonEmpty else {
            let stderr = result.errorOutput.trimmedNonEmpty ?? "无错误输出"
            throw MusicDossierError.decoding("Codex CLI 没有返回可解析的研究内容。stderr=\(stderr)")
        }

        let cleaned = Self.stripCodeFence(outputText)
        guard let data = cleaned.data(using: .utf8) else {
            throw MusicDossierError.decoding("Codex CLI 返回的 JSON 不是 UTF-8")
        }

        do {
            return try JSONCoding.makeDecoder().decode(ResearchDossier.self, from: data)
        } catch {
            throw MusicDossierError.decoding("Codex CLI 研究档案解码失败：\(error.localizedDescription)\n原始输出：\(cleaned)")
        }
    }

    private func makePrompt(for snapshot: TrackSnapshot) -> String {
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

        return """
        你是一名音乐研究编辑，负责生成简体中文的结构化档案页面数据。
        如果系统允许，请主动使用网络搜索验证事实并收集来源；如果遇到不确定或同名歧义，宁可保守，不要编造。

        你必须只输出一个 JSON 对象，不要输出 Markdown，不要输出解释，不要输出代码块。
        JSON 必须严格包含这些字段：
        - headline: string
        - oneLiner: string
        - visuals: array<{title:string, subject:string, caption:string, kind:string, imageURL:string, sourceURL:string, confidence:\"verified\"|\"inferred\"}>
        - creators: array<{name:string, role:string, summary:string, confidence:\"verified\"|\"inferred\"}>
        - background: array<{title:string, body:string, confidence:\"verified\"|\"inferred\"}>
        - anecdotes: array<{title:string, body:string, confidence:\"verified\"|\"inferred\"}>
        - timeline: array<{dateLabel:string, title:string, body:string, confidence:\"verified\"|\"inferred\"}>
        - relatedWorks: array<{title:string, artist:string, reason:string, confidence:\"verified\"|\"inferred\"}>
        - confidenceNote: string
        - citations: array<{title:string, url:string, publisher:string, note:string, confidence:\"verified\"|\"inferred\"}>

        关键约束：
        1. headline 必须严格等于本地曲目标题：\(snapshot.title)
        2. 必须优先用 title + artist + album 三元组确认歌曲身份。
        3. 不要把翻唱、live、demo、remaster、同名异曲混为一谈。
        4. 如果对象存在歧义，允许 creators/background/anecdotes/timeline/relatedWorks 为空数组，并在 confidenceNote 里明确写“存在歧义/待确认”。
        5. citations 尽量返回至少 3 条真实可打开的 URL；如果拿不到足够可靠来源，就减少正文内容，不要编造来源。
        6. visuals 最多返回 3 条，优先人物肖像、乐队合照、档案照；imageURL 必须是直链图片，最好是 jpg/png/webp/gif，不要返回网页 URL 冒充图片 URL，也不要重复返回专辑封面。
        7. 每段文字保持信息密度高，但不要过长，不要写散文。

        本地元数据如下：
        \(trackSummary)
        """
    }

    private func runCodexExec(executablePath: String, prompt: String) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.currentDirectoryURL = workspaceURL
            process.arguments = [
                "exec",
                "--skip-git-repo-check",
                "-C",
                workspaceURL.path,
                "-c",
                "model_reasoning_effort=\"low\"",
                "--sandbox",
                "read-only",
                "--color",
                "never",
                "--json",
                "-m",
                configuration.openAIModel,
                prompt,
            ]

            let environment = ProcessInfo.processInfo.environment
            process.environment = environment.merging(["TERM": "dumb"]) { current, _ in current }

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { process in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                continuation.resume(returning: ShellResult(output: output, errorOutput: errorOutput, exitCode: process.terminationStatus))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func extractFinalMessage(from stdout: String) -> String? {
        var finalText: String?

        for rawLine in stdout.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("{"), let data = line.data(using: .utf8) else { continue }

            guard
                let frame = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = frame["type"] as? String
            else {
                continue
            }

            if type == "item.completed",
               let item = frame["item"] as? [String: Any],
               (item["type"] as? String) == "agent_message",
               let text = item["text"] as? String,
               let cleaned = text.trimmedNonEmpty
            {
                finalText = cleaned
            }
        }

        return finalText
    }

    private static func stripCodeFence(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.replacingOccurrences(of: "^```[a-zA-Z0-9_-]*\\n", with: "", options: .regularExpression)
            cleaned = cleaned.replacingOccurrences(of: "\\n```$", with: "", options: .regularExpression)
        }
        return cleaned
    }
}
