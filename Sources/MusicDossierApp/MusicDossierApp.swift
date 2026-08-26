import AppKit
import MusicDossierKit
import SwiftUI
import WebKit

/// 窗口标题取自打包时写入 Info.plist 的显示名（见 Scripts/package_app_bundle.sh），直接 swift run 时用默认名。
private let appDisplayName: String = {
    let info = Bundle.main.infoDictionary
    return (info?["CFBundleDisplayName"] as? String)?.trimmedNonEmpty
        ?? (info?["CFBundleName"] as? String)?.trimmedNonEmpty
        ?? "Music Dossier"
}()
private let appLocalizedName = "听歌档案"

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var isTerminating = false
    private let coordinator = AppCoordinator()
    private var panelController: DossierPanelController?

    func launchInterface() {
        guard panelController == nil else { return }
        applyApplicationIconIfAvailable()
        let rootView = PanelRootView(coordinator: coordinator)
        panelController = DossierPanelController(rootView: rootView)
        if let window = panelController?.window {
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                guard !AppDelegate.isTerminating else { return }
                AppDelegate.isTerminating = true
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        }
        panelController?.showWindow(nil)
        panelController?.repositionWindowToVisibleArea(forceSnapToPrimaryScreen: true)
        panelController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak panelController] in
            panelController?.repositionWindowToVisibleArea()
        }
        coordinator.bootstrap()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchInterface()
        NotificationCenter.default.addObserver(forName: .musicDossierNeedsSetup, object: nil, queue: .main) { _ in
            Task { @MainActor in SettingsWindowController.shared.show() }
        }
        NotificationCenter.default.addObserver(forName: .musicDossierSettingsSaved, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.coordinator.bootstrap() }
        }
    }

    @objc func showSettings() {
        SettingsWindowController.shared.show()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppDelegate.isTerminating = true
        return .terminateNow
    }

    // 不用系统的“最后窗口关闭即退出”检查：主窗口是 NSPanel，不被该检查计数，
    // 右键菜单（本身是个临时窗口）一收起就会误判“无窗口”而退出应用。
    // 改为在面板真正被用户关闭时退出（见 windowWillClose 监听）。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func applyApplicationIconIfAvailable() {
        let fileManager = FileManager.default
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("MusicDossierIcon.png", isDirectory: false),
            Bundle.main.resourceURL?.appendingPathComponent("MusicDossier.icns", isDirectory: false),
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("Assets/AppIcon/MusicDossierIcon.png", isDirectory: false),
            URL(fileURLWithPath: CommandLine.arguments.first ?? "")
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Assets/AppIcon/MusicDossierIcon.png", isDirectory: false),
            URL(fileURLWithPath: CommandLine.arguments.first ?? "")
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Assets/AppIcon/MusicDossierIcon.png", isDirectory: false),
        ].compactMap { $0 }

        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            if let image = NSImage(contentsOf: candidate) {
                NSApp.applicationIconImage = image
                return
            }
        }
    }
}

final class DossierPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

}

