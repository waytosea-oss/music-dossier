import AppKit
import SwiftUI
import MusicDossierKit

extension Notification.Name {
    static let musicDossierNeedsSetup = Notification.Name("MusicDossierNeedsSetup")
    static let musicDossierSettingsSaved = Notification.Name("MusicDossierSettingsSaved")
}

/// 「设置」窗：选服务商 → 贴 Key → 测试 → 保存。全程不需要碰配置文件。
struct SettingsView: View {
    @State private var providerID: String
    @State private var apiKey: String
    @State private var model: String
    @State private var baseURL: String
    @State private var languageID: String
    @State private var testing = false
    @State private var testResult: String?
    @State private var testOK = false
    @State private var saved = false

    private let languages: [(String, String)] = [
        ("auto", "跟随系统 Auto"), ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"),
        ("en", "English"), ("ja", "日本語"), ("ko", "한국어"), ("es", "Español"),
        ("fr", "Français"), ("de", "Deutsch"), ("pt", "Português"), ("ru", "Русский"), ("it", "Italiano"),
    ]

    init() {
        let config = try? AppConfiguration.load()
        let pid = config?.apiProvider?.trimmedNonEmpty ?? "deepseek"
        _providerID = State(initialValue: pid)
        // 教程截图用：显示打码 Key
        let env = ProcessInfo.processInfo.environment
        _apiKey = State(initialValue: env["MUSIC_DOSSIER_DEMO_MASKED_KEY"] ?? config?.apiKey ?? "")
        _model = State(initialValue: config?.apiModel ?? "")
        _baseURL = State(initialValue: config?.apiBaseURL ?? "")
        _languageID = State(initialValue: config?.language?.trimmedNonEmpty ?? "auto")
    }

    private var preset: ChatCompletionsResearchClient.ProviderPreset? {
        ChatCompletionsResearchClient.preset(id: providerID)
    }

    private var isCustom: Bool { providerID == "custom" }

    private var hasClaude: Bool {
        ClaudeCLIResearchClient.resolvedClaudeExecutablePath(configuredPath: nil) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("设置 · 写作引擎")
                .font(.system(size: 17, weight: .semibold))
            Text("选择一个 AI 服务商，粘贴它的 API Key，就能为每首歌自动生成研究档案。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if hasClaude {
                Label("检测到本机已登录 Claude Code，会优先使用它；下面的配置作为备用。", systemImage: "checkmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("服务商")
                    Picker("", selection: $providerID) {
                        ForEach(ChatCompletionsResearchClient.presets, id: \.id) { p in
                            Text(p.displayName).tag(p.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 300)
                }
                GridRow {
                    Text("API Key")
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("在服务商后台复制，形如 sk-…", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 300)
                        if let p = preset, !p.keyURL.isEmpty {
                            Button("还没有 Key？点这里去「\(p.displayName)」申请 →") {
                                if let url = URL(string: p.keyURL) { NSWorkspace.shared.open(url) }
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                        }
                    }
                }
                GridRow {
                    Text("模型")
                    TextField(preset?.defaultModel.isEmpty == false ? "留空 = \(preset!.defaultModel)" : "例如 deepseek-chat", text: $model)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                }
                if isCustom {
                    GridRow {
                        Text("接口地址")
                        TextField("https://…/v1/chat/completions", text: $baseURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 300)
                    }
                }
                GridRow {
                    Text("档案语言")
                    Picker("", selection: $languageID) {
                        ForEach(languages, id: \.0) { pair in
                            Text(pair.1).tag(pair.0)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 300)
                }
            }

            Divider()

            HStack(spacing: 10) {
                Button(testing ? "正在测试…" : "测试连接") { runTest() }
                    .disabled(testing || apiKey.trimmedNonEmpty == nil)
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                if saved {
                    Text("已保存，引擎已重启 ✓").font(.system(size: 12)).foregroundStyle(.green)
                }
            }
            if let testResult {
                Text(testResult)
                    .font(.system(size: 12))
                    .foregroundStyle(testOK ? .green : .red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Key 只保存在这台电脑上（~/Library/Application Support/MusicDossier/config.json），不会上传到任何别的地方。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(width: 470)
        .onChange(of: providerID) { _ in testResult = nil; saved = false }
        .onAppear {
            if ProcessInfo.processInfo.environment["MUSIC_DOSSIER_DEMO_AUTOTEST"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { runTest() }
            }
        }
    }

    private func currentConfigForTest() -> AppConfiguration? {
        try? AppConfiguration.saveUserSettings(
            provider: providerID, key: apiKey, model: model, baseURL: baseURL, language: languageID)
        return try? AppConfiguration.load()
    }

    private func runTest() {
        testing = true; testResult = nil; saved = false
        Task {
            guard let config = currentConfigForTest() else {
                await MainActor.run { testing = false; testOK = false; testResult = "配置读写失败" }
                return
            }
            let client = ChatCompletionsResearchClient(configuration: config)
            let err = await client.testConnection()
            await MainActor.run {
                testing = false
                testOK = (err == nil)
                testResult = err == nil ? "连接成功！这个 Key 可以用。" : err
                if err == nil { NotificationCenter.default.post(name: .musicDossierSettingsSaved, object: nil) }
            }
        }
    }

    private func save() {
        do {
            try AppConfiguration.saveUserSettings(
                provider: providerID, key: apiKey, model: model, baseURL: baseURL, language: languageID)
            saved = true
            NotificationCenter.default.post(name: .musicDossierSettingsSaved, object: nil)
        } catch {
            testOK = false
            testResult = "保存失败：\(error.localizedDescription)"
        }
    }
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView())
        let w = NSWindow(contentViewController: hosting)
        w.title = "设置"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
