import Foundation

/// 把 RenderPayload 渲染成小窗页面。
/// 设计原则：一个主叙事（编辑手记）+ 少量高密度卡片，去掉状态噪音，只给主要信息。
public enum HTMLRenderer {
    public static func render(payload: RenderPayload) -> String {
        let scrollRestoreKey = scrollRestoreKey(for: payload)
        let L = L10n(payload.language)
        let palette = palette(for: payload.theme)
        let themeClass = "theme-\(payload.theme.rawValue)"

        let snapshot = payload.snapshot
        let dossier = payload.dossier

        // ---- hero ----
        let artMarkup: String
        if let artworkURL = payload.artworkURL, let artworkSource = artworkSource(for: artworkURL) {
            artMarkup = #"<img class="cover" src="\#(artworkSource.htmlEscaped)" alt="" />"#
        } else {
            artMarkup = #"<div class="cover placeholder"><span>♪</span></div>"#
        }

        let title = snapshot?.title ?? dossier?.headline ?? L.t("hero.waitTitle")
        let metaLine = heroMetaLine(snapshot: snapshot, L: L)
        let oneLiner = dossier?.oneLiner.trimmedNonEmpty
        let oneLinerMarkup = oneLiner.map { #"<p class="lede">\#(display($0))</p>"# } ?? ""

        // ---- body sections ----
        let body: String
        if let dossier {
            body = [
                renderStory(dossier.story, fallbackFacts: dossier.background, L: L),
                renderListeningNotes(dossier.listeningNotes, L: L),
                renderAlbum(dossier.album, artworkURL: payload.artworkURL, L: L),
                renderCreators(dossier.creators, visuals: dossier.visuals, visualAssetRootURL: payload.visualAssetRootURL, L: L),
                renderGallery(dossier.visuals, visualAssetRootURL: payload.visualAssetRootURL, L: L),
                renderBackground(dossier.background, hasStory: dossier.story != nil, L: L),
                renderAnecdotes(dossier.anecdotes, L: L),
                renderTimeline(dossier.timeline, L: L),
                renderRelatedWorks(dossier.relatedWorks, visualAssetRootURL: payload.visualAssetRootURL, L: L),
                renderSources(dossier, cachedAt: payload.cachedAt, L: L),
            ].joined(separator: "\n")
        } else {
            body = renderPendingState(payload: payload, L: L)
        }

        let errorBlock = payload.lastError.map {
            #"<div class="notice error"><strong>\#(display(L.t("notice.refreshFailed")))</strong><span>\#(display($0))</span></div>"#
        } ?? ""
        let staleBlock = (payload.isStale && dossier != nil)
            ? #"<div class="notice"><span>\#(display(L.t("notice.stale")))</span></div>"#
            : ""

        return """
        <!doctype html>
        <html lang="\(payload.language.htmlLang)">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <script>
            (() => {
              const scrollKey = "music-dossier-scroll:\(scrollRestoreKey.htmlEscaped)";
              let ticking = false, hasRestored = false, userScrolled = false;
              const save = () => { try { localStorage.setItem(scrollKey, String(window.scrollY || 0)); } catch (e) {} };
              const restore = () => {
                if (hasRestored || userScrolled) return;
                try {
                  const y = Number(localStorage.getItem(scrollKey));
                  if (Number.isFinite(y) && y > 0) window.scrollTo(0, y);
                } catch (e) {}
                hasRestored = true;
              };
              window.addEventListener("scroll", () => {
                if (!hasRestored && (window.scrollY || 0) > 4) userScrolled = true;
                if (ticking) return;
                ticking = true;
                requestAnimationFrame(() => { save(); ticking = false; });
              }, { passive: true });
              document.addEventListener("DOMContentLoaded", () => requestAnimationFrame(restore));
              window.addEventListener("load", () => requestAnimationFrame(restore));
              window.addEventListener("pagehide", save);
            })();
          </script>
          <style>
            \(palette)
            * { box-sizing: border-box; }
            html, body {
              margin: 0; padding: 0;
              background: var(--bg);
              color: var(--text);
              font-family: -apple-system, "PingFang SC", "PingFang TC", "Hiragino Sans", "Hiragino Sans GB", "Apple SD Gothic Neo", "Helvetica Neue", sans-serif;
              font-size: 14px;
              line-height: 1.7;
              -webkit-font-smoothing: antialiased;
              text-rendering: optimizeLegibility;
            }
            a { color: var(--accent); text-decoration: none; }
            a:hover { text-decoration: underline; }
            .page {
              max-width: 760px;
              margin: 0 auto;
              padding: 22px 26px 40px;
            }

            /* hero */
            .hero {
              display: grid;
              grid-template-columns: 132px minmax(0, 1fr);
              gap: 20px;
              align-items: center;
              padding-bottom: 20px;
              border-bottom: 1px solid var(--rule);
            }
            .cover {
              width: 132px; height: 132px;
              border-radius: 12px;
              object-fit: cover;
              box-shadow: 0 10px 28px var(--cover-shadow);
              border: 1px solid var(--cover-border);
              background: var(--panel);
            }
            .cover.placeholder {
              display: grid; place-items: center;
              color: var(--muted); font-size: 40px;
            }
            .hero h1 {
              margin: 0 0 4px;
              font-family: "New York", "Songti SC", "Songti TC", "Hiragino Mincho ProN", "AppleMyungjo", Georgia, "Times New Roman", serif;
              font-size: 30px;
              line-height: 1.15;
              font-weight: 700;
              letter-spacing: -0.01em;
              overflow-wrap: anywhere;
            }
            .meta { color: var(--muted); font-size: 13px; margin-bottom: 8px; }
            .meta b { color: var(--text); font-weight: 600; }
            .lede {
              margin: 0;
              font-family: "New York", "Songti SC", "Songti TC", "Hiragino Mincho ProN", "AppleMyungjo", Georgia, "Times New Roman", serif;
              font-size: 16px;
              line-height: 1.5;
              color: var(--accent);
            }

            /* notices */
            .notice {
              margin: 14px 0 0;
              padding: 10px 14px;
              border-radius: 10px;
              background: var(--panel);
              border: 1px solid var(--rule);
              color: var(--muted);
              font-size: 12.5px;
              display: flex; gap: 10px; align-items: baseline;
            }
            .notice.error { border-color: var(--error-border); background: var(--error-soft); color: var(--error); }
            .notice strong { font-weight: 600; white-space: nowrap; }

            /* sections */
            section { margin-top: 26px; }
            h2 {
              margin: 0 0 12px;
              font-size: 11.5px;
              font-weight: 600;
              letter-spacing: 0.14em;
              text-transform: uppercase;
              color: var(--muted);
              display: flex; align-items: center; gap: 10px;
            }
            h2::after { content: ""; flex: 1; height: 1px; background: var(--rule); }

            /* story */
            .story p {
              margin: 0 0 14px;
              font-family: "New York", "Songti SC", "Songti TC", "Hiragino Mincho ProN", "AppleMyungjo", Georgia, "Times New Roman", serif;
              font-size: 15.5px;
              line-height: 1.85;
              text-align: justify;
            }
            .story p:last-child { margin-bottom: 0; }
            .story p:first-child::first-letter {
              font-size: 2.1em; line-height: 1; float: left;
              padding: 6px 8px 0 0; color: var(--accent); font-weight: 700;
            }

            /* listening notes */
            .notes { list-style: none; margin: 0; padding: 0; display: grid; gap: 8px; }
            .notes li {
              display: grid; grid-template-columns: 26px minmax(0,1fr); gap: 8px;
              padding: 10px 12px;
              background: var(--panel);
              border: 1px solid var(--rule);
              border-radius: 10px;
            }
            .notes .n {
              color: var(--accent); font-weight: 700;
              font-family: "New York", Georgia, serif; font-size: 16px; line-height: 1.3;
            }

            /* album */
            .album {
              display: grid; grid-template-columns: 120px minmax(0,1fr); gap: 16px; align-items: start;
              padding: 14px;
              background: var(--panel); border: 1px solid var(--rule); border-radius: 12px;
            }
            .album .art { width: 120px; height: 120px; border-radius: 8px; object-fit: cover; box-shadow: 0 6px 18px var(--cover-shadow); background: var(--accent-soft); display: grid; place-items: center; color: var(--accent); font-size: 32px; }
            .album .t { font-weight: 600; font-size: 15px; }
            .album .m { color: var(--muted); font-size: 12.5px; margin: 2px 0 8px; }
            .album .s { color: var(--subtitle); font-size: 13.5px; line-height: 1.7; }
            .album .s a { font-size: 11.5px; margin-left: 6px; }
            .album ul { margin: 10px 0 0; padding: 0; list-style: none; display: grid; gap: 4px; }
            .album li { font-size: 13px; color: var(--subtitle); padding-left: 14px; position: relative; }
            .album li::before { content: "♪"; position: absolute; left: 0; color: var(--accent); font-size: 11px; top: 2px; }
            .album li b { color: var(--text); font-weight: 600; }
            @media (max-width: 560px) { .album { grid-template-columns: 84px minmax(0,1fr); } .album .art { width: 84px; height: 84px; } }

            /* creators */
            .people { display: grid; gap: 10px; }
            .person {
              display: grid; grid-template-columns: 96px minmax(0,1fr); gap: 14px; align-items: start;
              padding: 12px;
              background: var(--panel); border: 1px solid var(--rule); border-radius: 12px;
            }
            .person.no-photo { grid-template-columns: 44px minmax(0,1fr); }
            .photo {
              width: 96px; height: 96px; border-radius: 10px; overflow: hidden;
              background: var(--accent-soft); border: 1px solid var(--rule);
            }
            .photo img { width: 100%; height: 100%; object-fit: cover; object-position: center top; display: block; }
            .avatar {
              width: 44px; height: 44px; border-radius: 50%;
              display: grid; place-items: center;
              background: var(--accent-soft); color: var(--accent);
              font-weight: 700; font-size: 14px;
              border: 1px solid var(--rule);
            }
            .person .name { font-weight: 600; font-size: 15px; display: flex; align-items: baseline; gap: 8px; flex-wrap: wrap; }
            .person .role { color: var(--muted); font-size: 12px; font-weight: 400; }
            .person .bio { color: var(--subtitle); font-size: 13.5px; line-height: 1.7; margin-top: 4px; }
            .person .link { font-size: 11.5px; margin-left: auto; }

            /* gallery */
            .gallery { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; }
            .shot {
              display: grid; gap: 8px; align-content: start;
              background: var(--panel); border: 1px solid var(--rule); border-radius: 12px; overflow: hidden;
            }
            .shot.wide { grid-column: span 2; }
            .shot .img { aspect-ratio: 4 / 3; background: var(--accent-soft); overflow: hidden; }
            .shot.wide .img { aspect-ratio: 16 / 7; }
            .shot .img img { width: 100%; height: 100%; object-fit: cover; display: block; }
            .shot .cap { padding: 0 12px 12px; }
            .shot .cap b { display: block; font-size: 13.5px; margin-bottom: 2px; }
            .shot .cap span { color: var(--subtitle); font-size: 12.5px; line-height: 1.6; }
            .shot .cap a { font-size: 11.5px; margin-left: 6px; }

            /* facts */
            .facts { display: grid; grid-template-columns: repeat(auto-fill, minmax(230px, 1fr)); gap: 10px; }
            .fact {
              padding: 12px 14px;
              background: var(--panel); border: 1px solid var(--rule); border-radius: 12px;
            }
            .fact .t { font-weight: 600; margin-bottom: 4px; display: flex; align-items: baseline; gap: 8px; }
            .fact .b { color: var(--subtitle); font-size: 13.5px; line-height: 1.7; }
            .tag {
              font-size: 10.5px; color: var(--muted); font-weight: 500;
              border: 1px solid var(--rule); border-radius: 999px; padding: 0 7px; line-height: 1.6;
              white-space: nowrap;
            }

            /* anecdotes */
            .anecdote {
              margin: 0 0 12px;
              padding: 10px 14px 10px 16px;
              border-left: 3px solid var(--accent);
              background: var(--panel);
              border-radius: 0 10px 10px 0;
            }
            .anecdote:last-child { margin-bottom: 0; }
            .anecdote .t { font-weight: 600; margin-bottom: 2px; }
            .anecdote .b { color: var(--subtitle); font-size: 13.5px; }

            /* timeline */
            .timeline { display: grid; gap: 0; }
            .tl {
              display: grid; grid-template-columns: 92px 14px minmax(0,1fr); gap: 0 12px;
              position: relative;
              padding-bottom: 14px;
            }
            .tl:last-child { padding-bottom: 0; }
            .tl .d { color: var(--accent); font-weight: 600; font-size: 12.5px; text-align: right; padding-top: 2px; }
            .tl .dot {
              position: relative; width: 14px;
            }
            .tl .dot::before {
              content: ""; position: absolute; left: 3px; top: 7px;
              width: 8px; height: 8px; border-radius: 50%; background: var(--accent);
            }
            .tl:not(:last-child) .dot::after {
              content: ""; position: absolute; left: 6.5px; top: 17px; bottom: -14px;
              width: 1px; background: var(--rule);
            }
            .tl .t { font-weight: 600; }
            .tl .b { color: var(--subtitle); font-size: 13.5px; }

            /* related */
            .related { display: grid; gap: 6px; }
            .rel {
              display: grid; grid-template-columns: 52px minmax(0, 1fr); gap: 12px; align-items: center;
              padding: 8px 12px 8px 8px;
              background: var(--panel); border: 1px solid var(--rule); border-radius: 10px;
            }
            .rel .cover-sm {
              width: 52px; height: 52px; border-radius: 6px; overflow: hidden;
              background: var(--accent-soft); display: grid; place-items: center; color: var(--accent); font-size: 18px;
            }
            .rel .cover-sm img { width: 100%; height: 100%; object-fit: cover; display: block; }
            .rel .who { font-size: 13.5px; }
            .rel .who b { font-weight: 600; }
            .rel .who span { color: var(--muted); }
            .rel .why { color: var(--subtitle); font-size: 12.5px; line-height: 1.55; }

            /* sources */
            details { margin-top: 26px; }
            summary {
              cursor: pointer; list-style: none;
              font-size: 11.5px; font-weight: 600; letter-spacing: 0.14em; text-transform: uppercase;
              color: var(--muted); display: flex; align-items: center; gap: 10px;
            }
            summary::-webkit-details-marker { display: none; }
            summary::after { content: ""; flex: 1; height: 1px; background: var(--rule); }
            .sources { margin-top: 12px; display: grid; gap: 8px; }
            .src { font-size: 13px; }
            .src .n { color: var(--muted); font-size: 12px; }
            .foot { color: var(--muted); font-size: 12px; margin-top: 12px; line-height: 1.7; }

            /* pending */
            .pending {
              margin-top: 26px; padding: 22px;
              border: 1px dashed var(--rule); border-radius: 12px;
              color: var(--muted); text-align: center;
            }
            .pending strong { display: block; color: var(--text); font-weight: 600; margin-bottom: 4px; }
            .pending span { display: block; }
            .pending .kv { margin: 14px auto 0; display: grid; width: max-content; max-width: 100%; grid-template-columns: auto auto; gap: 4px 14px; text-align: left; font-size: 13px; }
            .pending .kv span:nth-child(odd) { color: var(--muted); }
            .pending .kv span:nth-child(even) { color: var(--text); }
            @keyframes pulse { 0%,100% { opacity: .55; } 50% { opacity: 1; } }
            .pending.busy strong { animation: pulse 1.6s ease-in-out infinite; }

            @media (max-width: 560px) {
              .page { padding: 18px 18px 32px; }
              .hero { grid-template-columns: 96px minmax(0,1fr); gap: 14px; }
              .cover { width: 96px; height: 96px; }
              .hero h1 { font-size: 24px; }
              .tl { grid-template-columns: 70px 14px minmax(0,1fr); }
              .gallery { grid-template-columns: 1fr; }
              .shot.wide { grid-column: span 1; }
              .person { grid-template-columns: 72px minmax(0,1fr); }
              .photo { width: 72px; height: 72px; }
            }
          </style>
        </head>
        <body class="\(themeClass.htmlEscaped)">
          <div class="page">
            <header class="hero">
              \(artMarkup)
              <div>
                <h1>\(display(title))</h1>
                <div class="meta">\(metaLine)</div>
                \(oneLinerMarkup)
              </div>
            </header>
            \(errorBlock)
            \(staleBlock)
            \(body)
          </div>
        </body>
        </html>
        """
    }

    // MARK: - Sections

    private static func heroMetaLine(snapshot: TrackSnapshot?, L: L10n) -> String {
        guard let snapshot else { return display(L.t("hero.waitHint")) }
        var parts: [String] = []
        if let artist = snapshot.artist?.trimmedNonEmpty { parts.append("<b>\(display(artist))</b>") }
        if let album = snapshot.album?.trimmedNonEmpty { parts.append(display(album)) }
        if let year = snapshot.year, year > 0 { parts.append(String(year)) }
        if let duration = snapshot.durationSeconds, duration > 0 {
            let total = Int(duration.rounded())
            parts.append(String(format: "%d:%02d", total / 60, total % 60))
        }
        return parts.joined(separator: " · ")
    }

    private static func renderStory(_ story: String?, fallbackFacts: [DossierFact], L: L10n) -> String {
        if let story = story?.trimmedNonEmpty {
            let paragraphs = story
                .replacingOccurrences(of: "\r\n", with: "\n")
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { "<p>\(display($0))</p>" }
                .joined()
            return "<section><h2>\(display(L.t("sec.story")))</h2><div class=\"story\">\(paragraphs)</div></section>"
        }

        // 旧缓存没有 story：把 background 的正文串成叙事，避免页面空洞
        guard !fallbackFacts.isEmpty else { return "" }
        let paragraphs = fallbackFacts.map { "<p>\(display($0.body))</p>" }.joined()
        return "<section><h2>\(display(L.t("sec.background")))</h2><div class=\"story\">\(paragraphs)</div></section>"
    }

    private static func renderListeningNotes(_ notes: [String], L: L10n) -> String {
        guard !notes.isEmpty else { return "" }
        let items = notes.prefix(5).enumerated().map { index, note in
            "<li><span class=\"n\">\(index + 1)</span><span>\(display(note))</span></li>"
        }.joined()
        return "<section><h2>\(display(L.t("sec.notes")))</h2><ol class=\"notes\">\(items)</ol></section>"
    }

    private static func renderAlbum(_ album: DossierAlbum?, artworkURL: URL?, L: L10n) -> String {
        guard let album, album.isMeaningful else { return "" }
        let art: String
        if let artworkURL, let source = artworkSource(for: artworkURL) {
            art = #"<img class="art" src="\#(source.htmlEscaped)" alt="" />"#
        } else {
            art = #"<div class="art">♪</div>"#
        }
        let meta = [album.artist, album.year, album.label].compactMap { $0.trimmedNonEmpty }.map(display).joined(separator: " · ")
        let link = album.sourceURL.map { #"<a href="\#($0.htmlEscaped)">\#(display(L.t("link.albumPage")))</a>"# } ?? ""
        let items = album.highlights.prefix(5).map { line -> String in
            // "曲名 — 说明" 拆成加粗曲名 + 说明
            let separators = [" — ", " – ", "——", " - ", "：", ": "]
            for sep in separators {
                if let range = line.range(of: sep) {
                    let name = String(line[..<range.lowerBound])
                    let why = String(line[range.upperBound...])
                    return "<li><b>\(display(name))</b> · \(display(why))</li>"
                }
            }
            return "<li>\(display(line))</li>"
        }.joined()
        let list = items.isEmpty ? "" : "<ul>\(items)</ul>"
        let title = album.title.trimmedNonEmpty ?? L.t("sec.album")
        return """
        <section><h2>\(display(L.t("sec.album")))</h2>
          <div class="album">
            \(art)
            <div>
              <div class="t">\(display(title))</div>
              <div class="m">\(meta)</div>
              <div class="s">\(display(album.summary))\(link)</div>
              \(list)
            </div>
          </div>
        </section>
        """
    }

    private static func renderCreators(_ creators: [DossierPerson], visuals: [DossierVisual], visualAssetRootURL: URL?, L: L10n) -> String {
        guard !creators.isEmpty else { return "" }
        let items = creators.prefix(6).map { creator in
            var photoSource = resolvedImageSource(cachedFileName: creator.imageFileName, localRootURL: visualAssetRootURL)
            if photoSource == nil, let visual = matchedVisual(for: creator, visuals: visuals) {
                photoSource = resolvedImageSource(cachedFileName: visual.cachedFileName, localRootURL: visualAssetRootURL)
            }
            let media: String
            let cardClass: String
            if let photoSource {
                media = #"<div class="photo"><img src="\#(photoSource.htmlEscaped)" alt="" loading="lazy" /></div>"#
                cardClass = "person"
            } else {
                media = #"<div class="avatar">\#(display(initials(for: creator.name)))</div>"#
                cardClass = "person no-photo"
            }
            let link = creator.imageSourceURL.map { #"<a class="link" href="\#($0.htmlEscaped)">\#(display(L.t("link.wikipedia")))</a>"# } ?? ""
            let text = creator.bio ?? creator.summary
            return """
            <div class="\(cardClass)">
              \(media)
              <div>
                <div class="name"><span>\(display(creator.name))</span><span class="role">\(display(creator.role))</span>\(link)</div>
                <div class="bio">\(display(text))</div>
              </div>
            </div>
            """
        }.joined()
        return "<section><h2>\(display(L.t("sec.people")))</h2><div class=\"people\">\(items)</div></section>"
    }

    private static func renderGallery(_ visuals: [DossierVisual], visualAssetRootURL: URL?, L: L10n) -> String {
        let shots = visuals.compactMap { visual -> (DossierVisual, String)? in
            guard let source = resolvedImageSource(cachedFileName: visual.cachedFileName, localRootURL: visualAssetRootURL) else { return nil }
            return (visual, source)
        }
        guard !shots.isEmpty else { return "" }
        let items = shots.prefix(6).enumerated().map { index, pair in
            let (visual, source) = pair
            // 单数张时，让第一张横跨两列
            let wide = (shots.count % 2 == 1 && index == 0) ? " wide" : ""
            let link = visual.displaySourceURL.trimmedNonEmpty.map { #"<a href="\#($0.htmlEscaped)">\#(display(L.t("link.source")))</a>"# } ?? ""
            let title = visual.title.trimmedNonEmpty ?? visual.subject
            return """
            <figure class="shot\(wide)" style="margin:0">
              <div class="img"><img src="\(source.htmlEscaped)" alt="\(display(visual.subject))" loading="lazy" /></div>
              <figcaption class="cap"><b>\(display(title))</b><span>\(display(visual.caption))\(link)</span></figcaption>
            </figure>
            """
        }.joined()
        return "<section><h2>\(display(L.t("sec.gallery")))</h2><div class=\"gallery\">\(items)</div></section>"
    }

    private static func renderBackground(_ facts: [DossierFact], hasStory: Bool, L: L10n) -> String {
        // 没有 story 时 background 已被当作叙事渲染，避免重复
        guard hasStory, !facts.isEmpty else { return "" }
        let items = facts.prefix(6).map { fact in
            """
            <div class="fact">
              <div class="t"><span>\(display(fact.title))</span>\(inferredTag(fact.confidence, L: L))</div>
              <div class="b">\(display(fact.body))</div>
            </div>
            """
        }.joined()
        return "<section><h2>\(display(L.t("sec.facts")))</h2><div class=\"facts\">\(items)</div></section>"
    }

    private static func renderAnecdotes(_ facts: [DossierFact], L: L10n) -> String {
        guard !facts.isEmpty else { return "" }
        let items = facts.prefix(4).map { fact in
            """
            <div class="anecdote">
              <div class="t">\(display(fact.title))\(inferredTag(fact.confidence, L: L))</div>
              <div class="b">\(display(fact.body))</div>
            </div>
            """
        }.joined()
        return "<section><h2>\(display(L.t("sec.anecdotes")))</h2>\(items)</section>"
    }

    private static func renderTimeline(_ timeline: [DossierTimelineEvent], L: L10n) -> String {
        guard !timeline.isEmpty else { return "" }
        let items = timeline.prefix(8).map { event in
            """
            <div class="tl">
              <div class="d">\(display(event.dateLabel))</div>
              <div class="dot"></div>
              <div>
                <div class="t">\(display(event.title))\(inferredTag(event.confidence, L: L))</div>
                <div class="b">\(display(event.body))</div>
              </div>
            </div>
            """
        }.joined()
        return "<section><h2>\(display(L.t("sec.timeline")))</h2><div class=\"timeline\">\(items)</div></section>"
    }

    private static func renderRelatedWorks(_ items: [DossierRelatedWork], visualAssetRootURL: URL?, L: L10n) -> String {
        guard !items.isEmpty else { return "" }
        let markup = items.prefix(6).map { item in
            let cover: String
            if let source = resolvedImageSource(cachedFileName: item.artworkFileName, localRootURL: visualAssetRootURL) {
                cover = #"<div class="cover-sm"><img src="\#(source.htmlEscaped)" alt="" loading="lazy" /></div>"#
            } else {
                cover = #"<div class="cover-sm">♪</div>"#
            }
            return """
            <div class="rel">
              \(cover)
              <div>
                <div class="who"><b>\(display(item.title))</b> <span>· \(display(item.artist))</span></div>
                <div class="why">\(display(item.reason))</div>
              </div>
            </div>
            """
        }.joined()
        return "<section><h2>\(display(L.t("sec.related")))</h2><div class=\"related\">\(markup)</div></section>"
    }

    private static func renderSources(_ dossier: ResearchDossier, cachedAt: Date?, L: L10n) -> String {
        let citations = dossier.citations.prefix(8).map { citation in
            let publisher = citation.publisher.trimmedNonEmpty.map { " · \(display($0))" } ?? ""
            let note = citation.note.trimmedNonEmpty.map { #"<div class="n">\#(display($0))</div>"# } ?? ""
            return """
            <div class="src">
              <a href="\(citation.url.htmlEscaped)">\(display(citation.title))</a><span class="n">\(publisher)</span>
              \(note)
            </div>
            """
        }.joined()

        var footParts: [String] = []
        if let cachedAt { footParts.append(display(L.t("foot.compiledAt", DateFormatting.displayString(from: cachedAt)))) }
        if let note = dossier.confidenceNote.trimmedNonEmpty { footParts.append(display(note)) }
        let foot = footParts.isEmpty ? "" : #"<div class="foot">\#(footParts.joined(separator: " · "))</div>"#

        let sourceMarkup = citations.isEmpty
            ? #"<div class="foot">\#(display(L.t("foot.noSources")))</div>"#
            : #"<div class="sources">\#(citations)</div>"#

        return """
        <details>
          <summary>\(display(L.t("sec.sources", String(dossier.citations.count))))</summary>
          \(sourceMarkup)
          \(foot)
        </details>
        """
    }

    private static func renderPendingState(payload: RenderPayload, L: L10n) -> String {
        let busy = payload.snapshot != nil && payload.lastError == nil
        var kv = ""
        if let snapshot = payload.snapshot {
            let rows: [(String, String?)] = [
                (L.t("pending.albumArtist"), snapshot.albumArtist),
                (L.t("pending.composer"), snapshot.composer),
                (L.t("pending.genre"), snapshot.genre),
            ]
            let cells = rows.compactMap { label, value -> String? in
                guard let value = value?.trimmedNonEmpty else { return nil }
                return "<span>\(display(label))</span><span>\(display(value))</span>"
            }.joined()
            if !cells.isEmpty { kv = #"<div class="kv">\#(cells)</div>"# }
        }
        return """
        <div class="pending\(busy ? " busy" : "")">
          <strong>\(display(payload.statusHeadline))</strong>
          <span>\(display(payload.statusDetail))</span>
          \(kv)
        </div>
        """
    }

    // MARK: - Helpers

    private static func inferredTag(_ confidence: FactConfidence, L: L10n) -> String {
        confidence == .inferred ? #"<span class="tag">\#(display(L.t("tag.inferred")))</span>"# : ""
    }

    private static func artworkSource(for artworkURL: URL) -> String? {
        if artworkURL.isFileURL {
            return "artwork/\(artworkURL.lastPathComponent)"
        }
        return artworkURL.absoluteString.trimmedNonEmpty
    }

    private static func display(_ value: String) -> String {
        value.htmlDisplayEscaped
    }

    private static func resolvedImageSource(cachedFileName: String?, localRootURL: URL?) -> String? {
        guard let cachedFileName = cachedFileName?.trimmedNonEmpty, let localRootURL else { return nil }
        let localURL = localRootURL.appendingPathComponent(cachedFileName, isDirectory: false)
        return FileManager.default.fileExists(atPath: localURL.path) ? "visuals/\(cachedFileName)" : nil
    }

    private static func matchedVisual(for creator: DossierPerson, visuals: [DossierVisual]) -> DossierVisual? {
        guard !visuals.isEmpty else { return nil }
        let creatorKey = creator.name.normalizedTrackToken()
        let exact = visuals.first { visual in
            let subject = visual.subject.normalizedTrackToken()
            if subject == creatorKey || subject.contains(creatorKey) || creatorKey.contains(subject) {
                return true
            }
            return visual.title.normalizedTrackToken().contains(creatorKey)
        }
        if let exact { return exact }
        return visuals.count == 1 ? visuals.first : nil
    }

    private static func initials(for value: String) -> String {
        var cleaned = value
        for pattern in [#"\([^)]*\)"#, #"（[^）]*）"#] {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        let trimmed = cleaned.trimmedNonEmpty ?? value.trimmedNonEmpty ?? "?"
        // 中日韩名字：只取第一个字
        if let first = trimmed.unicodeScalars.first, first.properties.isIdeographic {
            return String(trimmed.prefix(1))
        }
        let words = trimmed
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .map { String($0.prefix(1)) }
            .joined()
        if let words = words.trimmedNonEmpty { return words }
        return String(trimmed.prefix(2))
    }

    private static func scrollRestoreKey(for payload: RenderPayload) -> String {
        if let trackKey = payload.snapshot?.trackKey.trimmedNonEmpty { return trackKey }
        if let headline = payload.dossier?.headline.trimmedNonEmpty { return "headline:\(headline)" }
        return "empty"
    }

    private static func palette(for theme: DossierTheme) -> String {
        switch theme {
        case .day:
            return """
            :root {
              --bg: #f6f2ea;
              --panel: rgba(255,255,255,0.72);
              --text: #1f1a17;
              --subtitle: #3f3730;
              --muted: #7a6c60;
              --rule: rgba(75,54,34,0.13);
              --accent: #8f4729;
              --accent-soft: rgba(143,71,41,0.12);
              --error: #9e4037;
              --error-soft: rgba(158,64,55,0.08);
              --error-border: rgba(158,64,55,0.18);
              --cover-shadow: rgba(55,29,9,0.18);
              --cover-border: rgba(255,255,255,0.7);
            }
            """
        case .night:
            return """
            :root {
              --bg: #121417;
              --panel: rgba(255,255,255,0.045);
              --text: #f0e8de;
              --subtitle: #d6c8b8;
              --muted: #a3927f;
              --rule: rgba(214,190,160,0.14);
              --accent: #dca06c;
              --accent-soft: rgba(220,160,108,0.16);
              --error: #ee8c80;
              --error-soft: rgba(147,67,61,0.20);
              --error-border: rgba(238,140,128,0.22);
              --cover-shadow: rgba(0,0,0,0.5);
              --cover-border: rgba(255,255,255,0.08);
            }
            """
        }
    }
}