final class DossierPanelController: NSWindowController {
    init<Content: View>(rootView: Content) {
        let hostingController = NSHostingController(rootView: rootView)
        let panel = DossierPanel(
            contentRect: NSRect(x: 180, y: 160, width: 720, height: 860),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = appDisplayName
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 520, height: 640)
        panel.contentViewController = hostingController

        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func repositionWindowToVisibleArea(forceSnapToPrimaryScreen: Bool = false) {
        guard let window else { return }

        guard let screen = bestScreen(for: window.frame, forcePrimary: forceSnapToPrimaryScreen) else {
            window.center()
            return
        }

        let frame = clampedFrame(window.frame, in: screen.visibleFrame)
        window.setFrame(frame, display: true)
    }

    private func bestScreen(for frame: NSRect, forcePrimary: Bool) -> NSScreen? {
        let allScreens = NSScreen.screens
        guard !allScreens.isEmpty else { return nil }

        if forcePrimary {
            return primaryScreen(from: allScreens)
        }

        let visibleScreens = allScreens
            .map { screen in
                (screen: screen, intersection: frame.intersection(screen.visibleFrame))
            }
            .filter { !$0.intersection.isNull && !$0.intersection.isEmpty }
            .sorted { lhs, rhs in lhs.intersection.width * lhs.intersection.height > rhs.intersection.width * rhs.intersection.height }

        return visibleScreens.first?.screen ?? primaryScreen(from: allScreens)
    }

    private func primaryScreen(from screens: [NSScreen]) -> NSScreen? {
        screens.first(where: { $0.frame.contains(CGPoint.zero) })
            ?? NSScreen.main
            ?? screens.first
    }

    private func clampedFrame(_ frame: NSRect, in visibleFrame: NSRect) -> NSRect {
        var clamped = frame
        let horizontalInset: CGFloat = 24
        let verticalInset: CGFloat = 24
        let maxWidth = max(visibleFrame.width - horizontalInset * 2, 520)
        let maxHeight = max(visibleFrame.height - verticalInset * 2, 640)

        clamped.size.width = min(clamped.width, maxWidth)
        clamped.size.height = min(clamped.height, maxHeight)

        let minX = visibleFrame.minX + horizontalInset
        let maxX = visibleFrame.maxX - horizontalInset - clamped.width
        let minY = visibleFrame.minY + verticalInset
        let maxY = visibleFrame.maxY - verticalInset - clamped.height

        if maxX >= minX {
            clamped.origin.x = min(max(clamped.origin.x, minX), maxX)
        } else {
            clamped.origin.x = minX
        }

        if maxY >= minY {
            clamped.origin.y = min(max(clamped.origin.y, minY), maxY)
        } else {
            clamped.origin.y = minY
        }

        return clamped
    }
}

struct PanelRootView: View {
    @ObservedObject var coordinator: AppCoordinator

    private var isNight: Bool { coordinator.displayTheme == .night }
    private var headerTitleColor: Color {
        isNight ? Color(red: 0.96, green: 0.91, blue: 0.85) : Color(red: 0.28, green: 0.17, blue: 0.10)
    }
    private var headerBodyColor: Color {
        isNight ? Color(red: 0.84, green: 0.76, blue: 0.67) : Color(red: 0.36, green: 0.28, blue: 0.21)
    }
    private var headerMetaColor: Color {
        isNight ? Color(red: 0.86, green: 0.67, blue: 0.46) : Color(red: 0.54, green: 0.27, blue: 0.15)
    }
    private var headerGradientColors: [Color] {
        isNight
            ? [
                Color(red: 0.14, green: 0.16, blue: 0.19),
                Color(red: 0.09, green: 0.10, blue: 0.13),
            ]
            : [
                Color(red: 0.98, green: 0.96, blue: 0.93),
                Color(red: 0.94, green: 0.90, blue: 0.85),
            ]
    }
    private var rootBackgroundColor: Color {
        isNight ? Color(red: 0.07, green: 0.08, blue: 0.10) : Color(red: 0.96, green: 0.94, blue: 0.90)
    }
    private var dividerColor: Color {
        isNight ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
    private var localizedPillFill: Color {
        isNight ? Color.white.opacity(0.08) : Color.white.opacity(0.78)
    }
    private var localizedPillBorder: Color {
        isNight ? Color(red: 0.84, green: 0.65, blue: 0.43).opacity(0.18) : Color(red: 0.56, green: 0.39, blue: 0.24).opacity(0.14)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(appDisplayName)
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .foregroundStyle(headerTitleColor)
                    Text(coordinator.bannerText)
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .foregroundStyle(headerBodyColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Button(coordinator.displayTheme == .night ? coordinator.strings.t("btn.day") : coordinator.strings.t("btn.night")) {
                        coordinator.toggleTheme()
                    }
                    .buttonStyle(HeaderActionButtonStyle(theme: coordinator.displayTheme))

                    Button(coordinator.isPinned ? coordinator.strings.t("btn.unpin") : coordinator.strings.t("btn.pin")) {
                        coordinator.togglePin()
                    }
                    .buttonStyle(HeaderActionButtonStyle(theme: coordinator.displayTheme))

                    Button(coordinator.strings.t("btn.refresh")) {
                        coordinator.refreshCurrent()
                    }
                    .buttonStyle(HeaderActionButtonStyle(theme: coordinator.displayTheme, prominent: true))
                    .disabled(!coordinator.canRefresh)

                    Button(coordinator.strings.t("btn.sources")) {
                        coordinator.openSources()
                    }
                    .buttonStyle(HeaderActionButtonStyle(theme: coordinator.displayTheme))
                    .disabled(!coordinator.canOpenSources)
                }
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: headerGradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            Divider()
                .overlay(dividerColor)

            DossierWebView(html: coordinator.html, baseURL: coordinator.baseURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 520, minHeight: 640)
        .background(rootBackgroundColor)
    }
}

struct HeaderActionButtonStyle: ButtonStyle {
    let theme: DossierTheme
    let prominent: Bool

