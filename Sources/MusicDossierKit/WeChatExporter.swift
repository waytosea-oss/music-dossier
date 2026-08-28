import Foundation

/// 把一份档案渲染成「公众号编辑器可直接粘贴」的 HTML：
/// 全部内联样式（编辑器会剥掉 <style>），图片转 base64 内嵌（粘贴时编辑器自动转存）。
/// 版式忠实于档案页：衬线标题、赭色点缀、编号听点、人物卡、图注、来源列表。
public enum WeChatExporter {

    // 档案页日间配色
    private static let ink = "#2a2119"
    private static let sub = "#5a4c3c"
    private static let muted = "#98897a"
    private static let accent = "#a05a2c"
    private static let rule = "#e3d9c8"
    private static let panel = "#faf6ee"

    private static let pBase = "margin:0 0 20px;font-size:15px;line-height:1.85;color:\(sub);"
    private static let serif = "font-family:Georgia,'Songti SC','STSong',serif;"

    public static func render(
        snapshot: TrackSnapshot,
        dossier: ResearchDossier,
        artworkURL: URL?,
        visualAssetRootURL: URL?
    ) -> String {
        var out: [String] = []
        out.append("<section style=\"max-width:677px;margin:0 auto;padding:0 4px;font-family:-apple-system,'PingFang SC',sans-serif;word-break:break-word;\">")

        // ---- 标题区 ----
        if let art = imageTag(url: artworkURL, maxPixel: 500,
                              style: "width:130px;height:130px;border-radius:10px;display:block;margin:0 auto 14px;box-shadow:0 6px 18px rgba(90,60,30,.18);") {
            out.append("<p style=\"margin:0;text-align:center;\">\(art)</p>")
        }
        out.append("<h1 style=\"\(serif)font-size:22px;line-height:1.4;color:\(ink);text-align:center;margin:0 0 6px;\">\(esc(dossier.headline))</h1>")
        let metaBits = [snapshot.artist, snapshot.album, snapshot.year.map(String.init)].compactMap { $0 }
        if !metaBits.isEmpty {
            out.append("<p style=\"margin:0 0 10px;text-align:center;color:\(muted);font-size:12.5px;\">\(esc(metaBits.joined(separator: " · ")))</p>")
        }
        if let one = dossier.oneLiner.trimmedNonEmpty {
            out.append("<p style=\"\(serif)margin:0 0 26px;text-align:center;color:\(accent);font-size:14.5px;line-height:1.7;\">\(esc(one))</p>")
        }

        // ---- 编辑手记 ----
        if let story = dossier.story?.trimmedNonEmpty {
            out.append(sectionTitle("编 辑 手 记"))
            for para in story.components(separatedBy: "\n\n") {
                guard let p = para.trimmedNonEmpty else { continue }
                out.append("<p style=\"\(pBase)\">\(esc(p))</p>")
            }
        }

        // ---- 听点 ----
        if !dossier.listeningNotes.isEmpty {
            out.append(sectionTitle("听 点"))
            for (i, note) in dossier.listeningNotes.enumerated() {
                out.append("""
                <section style="background:\(panel);border:1px solid \(rule);border-radius:10px;padding:12px 14px;margin:0 0 10px;">
                <p style="margin:0;font-size:14px;line-height:1.8;color:\(sub);"><span style="\(serif)color:\(accent);font-weight:700;margin-right:8px;">\(i + 1)</span>\(esc(note))</p>
                </section>
                """)
            }
            out.append("<p style=\"margin:0 0 10px;\"></p>")
        }

        // ---- 专辑 ----
        if let album = dossier.album, album.isMeaningful {
            out.append(sectionTitle("专 辑"))
            var inner = "<p style=\"margin:0 0 4px;font-size:15px;color:\(ink);\"><strong>\(esc(album.title))</strong></p>"
            let meta = [album.artist, album.year, album.label].compactMap { $0.trimmedNonEmpty }.joined(separator: " · ")
            if !meta.isEmpty { inner += "<p style=\"margin:0 0 8px;color:\(muted);font-size:12.5px;\">\(esc(meta))</p>" }
            if let s = album.summary.trimmedNonEmpty { inner += "<p style=\"margin:0 0 8px;font-size:14px;line-height:1.8;color:\(sub);\">\(esc(s))</p>" }
            for h in album.highlights {
                inner += "<p style=\"margin:0 0 4px;font-size:13px;color:\(sub);\"><span style=\"color:\(accent);\">♪</span> \(esc(h))</p>"
            }
            out.append("<section style=\"background:\(panel);border:1px solid \(rule);border-radius:10px;padding:14px 16px;margin:0 0 20px;\">\(inner)</section>")
        }

        // ---- 人物 ----
        if !dossier.creators.isEmpty {
            out.append(sectionTitle("人 物"))
            for c in dossier.creators {
                var inner = ""
                if let file = c.imageFileName, let root = visualAssetRootURL,
                   let img = imageTag(url: root.appendingFile(file), maxPixel: 300,
                                      style: "width:64px;height:64px;border-radius:50%;object-fit:cover;float:left;margin:0 12px 4px 0;") {
                    inner += img
                }
                inner += "<p style=\"margin:0 0 2px;font-size:14.5px;color:\(ink);\"><strong>\(esc(c.name))</strong> <span style=\"color:\(muted);font-size:12px;\">\(esc(c.role))</span></p>"
                let bio = c.bio?.trimmedNonEmpty ?? c.summary
                inner += "<p style=\"margin:0;font-size:13px;line-height:1.75;color:\(sub);\">\(esc(bio))</p>"
                out.append("<section style=\"background:\(panel);border:1px solid \(rule);border-radius:10px;padding:13px 15px;margin:0 0 10px;overflow:hidden;\">\(inner)</section>")
            }
            out.append("<p style=\"margin:0 0 10px;\"></p>")
        }

        // ---- 图集 ----
        let gallery = dossier.visuals.filter { $0.cachedFileName != nil }
        if !gallery.isEmpty, let root = visualAssetRootURL {
            out.append(sectionTitle("图 集"))
            for v in gallery.prefix(4) {
                guard let file = v.cachedFileName,
                      let img = imageTag(url: root.appendingFile(file), maxPixel: 1000,
                                         style: "max-width:100%;border-radius:8px;display:block;margin:0 auto;") else { continue }
                out.append("<p style=\"margin:0 0 6px;text-align:center;\">\(img)</p>")
                out.append("<p style=\"margin:0 0 18px;text-align:center;color:\(muted);font-size:12px;line-height:1.6;\">\(esc(v.title))\(v.caption.trimmedNonEmpty.map { " · " + esc($0) } ?? "")</p>")
            }
        }

        // ---- 要点 / 轶事 ----
        func factBlock(_ title: String, _ facts: [DossierFact]) {
            guard !facts.isEmpty else { return }
            out.append(sectionTitle(title))
            for f in facts {
                out.append("<p style=\"\(pBase)\"><strong style=\"color:\(ink);\">\(esc(f.title))</strong>\(f.confidence == .inferred ? " <span style=\"font-size:11px;color:\(muted);border:1px solid \(rule);border-radius:8px;padding:0 6px;\">推测</span>" : "")<br>\(esc(f.body))</p>")
            }
        }
        factBlock("要 点", dossier.background)
        factBlock("轶 事", dossier.anecdotes)

        // ---- 时间线 ----
        if !dossier.timeline.isEmpty {
            out.append(sectionTitle("时 间 线"))
            var inner = ""
            for t in dossier.timeline {
                inner += "<p style=\"margin:0 0 10px;font-size:13.5px;line-height:1.7;color:\(sub);\"><strong style=\"\(serif)color:\(accent);\">\(esc(t.dateLabel))</strong> · <strong style=\"color:\(ink);\">\(esc(t.title))</strong><br>\(esc(t.body))</p>"
            }
            out.append("<section style=\"border-left:3px solid \(rule);padding:2px 0 2px 14px;margin:0 0 20px;\">\(inner)</section>")
        }

        // ---- 延伸聆听 ----
        if !dossier.relatedWorks.isEmpty {
            out.append(sectionTitle("延 伸 聆 听"))
            for r in dossier.relatedWorks {
                out.append("<p style=\"margin:0 0 8px;font-size:13.5px;line-height:1.7;color:\(sub);\"><span style=\"color:\(accent);\">♪</span> <strong style=\"color:\(ink);\">\(esc(r.title))</strong> — \(esc(r.artist))<br><span style=\"color:\(muted);font-size:12.5px;\">\(esc(r.reason))</span></p>")
            }
            out.append("<p style=\"margin:0 0 12px;\"></p>")
        }

        // ---- 来源 ----
        if !dossier.citations.isEmpty {
            out.append(sectionTitle("来 源"))
            var inner = ""
            for c in dossier.citations {
                inner += "<p style=\"margin:0 0 6px;font-size:12px;line-height:1.6;color:\(muted);\">· \(esc(c.title))（\(esc(c.publisher))）<br><span style=\"word-break:break-all;\">\(esc(c.url))</span></p>"
            }
            out.append("<section style=\"background:\(panel);border:1px solid \(rule);border-radius:10px;padding:12px 14px;margin:0 0 20px;\">\(inner)</section>")
        }

        // ---- 尾注 ----
        out.append("<p style=\"margin:26px 0 0;text-align:center;color:\(muted);font-size:11.5px;\">本档案由 Music Dossier 生成 · 图片来自维基百科等公开来源，版权归原作者</p>")
        out.append("</section>")
        return out.joined(separator: "\n")
    }

    private static func sectionTitle(_ t: String) -> String {
        """
        <p style="margin:28px 0 12px;font-size:12.5px;letter-spacing:3px;color:\(accent);font-weight:600;border-bottom:1px solid \(rule);padding-bottom:6px;">\(t)</p>
        """
    }

    /// 本地图片 → 压缩 JPEG base64 <img>。读不到就返回 nil（段落自动省略）。
    private static func imageTag(url: URL?, maxPixel: CGFloat, style: String) -> String? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let (small, _) = ImageDownscaler.downscale(data, maxPixel: maxPixel, quality: 0.82)
        guard small.count < 900_000 else { return nil }  // 单图过大就跳过，防粘贴卡死
        return "<img src=\"data:image/jpeg;base64,\(small.base64EncodedString())\" style=\"\(style)\">"
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
