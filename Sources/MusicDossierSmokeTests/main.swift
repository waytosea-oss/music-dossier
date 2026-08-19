import Foundation
import MusicDossierKit

@main
enum MusicDossierSmokeTests {
    static func main() throws {
        try verifyTrackKeyFallback()
        try verifyRendererSections()
        print("MusicDossier smoke tests passed.")
    }

    private static func verifyTrackKeyFallback() throws {
        let key = TrackSnapshot.makeTrackKey(
            persistentId: nil,
            title: "Paranoid Android",
            artist: "Radiohead",
            album: "OK Computer",
            durationSeconds: 386.2
        )

        try expect(
            key == "fallback:paranoid android|radiohead|ok computer|386",
            "track key fallback mismatch: \(key)"
        )
    }

    private static func verifyRendererSections() throws {
        let snapshot = TrackSnapshot(
            persistentId: "ABC123",
            databaseId: 42,
            title: "Yellow",
            artist: "Coldplay",
            album: "Parachutes",
            albumArtist: "Coldplay",
            composer: "Chris Martin",
            durationSeconds: 269,
            genre: "Alternative",
            year: 2000,
            releaseDate: nil,
            lyrics: nil,
            artworkData: nil,
            playerState: .playing,
            kind: "AAC audio file",
            comment: nil,
            cloudStatus: nil
        )

        let dossier = ResearchDossier(
            headline: "Yellow",
            oneLiner: "一首把 Coldplay 推向全球视野的抒情代表作。",
            visuals: [
                DossierVisual(
                    title: "乐队档案照",
                    subject: "Coldplay",
                    caption: "乐队早期宣传照，适合放进人物卡。",
                    kind: "band_photo",
                    imageURL: "https://example.com/coldplay.jpg",
                    sourceURL: "https://example.com/source",
                    confidence: .verified
                ),
            ],
            creators: [
                DossierPerson(name: "Chris Martin", role: "主创", summary: "主唱与核心词曲作者。", confidence: .verified),
            ],
            background: [
                DossierFact(title: "创作缘起", body: "灵感来自夜晚抬头看星空的情绪瞬间。", confidence: .verified),
            ],
            anecdotes: [],
            timeline: [
                DossierTimelineEvent(dateLabel: "2000", title: "正式发行", body: "作为专辑代表单曲扩散。", confidence: .verified),
            ],
            relatedWorks: [],
            confidenceNote: "已区分已证实信息与推断信息。",
            citations: [
                Citation(title: "Wikipedia", url: "https://example.com/1", publisher: "Wikipedia", note: "歌曲词条", confidence: .verified),
                Citation(title: "BBC", url: "https://example.com/2", publisher: "BBC", note: "采访", confidence: .verified),
                Citation(title: "NME", url: "https://example.com/3", publisher: "NME", note: "回顾文章", confidence: .verified),
            ]
        )

        let html = HTMLRenderer.render(
            payload: RenderPayload(
                snapshot: snapshot,
                dossier: dossier,
                artworkURL: nil,
                language: .zhHans,
                statusHeadline: "已命中缓存档案",
                statusDetail: "直接读取本地缓存。",
                cachedAt: .now,
                isPinned: true,
                isStale: false
            )
        )

        try expect(html.contains("人物"), "renderer missing creators section")
        try expect(html.contains("时间线"), "renderer missing timeline section")
        try expect(html.contains("来源与说明"), "renderer missing sources drawer")
        try expect(html.contains("Coldplay"), "renderer missing hero meta")
        try verifyLocalization()
        try expect(html.contains("music-dossier-scroll:"), "renderer missing scroll restore script")
    }

    private static func verifyLocalization() throws {
        try expect(AppLanguage.resolve("zh-CN") == .zhHans, "zh-CN should map to zh-Hans")
        try expect(AppLanguage.resolve("zh-TW") == .zhHant, "zh-TW should map to zh-Hant")
        try expect(AppLanguage.resolve(nil, preferred: ["ja-JP"]) == .ja, "system ja should map to ja")
        try expect(AppLanguage.resolve("auto", preferred: ["xx"]) == .en, "unknown falls back to en")
        for language in AppLanguage.allCases {
            let L = L10n(language)
            try expect(L.t("sec.story") != "sec.story", "missing sec.story for \(language)")
            try expect(L.t("btn.refresh") != "btn.refresh", "missing btn.refresh for \(language)")
        }
        try expect(L10n(.en).t("sec.sources", "4") == "Sources & Notes (4)", "placeholder substitution")
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition {
            struct SmokeFailure: LocalizedError {
                let message: String
                var errorDescription: String? { message }
            }
            throw SmokeFailure(message: message)
        }
    }
}