    init(theme: DossierTheme, prominent: Bool = false) {
        self.theme = theme
        self.prominent = prominent
    }

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .default))
            .foregroundStyle(foregroundColor(for: configuration))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundColor(for: configuration))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(borderColor(for: configuration), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.58)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func foregroundColor(for configuration: Configuration) -> Color {
        if prominent {
            if theme == .night {
                return Color(red: 0.12, green: 0.10, blue: 0.08).opacity(isEnabled ? 1 : 0.85)
            }
            return .white.opacity(isEnabled ? 1 : 0.92)
        }

        if theme == .night {
            return Color(red: 0.93, green: 0.88, blue: 0.82).opacity(configuration.isPressed ? 0.88 : 1)
        }

        return Color(red: 0.34, green: 0.24, blue: 0.17).opacity(configuration.isPressed ? 0.88 : 1)
    }

    private func backgroundColor(for configuration: Configuration) -> Color {
        if prominent {
            if theme == .night {
                return Color(red: 0.86, green: 0.63, blue: 0.39).opacity(configuration.isPressed ? 0.92 : 1)
            }
            return Color(red: 0.69, green: 0.43, blue: 0.20).opacity(configuration.isPressed ? 0.90 : 1)
        }

        if theme == .night {
            return Color.white.opacity(configuration.isPressed ? 0.10 : 0.08)
        }

        return Color.white.opacity(configuration.isPressed ? 0.72 : 0.84)
    }

    private func borderColor(for configuration: Configuration) -> Color {
        if prominent {
            if theme == .night {
                return Color(red: 0.95, green: 0.79, blue: 0.60).opacity(configuration.isPressed ? 0.70 : 0.84)
            }
            return Color(red: 0.55, green: 0.33, blue: 0.15).opacity(configuration.isPressed ? 0.70 : 0.84)
        }

        if theme == .night {
            return Color.white.opacity(configuration.isPressed ? 0.18 : 0.12)
        }

        return Color(red: 0.56, green: 0.39, blue: 0.24).opacity(configuration.isPressed ? 0.34 : 0.18)
    }
}

struct DossierWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        let isFirstLoad = context.coordinator.lastHTML.isEmpty
        context.coordinator.lastHTML = html
        if isFirstLoad {
            context.coordinator.pendingScrollY = 0
        } else {
            webView.evaluateJavaScript("window.scrollY") { value, _ in
                context.coordinator.pendingScrollY = (value as? Double) ?? 0
            }
        }
        if let baseURL, baseURL.isFileURL {
            do {
                try context.coordinator.loadLocalHTML(html, rootURL: baseURL, into: webView)
                return
            } catch {
                webView.loadHTMLString(html, baseURL: baseURL)
                return
            }
        }
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        fileprivate var lastHTML: String = ""
        fileprivate var pendingScrollY: Double = 0
        private let fileManager = FileManager.default

        // 网页进程被系统回收/崩溃时自动重载，避免留下白屏。
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            let html = lastHTML
            lastHTML = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak webView] in
                guard let self, let webView, !html.isEmpty else { return }
                self.lastHTML = html
                webView.loadHTMLString(html, baseURL: nil)
            }
        }

        // 重载后恢复滚动位置，阅读中途的刷新不再跳回顶部。
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard pendingScrollY > 0 else { return }
            webView.evaluateJavaScript("window.scrollTo(0, \(pendingScrollY));", completionHandler: nil)
        }

        fileprivate func loadLocalHTML(_ html: String, rootURL: URL, into webView: WKWebView) throws {
            let previewURL = rootURL.appendingFile("live-preview.html")
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try html.write(to: previewURL, atomically: true, encoding: .utf8)
            webView.loadFileURL(previewURL, allowingReadAccessTo: rootURL)
        }

        @MainActor
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
