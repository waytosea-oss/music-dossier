import Foundation

/// 支持的界面 / 档案语言。`auto` 时跟随系统语言。
public enum AppLanguage: String, CaseIterable, Sendable, Codable {
    case en
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case ja
    case ko
    case es
    case fr
    case de
    case pt
    case ru
    case it

    /// 给模型看的语言名（英文）。
    public var promptName: String {
        switch self {
        case .en: return "English"
        case .zhHans: return "Simplified Chinese (简体中文)"
        case .zhHant: return "Traditional Chinese (繁體中文)"
        case .ja: return "Japanese (日本語)"
        case .ko: return "Korean (한국어)"
        case .es: return "Spanish (Español)"
        case .fr: return "French (Français)"
        case .de: return "German (Deutsch)"
        case .pt: return "Portuguese (Português)"
        case .ru: return "Russian (Русский)"
        case .it: return "Italian (Italiano)"
        }
    }

    /// 本地语言的自称，用于 README / 设置说明。
    public var nativeName: String {
        switch self {
        case .en: return "English"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .es: return "Español"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .pt: return "Português"
        case .ru: return "Русский"
        case .it: return "Italiano"
        }
    }

    /// 对应的维基百科站点代码。
    public var wikipediaLang: String {
        switch self {
        case .zhHans, .zhHant: return "zh"
        default: return rawValue
        }
    }

    /// HTML `lang` 属性。
    public var htmlLang: String {
        switch self {
        case .zhHans: return "zh-Hans"
        case .zhHant: return "zh-Hant"
        default: return rawValue
        }
    }

    /// 是否使用中文标点（“”《》）。
    public var usesCJKPunctuation: Bool {
        self == .zhHans || self == .zhHant || self == .ja
    }

    /// 从配置值或系统语言解析。
    public static func resolve(_ configured: String?, preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        if let configured = configured?.trimmedNonEmpty?.lowercased(), configured != "auto" {
            if let exact = AppLanguage.allCases.first(where: { $0.rawValue.lowercased() == configured }) {
                return exact
            }
            if let matched = match(identifier: configured) {
                return matched
            }
        }
        for identifier in preferred {
            if let matched = match(identifier: identifier.lowercased()) {
                return matched
            }
        }
        return .en
    }

    private static func match(identifier: String) -> AppLanguage? {
        let id = identifier.lowercased().replacingOccurrences(of: "_", with: "-")
        if id.hasPrefix("zh") {
            if id.contains("hant") || id.contains("-tw") || id.contains("-hk") || id.contains("-mo") {
                return .zhHant
            }
            return .zhHans
        }
        let prefix = String(id.split(separator: "-").first ?? Substring(id))
        switch prefix {
        case "en": return .en
        case "ja": return .ja
        case "ko": return .ko
        case "es": return .es
        case "fr": return .fr
        case "de": return .de
        case "pt": return .pt
        case "ru": return .ru
        case "it": return .it
        default: return nil
        }
    }
}

/// 界面文案表。查不到的键回退英文，再回退键名本身。
public struct L10n: Sendable {
    public let language: AppLanguage

    public init(_ language: AppLanguage) {
        self.language = language
    }

    public static var system: L10n {
        L10n(AppLanguage.resolve(nil))
    }

    public func t(_ key: String) -> String {
        if let table = Self.strings[key] {
            if let value = table[language] { return value }
            if let value = table[.en] { return value }
        }
        return key
    }

    /// 带一个占位符 `%@` 的文案。
    public func t(_ key: String, _ argument: String) -> String {
        t(key).replacingOccurrences(of: "%@", with: argument)
    }

    // swiftlint:disable line_length
    private static let strings: [String: [AppLanguage: String]] = [
        // ---- 顶栏按钮 ----
        "btn.night": [.en: "Night", .zhHans: "夜间", .zhHant: "夜間", .ja: "ナイト", .ko: "야간", .es: "Noche", .fr: "Nuit", .de: "Nacht", .pt: "Noite", .ru: "Ночь", .it: "Notte"],
        "btn.day": [.en: "Day", .zhHans: "日间", .zhHant: "日間", .ja: "デイ", .ko: "주간", .es: "Día", .fr: "Jour", .de: "Tag", .pt: "Dia", .ru: "День", .it: "Giorno"],
        "btn.pin": [.en: "Pin", .zhHans: "固定", .zhHant: "固定", .ja: "固定", .ko: "고정", .es: "Fijar", .fr: "Épingler", .de: "Anheften", .pt: "Fixar", .ru: "Закрепить", .it: "Fissa"],
        "btn.unpin": [.en: "Unpin", .zhHans: "取消固定", .zhHant: "取消固定", .ja: "固定解除", .ko: "고정 해제", .es: "Soltar", .fr: "Détacher", .de: "Lösen", .pt: "Soltar", .ru: "Открепить", .it: "Sblocca"],
        "btn.refresh": [.en: "Refresh", .zhHans: "刷新", .zhHant: "重新整理", .ja: "更新", .ko: "새로고침", .es: "Actualizar", .fr: "Actualiser", .de: "Neu laden", .pt: "Atualizar", .ru: "Обновить", .it: "Aggiorna"],
        "btn.sources": [.en: "Sources", .zhHans: "来源", .zhHant: "來源", .ja: "出典", .ko: "출처", .es: "Fuentes", .fr: "Sources", .de: "Quellen", .pt: "Fontes", .ru: "Источники", .it: "Fonti"],

        // ---- 页面板块 ----
        "sec.story": [.en: "Editor's Notes", .zhHans: "编辑手记", .zhHant: "編輯手記", .ja: "編集ノート", .ko: "에디터 노트", .es: "Notas del editor", .fr: "Notes de la rédaction", .de: "Notizen der Redaktion", .pt: "Notas do editor", .ru: "Заметки редактора", .it: "Note della redazione"],
        "sec.background": [.en: "Background", .zhHans: "创作背景", .zhHant: "創作背景", .ja: "背景", .ko: "배경", .es: "Contexto", .fr: "Contexte", .de: "Hintergrund", .pt: "Contexto", .ru: "Предыстория", .it: "Contesto"],
        "sec.notes": [.en: "Listen For", .zhHans: "听点", .zhHant: "聽點", .ja: "聴きどころ", .ko: "감상 포인트", .es: "Escucha con atención", .fr: "À écouter", .de: "Hörtipps", .pt: "Preste atenção", .ru: "На что обратить слух", .it: "Da ascoltare"],
        "sec.album": [.en: "Album", .zhHans: "专辑", .zhHant: "專輯", .ja: "アルバム", .ko: "앨범", .es: "Álbum", .fr: "Album", .de: "Album", .pt: "Álbum", .ru: "Альбом", .it: "Album"],
        "sec.people": [.en: "People", .zhHans: "人物", .zhHant: "人物", .ja: "人物", .ko: "인물", .es: "Personas", .fr: "Personnes", .de: "Personen", .pt: "Pessoas", .ru: "Люди", .it: "Persone"],
        "sec.gallery": [.en: "Gallery", .zhHans: "图集", .zhHant: "圖集", .ja: "ギャラリー", .ko: "갤러리", .es: "Galería", .fr: "Galerie", .de: "Galerie", .pt: "Galeria", .ru: "Галерея", .it: "Galleria"],
        "sec.facts": [.en: "Key Facts", .zhHans: "要点", .zhHant: "要點", .ja: "要点", .ko: "핵심 정보", .es: "Datos clave", .fr: "Points clés", .de: "Fakten", .pt: "Fatos", .ru: "Факты", .it: "Punti chiave"],
        "sec.anecdotes": [.en: "Anecdotes", .zhHans: "轶事", .zhHant: "軼事", .ja: "エピソード", .ko: "일화", .es: "Anécdotas", .fr: "Anecdotes", .de: "Anekdoten", .pt: "Curiosidades", .ru: "Истории", .it: "Aneddoti"],
        "sec.timeline": [.en: "Timeline", .zhHans: "时间线", .zhHant: "時間線", .ja: "年表", .ko: "타임라인", .es: "Cronología", .fr: "Chronologie", .de: "Zeitleiste", .pt: "Linha do tempo", .ru: "Хронология", .it: "Cronologia"],
        "sec.related": [.en: "Further Listening", .zhHans: "延伸聆听", .zhHant: "延伸聆聽", .ja: "あわせて聴きたい", .ko: "함께 듣기", .es: "Para seguir escuchando", .fr: "À écouter aussi", .de: "Weiterhören", .pt: "Para ouvir depois", .ru: "Послушать ещё", .it: "Da ascoltare anche"],
        "sec.sources": [.en: "Sources & Notes (%@)", .zhHans: "来源与说明（%@）", .zhHant: "來源與說明（%@）", .ja: "出典と注記（%@）", .ko: "출처 및 참고 (%@)", .es: "Fuentes y notas (%@)", .fr: "Sources et notes (%@)", .de: "Quellen & Hinweise (%@)", .pt: "Fontes e notas (%@)", .ru: "Источники и примечания (%@)", .it: "Fonti e note (%@)"],
        "tag.inferred": [.en: "inferred", .zhHans: "推测", .zhHant: "推測", .ja: "推定", .ko: "추정", .es: "inferido", .fr: "déduit", .de: "vermutet", .pt: "inferido", .ru: "предположительно", .it: "dedotto"],
        "link.wikipedia": [.en: "Wikipedia ↗", .zhHans: "维基百科 ↗", .zhHant: "維基百科 ↗", .ja: "Wikipedia ↗", .ko: "위키백과 ↗", .es: "Wikipedia ↗", .fr: "Wikipédia ↗", .de: "Wikipedia ↗", .pt: "Wikipédia ↗", .ru: "Википедия ↗", .it: "Wikipedia ↗"],
        "link.source": [.en: "source ↗", .zhHans: "来源 ↗", .zhHant: "來源 ↗", .ja: "出典 ↗", .ko: "출처 ↗", .es: "fuente ↗", .fr: "source ↗", .de: "Quelle ↗", .pt: "fonte ↗", .ru: "источник ↗", .it: "fonte ↗"],
        "link.albumPage": [.en: "about this album ↗", .zhHans: "介绍页 ↗", .zhHant: "介紹頁 ↗", .ja: "紹介ページ ↗", .ko: "소개 페이지 ↗", .es: "más sobre el álbum ↗", .fr: "à propos de l'album ↗", .de: "über das Album ↗", .pt: "sobre o álbum ↗", .ru: "об альбоме ↗", .it: "sull'album ↗"],
        "foot.compiledAt": [.en: "Compiled %@", .zhHans: "整理于 %@", .zhHant: "整理於 %@", .ja: "%@ 作成", .ko: "%@ 작성", .es: "Elaborado el %@", .fr: "Rédigé le %@", .de: "Erstellt am %@", .pt: "Elaborado em %@", .ru: "Составлено %@", .it: "Compilato il %@"],
        "foot.noSources": [.en: "No openable sources were found this time.", .zhHans: "这次没有拿到可打开的来源。", .zhHant: "這次沒有拿到可開啟的來源。", .ja: "今回は参照できる出典が見つかりませんでした。", .ko: "이번에는 열 수 있는 출처를 찾지 못했습니다.", .es: "Esta vez no se encontraron fuentes consultables.", .fr: "Aucune source consultable n'a été trouvée cette fois.", .de: "Diesmal wurden keine aufrufbaren Quellen gefunden.", .pt: "Desta vez não foram encontradas fontes consultáveis.", .ru: "На этот раз открываемых источников не найдено.", .it: "Questa volta non sono state trovate fonti consultabili."],
        "hero.waitTitle": [.en: "Waiting for Music", .zhHans: "等待 Music 播放", .zhHant: "等待 Music 播放", .ja: "Music の再生を待っています", .ko: "Music 재생 대기 중", .es: "Esperando a Música", .fr: "En attente de Musique", .de: "Warte auf Musik", .pt: "Aguardando o Música", .ru: "Ожидание Музыки", .it: "In attesa di Musica"],
        "hero.waitHint": [.en: "Open Music and play a song", .zhHans: "打开 Music 并播放一首歌", .zhHant: "打開 Music 並播放一首歌", .ja: "Music を開いて曲を再生してください", .ko: "Music을 열고 노래를 재생하세요", .es: "Abre Música y reproduce una canción", .fr: "Ouvrez Musique et lancez un morceau", .de: "Öffne Musik und spiele einen Song", .pt: "Abra o Música e toque uma faixa", .ru: "Откройте Музыку и включите песню", .it: "Apri Musica e riproduci un brano"],
        "notice.refreshFailed": [.en: "Refresh failed", .zhHans: "本次刷新失败", .zhHant: "本次重新整理失敗", .ja: "更新に失敗しました", .ko: "새로고침 실패", .es: "Fallo al actualizar", .fr: "Échec de l'actualisation", .de: "Aktualisierung fehlgeschlagen", .pt: "Falha ao atualizar", .ru: "Не удалось обновить", .it: "Aggiornamento non riuscito"],
        "notice.stale": [.en: "This dossier is cached; a fresh one is being prepared in the background.", .zhHans: "这份档案是缓存，后台正在更新。", .zhHant: "這份檔案是快取，背景正在更新。", .ja: "これはキャッシュです。バックグラウンドで更新中。", .ko: "캐시된 문서입니다. 백그라운드에서 갱신 중.", .es: "Este dossier es de la caché; se está actualizando en segundo plano.", .fr: "Ce dossier vient du cache ; une mise à jour est en cours.", .de: "Dieses Dossier stammt aus dem Cache; im Hintergrund wird aktualisiert.", .pt: "Este dossiê está em cache; uma atualização está a caminho.", .ru: "Это досье из кэша; обновление идёт в фоне.", .it: "Questo dossier è in cache; è in corso un aggiornamento."],
        "pending.albumArtist": [.en: "Album artist", .zhHans: "专辑艺人", .zhHant: "專輯藝人", .ja: "アルバムアーティスト", .ko: "앨범 아티스트", .es: "Artista del álbum", .fr: "Artiste de l'album", .de: "Albumkünstler", .pt: "Artista do álbum", .ru: "Исполнитель альбома", .it: "Artista dell'album"],
        "pending.composer": [.en: "Composer", .zhHans: "作曲", .zhHant: "作曲", .ja: "作曲", .ko: "작곡", .es: "Compositor", .fr: "Compositeur", .de: "Komponist", .pt: "Compositor", .ru: "Композитор", .it: "Compositore"],
        "pending.genre": [.en: "Genre", .zhHans: "体裁", .zhHant: "類型", .ja: "ジャンル", .ko: "장르", .es: "Género", .fr: "Genre", .de: "Genre", .pt: "Gênero", .ru: "Жанр", .it: "Genere"],

        // ---- 状态（原生头栏与等待卡）----
        "st.waiting.title": [.en: "Waiting for the current track", .zhHans: "等待 Music 当前曲目", .zhHant: "等待 Music 目前曲目", .ja: "再生中の曲を待っています", .ko: "현재 곡을 기다리는 중", .es: "Esperando la pista actual", .fr: "En attente du morceau en cours", .de: "Warte auf den aktuellen Titel", .pt: "Aguardando a faixa atual", .ru: "Ожидание текущего трека", .it: "In attesa del brano corrente"],
        "st.waiting.detail": [.en: "The panel follows Music.app and researches each new track.", .zhHans: "启动后会自动跟随 Music，切歌时整理背景信息。", .zhHant: "啟動後會自動跟隨 Music，切歌時整理背景資訊。", .ja: "Music.app に追従し、曲が変わるたびに調べます。", .ko: "Music.app을 따라가며 곡이 바뀔 때마다 조사합니다.", .es: "El panel sigue a Música e investiga cada nueva pista.", .fr: "Le panneau suit Musique et documente chaque nouveau morceau.", .de: "Das Panel folgt Musik und recherchiert jeden neuen Titel.", .pt: "O painel acompanha o Música e pesquisa cada nova faixa.", .ru: "Панель следует за Музыкой и исследует каждый новый трек.", .it: "Il pannello segue Musica e ricerca ogni nuovo brano."],
        "st.started": [.en: "Ready — listening to Music.app", .zhHans: "服务已启动，正在监听 Music", .zhHant: "服務已啟動，正在監聽 Music", .ja: "準備完了 — Music.app を監視中", .ko: "준비 완료 — Music.app 감시 중", .es: "Listo — escuchando Música", .fr: "Prêt — à l'écoute de Musique", .de: "Bereit — Musik wird beobachtet", .pt: "Pronto — acompanhando o Música", .ru: "Готово — слежу за Музыкой", .it: "Pronto — in ascolto di Musica"],
        "st.startFail.title": [.en: "Failed to start", .zhHans: "启动失败", .zhHant: "啟動失敗", .ja: "起動に失敗", .ko: "시작 실패", .es: "Error al iniciar", .fr: "Échec du démarrage", .de: "Start fehlgeschlagen", .pt: "Falha ao iniciar", .ru: "Не удалось запустить", .it: "Avvio non riuscito"],
        "st.startFail.detail": [.en: "Could not initialise the cache or the Music connection.", .zhHans: "暂时无法初始化缓存或 Music 通道。", .zhHant: "暫時無法初始化快取或 Music 通道。", .ja: "キャッシュまたは Music 連携を初期化できません。", .ko: "캐시 또는 Music 연결을 초기화할 수 없습니다.", .es: "No se pudo inicializar la caché o la conexión con Música.", .fr: "Impossible d'initialiser le cache ou la connexion à Musique.", .de: "Cache oder Musik-Verbindung konnten nicht initialisiert werden.", .pt: "Não foi possível iniciar o cache ou a conexão com o Música.", .ru: "Не удалось инициализировать кэш или связь с Музыкой.", .it: "Impossibile inizializzare la cache o la connessione a Musica."],
        "st.pinned.title": [.en: "Pinned to this track", .zhHans: "已固定当前歌曲", .zhHant: "已固定目前歌曲", .ja: "この曲に固定中", .ko: "이 곡에 고정됨", .es: "Fijado en esta pista", .fr: "Épinglé sur ce morceau", .de: "An diesen Titel angeheftet", .pt: "Fixado nesta faixa", .ru: "Закреплено на этом треке", .it: "Fissato su questo brano"],
        "st.pinned.detail": [.en: "The panel will not follow track changes until you unpin.", .zhHans: "此窗口暂时不会跟随切歌，需要时可手动刷新。", .zhHant: "此視窗暫時不會跟隨切歌，需要時可手動重新整理。", .ja: "固定を解除するまで曲の変更に追従しません。", .ko: "고정을 해제할 때까지 곡 변경을 따라가지 않습니다.", .es: "El panel no seguirá los cambios de pista hasta que lo sueltes.", .fr: "Le panneau ne suivra plus les changements tant qu'il est épinglé.", .de: "Das Panel folgt Titelwechseln erst wieder nach dem Lösen.", .pt: "O painel não acompanhará mudanças de faixa até você soltar.", .ru: "Панель не будет следовать за сменой трека, пока закреплена.", .it: "Il pannello non seguirà i cambi di brano finché non lo sblocchi."],
        "st.unpinned.title": [.en: "Following Music again", .zhHans: "已恢复跟随 Music", .zhHant: "已恢復跟隨 Music", .ja: "Music への追従を再開", .ko: "다시 Music을 따라갑니다", .es: "Siguiendo Música de nuevo", .fr: "Suit à nouveau Musique", .de: "Folgt Musik wieder", .pt: "Acompanhando o Música novamente", .ru: "Снова следую за Музыкой", .it: "Segue di nuovo Musica"],
        "st.unpinned.detail": [.en: "The dossier will refresh automatically when the track changes.", .zhHans: "切歌时会继续自动刷新。", .zhHant: "切歌時會繼續自動重新整理。", .ja: "曲が変わると自動的に更新されます。", .ko: "곡이 바뀌면 자동으로 새로고침됩니다.", .es: "El dossier se actualizará al cambiar de pista.", .fr: "Le dossier s'actualisera au changement de morceau.", .de: "Das Dossier aktualisiert sich beim Titelwechsel.", .pt: "O dossiê será atualizado quando a faixa mudar.", .ru: "Досье обновится при смене трека.", .it: "Il dossier si aggiornerà al cambio di brano."],
        "st.musicNotRunning.title": [.en: "Music is not running", .zhHans: "Music 未启动", .zhHant: "Music 未啟動", .ja: "Music が起動していません", .ko: "Music이 실행 중이 아닙니다", .es: "Música no está abierta", .fr: "Musique n'est pas lancé", .de: "Musik läuft nicht", .pt: "O Música não está aberto", .ru: "Музыка не запущена", .it: "Musica non è in esecuzione"],
        "st.musicNotRunning.keep": [.en: "Keeping the last dossier open.", .zhHans: "暂时保留上一首资料页。", .zhHant: "暫時保留上一首資料頁。", .ja: "前の曲の資料を表示したままにします。", .ko: "이전 곡의 문서를 유지합니다.", .es: "Se mantiene el último dossier.", .fr: "Le dernier dossier reste affiché.", .de: "Das letzte Dossier bleibt geöffnet.", .pt: "Mantendo o último dossiê aberto.", .ru: "Показываю последнее досье.", .it: "L'ultimo dossier resta aperto."],
        "st.musicNotRunning.hint": [.en: "Open Music and play a song to generate a dossier.", .zhHans: "打开 Music 并播放歌曲后，会自动生成档案。", .zhHant: "打開 Music 並播放歌曲後，會自動生成檔案。", .ja: "Music を開いて曲を再生すると資料が生成されます。", .ko: "Music을 열고 노래를 재생하면 문서가 생성됩니다.", .es: "Abre Música y reproduce algo para generar un dossier.", .fr: "Ouvrez Musique et lancez un morceau pour générer un dossier.", .de: "Öffne Musik und spiele etwas ab, um ein Dossier zu erzeugen.", .pt: "Abra o Música e toque algo para gerar um dossiê.", .ru: "Откройте Музыку и включите песню, чтобы создать досье.", .it: "Apri Musica e riproduci qualcosa per generare un dossier."],
        "st.noTrack.title": [.en: "Nothing playing", .zhHans: "没有可读取的曲目", .zhHant: "沒有可讀取的曲目", .ja: "再生中の曲がありません", .ko: "재생 중인 곡 없음", .es: "Nada en reproducción", .fr: "Rien en lecture", .de: "Nichts wird abgespielt", .pt: "Nada tocando", .ru: "Ничего не играет", .it: "Nessuna riproduzione"],
        "st.noTrack.keep": [.en: "Music is paused or stopped; keeping the last dossier.", .zhHans: "Music 已暂停或停止，暂时保留上一首资料页。", .zhHant: "Music 已暫停或停止，暫時保留上一首資料頁。", .ja: "Music は一時停止/停止中。前の資料を表示します。", .ko: "Music이 일시정지/정지됨. 이전 문서를 유지합니다.", .es: "Música está en pausa; se mantiene el último dossier.", .fr: "Musique est en pause ; le dernier dossier reste affiché.", .de: "Musik ist pausiert; das letzte Dossier bleibt offen.", .pt: "O Música está pausado; mantendo o último dossiê.", .ru: "Музыка на паузе; показываю последнее досье.", .it: "Musica è in pausa; l'ultimo dossier resta aperto."],
        "st.noTrack.hint": [.en: "Press play in Music to begin.", .zhHans: "在 Music 里播放一首歌即可开始。", .zhHant: "在 Music 裡播放一首歌即可開始。", .ja: "Music で再生を始めてください。", .ko: "Music에서 재생을 시작하세요.", .es: "Pulsa reproducir en Música para empezar.", .fr: "Lancez la lecture dans Musique pour commencer.", .de: "Drücke in Musik auf Wiedergabe.", .pt: "Dê play no Música para começar.", .ru: "Нажмите воспроизведение в Музыке.", .it: "Premi play in Musica per iniziare."],
        "st.noPermission.title": [.en: "Automation permission needed", .zhHans: "缺少自动化权限", .zhHant: "缺少自動化權限", .ja: "オートメーション権限が必要です", .ko: "자동화 권한 필요", .es: "Se necesita permiso de automatización", .fr: "Autorisation d'automatisation requise", .de: "Automatisierungs-Berechtigung nötig", .pt: "Permissão de automação necessária", .ru: "Нужно разрешение автоматизации", .it: "Serve il permesso di automazione"],
        "st.noPermission.detail": [.en: "Allow this app to control Music in System Settings → Privacy & Security → Automation.", .zhHans: "请在 系统设置 → 隐私与安全性 → 自动化 里允许本应用控制 Music。", .zhHant: "請在 系統設定 → 隱私權與安全性 → 自動化 裡允許本應用控制 Music。", .ja: "システム設定 → プライバシーとセキュリティ → オートメーション で Music の制御を許可してください。", .ko: "시스템 설정 → 개인정보 보호 및 보안 → 자동화에서 Music 제어를 허용하세요.", .es: "Permite que esta app controle Música en Ajustes → Privacidad y seguridad → Automatización.", .fr: "Autorisez cette app à contrôler Musique dans Réglages → Confidentialité → Automatisation.", .de: "Erlaube dieser App in Systemeinstellungen → Datenschutz → Automatisierung die Steuerung von Musik.", .pt: "Permita que este app controle o Música em Ajustes → Privacidade e Segurança → Automação.", .ru: "Разрешите приложению управлять Музыкой: Системные настройки → Конфиденциальность → Автоматизация.", .it: "Consenti a questa app di controllare Musica in Impostazioni → Privacy e sicurezza → Automazione."],
        "st.noPermission.error": [.en: "No Automation permission; cannot read the current track.", .zhHans: "没有获得 Automation 权限，无法读取当前曲目。", .zhHant: "沒有獲得 Automation 權限，無法讀取目前曲目。", .ja: "オートメーション権限がなく、現在の曲を読めません。", .ko: "자동화 권한이 없어 현재 곡을 읽을 수 없습니다.", .es: "Sin permiso de automatización; no se puede leer la pista actual.", .fr: "Pas d'autorisation d'automatisation ; lecture du morceau impossible.", .de: "Keine Automatisierungs-Berechtigung; aktueller Titel nicht lesbar.", .pt: "Sem permissão de automação; não é possível ler a faixa atual.", .ru: "Нет разрешения автоматизации; текущий трек не прочитать.", .it: "Nessun permesso di automazione; impossibile leggere il brano."],
        "st.readFail.title": [.en: "Could not read Music", .zhHans: "读取 Music 失败", .zhHant: "讀取 Music 失敗", .ja: "Music を読み取れません", .ko: "Music을 읽을 수 없음", .es: "No se pudo leer Música", .fr: "Lecture de Musique impossible", .de: "Musik konnte nicht gelesen werden", .pt: "Não foi possível ler o Música", .ru: "Не удалось прочитать Музыку", .it: "Impossibile leggere Musica"],
        "st.readFail.detail": [.en: "Will retry on the next poll.", .zhHans: "等待下次轮询恢复。", .zhHant: "等待下次輪詢恢復。", .ja: "次回のポーリングで再試行します。", .ko: "다음 폴링에서 다시 시도합니다.", .es: "Se reintentará en el próximo sondeo.", .fr: "Nouvelle tentative au prochain cycle.", .de: "Beim nächsten Abfragen wird es erneut versucht.", .pt: "Tentará novamente na próxima verificação.", .ru: "Повтор при следующем опросе.", .it: "Riproverà al prossimo controllo."],
        "st.reading.title": [.en: "Reading track info", .zhHans: "正在读取本地元数据", .zhHant: "正在讀取本地中繼資料", .ja: "曲情報を読み込み中", .ko: "곡 정보 읽는 중", .es: "Leyendo la pista", .fr: "Lecture des infos du morceau", .de: "Titelinfos werden gelesen", .pt: "Lendo a faixa", .ru: "Читаю данные трека", .it: "Lettura del brano"],
        "st.reading.detail": [.en: "Showing the track card first; the research usually takes 1–3 minutes.", .zhHans: "先显示歌曲卡片，再后台补全研究内容；首轮联网研究通常需要 1 到 3 分钟。", .zhHant: "先顯示歌曲卡片，再背景補全研究內容；首輪聯網研究通常需要 1 到 3 分鐘。", .ja: "先に曲カードを表示し、調査は通常 1〜3 分かかります。", .ko: "먼저 곡 카드를 표시하고, 조사는 보통 1–3분 걸립니다.", .es: "Primero la ficha; la investigación suele tardar 1–3 minutos.", .fr: "La fiche d'abord ; la recherche prend généralement 1 à 3 minutes.", .de: "Zuerst die Titelkarte; die Recherche dauert meist 1–3 Minuten.", .pt: "Primeiro a ficha; a pesquisa costuma levar de 1 a 3 minutos.", .ru: "Сначала карточка; исследование обычно занимает 1–3 минуты.", .it: "Prima la scheda; la ricerca richiede di solito 1–3 minuti."],
        "st.forceRefresh.title": [.en: "Rewriting the dossier", .zhHans: "正在强制刷新档案", .zhHant: "正在強制重新整理檔案", .ja: "資料を作り直しています", .ko: "문서를 다시 작성 중", .es: "Reescribiendo el dossier", .fr: "Réécriture du dossier", .de: "Dossier wird neu erstellt", .pt: "Reescrevendo o dossiê", .ru: "Переписываю досье", .it: "Riscrittura del dossier"],
        "st.forceRefresh.detail": [.en: "Ignoring the cache and researching again; usually 1–3 minutes.", .zhHans: "忽略旧缓存，重新检索；通常需要 1 到 3 分钟。", .zhHant: "忽略舊快取，重新檢索；通常需要 1 到 3 分鐘。", .ja: "キャッシュを無視して再調査中。通常 1〜3 分。", .ko: "캐시를 무시하고 다시 조사 중. 보통 1–3분.", .es: "Ignorando la caché e investigando de nuevo; 1–3 minutos.", .fr: "Cache ignoré, nouvelle recherche ; 1 à 3 minutes.", .de: "Cache wird ignoriert, neue Recherche; 1–3 Minuten.", .pt: "Ignorando o cache e pesquisando de novo; 1–3 minutos.", .ru: "Кэш игнорируется, новое исследование; 1–3 минуты.", .it: "Cache ignorata, nuova ricerca; 1–3 minuti."],
        "st.cachedHit.title": [.en: "Loaded from cache", .zhHans: "已命中缓存档案", .zhHant: "已命中快取檔案", .ja: "キャッシュから読み込み", .ko: "캐시에서 불러옴", .es: "Cargado de la caché", .fr: "Chargé depuis le cache", .de: "Aus dem Cache geladen", .pt: "Carregado do cache", .ru: "Загружено из кэша", .it: "Caricato dalla cache"],
        "st.cachedHit.detail": [.en: "This track already has a fresh dossier; nothing to spend.", .zhHans: "本首歌已有新鲜缓存，不再重复检索。", .zhHant: "本首歌已有新鮮快取，不再重複檢索。", .ja: "この曲には新しい資料があります。再調査は不要。", .ko: "이 곡은 이미 최신 문서가 있습니다.", .es: "Esta pista ya tiene un dossier reciente.", .fr: "Ce morceau a déjà un dossier récent.", .de: "Dieser Titel hat bereits ein aktuelles Dossier.", .pt: "Esta faixa já tem um dossiê recente.", .ru: "У этого трека уже есть свежее досье.", .it: "Questo brano ha già un dossier recente."],
        "st.cachedStale.title": [.en: "Cache is old — updating", .zhHans: "缓存偏旧，后台更新中", .zhHant: "快取偏舊，背景更新中", .ja: "キャッシュが古いため更新中", .ko: "캐시가 오래됨 — 갱신 중", .es: "Caché antigua — actualizando", .fr: "Cache ancien — mise à jour", .de: "Cache veraltet — wird aktualisiert", .pt: "Cache antigo — atualizando", .ru: "Кэш устарел — обновляю", .it: "Cache vecchia — aggiornamento"],
        "st.cachedStale.detail": [.en: "Showing the old dossier while a new one is researched (1–3 minutes).", .zhHans: "先显示旧缓存，再后台补全最新资料（1 到 3 分钟）。", .zhHant: "先顯示舊快取，再背景補全最新資料（1 到 3 分鐘）。", .ja: "古い資料を表示しつつ新しいものを調査中（1〜3 分）。", .ko: "이전 문서를 보여주며 새 문서를 조사 중(1–3분).", .es: "Se muestra el antiguo mientras se investiga (1–3 min).", .fr: "Ancien dossier affiché pendant la recherche (1 à 3 min).", .de: "Altes Dossier sichtbar, neues wird recherchiert (1–3 Min.).", .pt: "Mostrando o antigo enquanto o novo é pesquisado (1–3 min).", .ru: "Показываю старое, пока готовится новое (1–3 мин).", .it: "Mostro il vecchio mentre si ricerca il nuovo (1–3 min)."],
        "st.updated.title": [.en: "Dossier updated", .zhHans: "研究档案已更新", .zhHant: "研究檔案已更新", .ja: "資料を更新しました", .ko: "문서 업데이트 완료", .es: "Dossier actualizado", .fr: "Dossier mis à jour", .de: "Dossier aktualisiert", .pt: "Dossiê atualizado", .ru: "Досье обновлено", .it: "Dossier aggiornato"],
        "st.updated.detail": [.en: "New notes, people and sources have been cached.", .zhHans: "新的手记、人物与来源已写入缓存。", .zhHant: "新的手記、人物與來源已寫入快取。", .ja: "新しいノート、人物、出典をキャッシュしました。", .ko: "새 노트, 인물, 출처가 캐시되었습니다.", .es: "Nuevas notas, personas y fuentes guardadas.", .fr: "Nouvelles notes, personnes et sources en cache.", .de: "Neue Notizen, Personen und Quellen gespeichert.", .pt: "Novas notas, pessoas e fontes salvas.", .ru: "Новые заметки, люди и источники сохранены.", .it: "Nuove note, persone e fonti salvate."],
        "st.byClaude": [.en: "Researched and written by Claude.", .zhHans: "由 Claude 联网检索并整理。", .zhHant: "由 Claude 聯網檢索並整理。", .ja: "Claude が調査・執筆。", .ko: "Claude가 조사하고 작성함.", .es: "Investigado y redactado por Claude.", .fr: "Recherché et rédigé par Claude.", .de: "Recherchiert und geschrieben von Claude.", .pt: "Pesquisado e escrito por Claude.", .ru: "Исследовано и написано Claude.", .it: "Ricercato e scritto da Claude."],
        "st.fallback.title": [.en: "Showing local metadata only", .zhHans: "回退到本地元数据", .zhHant: "回退到本地中繼資料", .ja: "ローカル情報のみ表示", .ko: "로컬 정보만 표시", .es: "Solo metadatos locales", .fr: "Métadonnées locales seulement", .de: "Nur lokale Metadaten", .pt: "Apenas metadados locais", .ru: "Только локальные данные", .it: "Solo metadati locali"],
        "st.fallback.detail": [.en: "The research engine or network is unavailable; the track card stays.", .zhHans: "网络或模型不可用时，会继续显示歌曲卡片。", .zhHant: "網路或模型不可用時，會繼續顯示歌曲卡片。", .ja: "調査エンジンまたはネットワークが利用不可。曲カードを表示します。", .ko: "조사 엔진 또는 네트워크 사용 불가. 곡 카드는 유지됩니다.", .es: "Motor o red no disponibles; se mantiene la ficha.", .fr: "Moteur ou réseau indisponible ; la fiche reste.", .de: "Engine oder Netz nicht verfügbar; die Titelkarte bleibt.", .pt: "Motor ou rede indisponíveis; a ficha permanece.", .ru: "Движок или сеть недоступны; карточка остаётся.", .it: "Motore o rete non disponibili; resta la scheda."],
        "st.keep.title": [.en: "Keeping the existing dossier", .zhHans: "保留现有档案", .zhHant: "保留現有檔案", .ja: "既存の資料を保持", .ko: "기존 문서 유지", .es: "Se mantiene el dossier existente", .fr: "Dossier existant conservé", .de: "Bestehendes Dossier bleibt", .pt: "Mantendo o dossiê existente", .ru: "Сохраняю существующее досье", .it: "Mantengo il dossier esistente"],
        "st.keep.detail": [.en: "The cached dossier is still readable; refresh again later.", .zhHans: "缓存内容仍可阅读，稍后可手动刷新。", .zhHant: "快取內容仍可閱讀，稍後可手動重新整理。", .ja: "キャッシュは引き続き閲覧可能。後で更新してください。", .ko: "캐시된 문서는 계속 읽을 수 있습니다. 나중에 새로고침하세요.", .es: "El dossier en caché sigue legible; reintenta más tarde.", .fr: "Le dossier en cache reste lisible ; réessayez plus tard.", .de: "Das gecachte Dossier bleibt lesbar; später erneut versuchen.", .pt: "O dossiê em cache continua legível; tente depois.", .ru: "Кэшированное досье доступно; обновите позже.", .it: "Il dossier in cache resta leggibile; riprova più tardi."],
        "st.ready.title": [.en: "Dossier ready", .zhHans: "研究档案已就绪", .zhHant: "研究檔案已就緒", .ja: "資料の準備完了", .ko: "문서 준비 완료", .es: "Dossier listo", .fr: "Dossier prêt", .de: "Dossier bereit", .pt: "Dossiê pronto", .ru: "Досье готово", .it: "Dossier pronto"],
        "st.ready.detail": [.en: "The story and timeline of this track are ready to read.", .zhHans: "本首歌的故事和时间线已经可读。", .zhHant: "本首歌的故事和時間線已經可讀。", .ja: "この曲のストーリーと年表が読めます。", .ko: "이 곡의 이야기와 타임라인을 읽을 수 있습니다.", .es: "La historia y cronología de esta pista están listas.", .fr: "L'histoire et la chronologie du morceau sont prêtes.", .de: "Geschichte und Zeitleiste dieses Titels sind lesbar.", .pt: "A história e a linha do tempo desta faixa estão prontas.", .ru: "История и хронология трека готовы.", .it: "Storia e cronologia del brano sono pronte."],
        "st.staleShown.detail": [.en: "Showing the cached dossier; the latest sources will follow.", .zhHans: "当前先展示旧缓存，稍后会补齐最新来源。", .zhHant: "目前先展示舊快取，稍後會補齊最新來源。", .ja: "キャッシュを表示中。最新の出典は後ほど。", .ko: "캐시를 표시 중. 최신 출처는 곧 추가됩니다.", .es: "Mostrando la caché; las fuentes nuevas llegarán.", .fr: "Cache affiché ; les sources récentes suivront.", .de: "Cache wird gezeigt; neue Quellen folgen.", .pt: "Mostrando o cache; as fontes novas virão.", .ru: "Показываю кэш; свежие источники подтянутся.", .it: "Mostro la cache; le fonti nuove arriveranno."],
        "st.preparing.title": [.en: "Preparing the dossier", .zhHans: "正在整理本地元数据", .zhHant: "正在整理本地中繼資料", .ja: "資料を準備中", .ko: "문서 준비 중", .es: "Preparando el dossier", .fr: "Préparation du dossier", .de: "Dossier wird vorbereitet", .pt: "Preparando o dossiê", .ru: "Готовлю досье", .it: "Preparazione del dossier"],
        "st.preparing.detail": [.en: "The track card shows first; background research follows.", .zhHans: "歌曲切换后会先显示作品卡，再继续补全背景信息。", .zhHant: "歌曲切換後會先顯示作品卡，再繼續補全背景資訊。", .ja: "先に曲カードを表示し、続いて調査します。", .ko: "먼저 곡 카드가 표시되고 조사가 이어집니다.", .es: "Primero la ficha; luego la investigación.", .fr: "La fiche d'abord, la recherche ensuite.", .de: "Zuerst die Titelkarte, dann die Recherche.", .pt: "Primeiro a ficha; depois a pesquisa.", .ru: "Сначала карточка, затем исследование.", .it: "Prima la scheda, poi la ricerca."],
        "st.automationUnavailable.title": [.en: "Music automation unavailable", .zhHans: "Music 自动化不可用", .zhHant: "Music 自動化不可用", .ja: "Music のオートメーションが使えません", .ko: "Music 자동화 사용 불가", .es: "Automatización de Música no disponible", .fr: "Automatisation de Musique indisponible", .de: "Musik-Automatisierung nicht verfügbar", .pt: "Automação do Música indisponível", .ru: "Автоматизация Музыки недоступна", .it: "Automazione di Musica non disponibile"],
        "st.automationUnavailable.detail": [.en: "Cannot read the playback state right now.", .zhHans: "当前无法读取播放状态。", .zhHant: "目前無法讀取播放狀態。", .ja: "現在、再生状態を読み取れません。", .ko: "현재 재생 상태를 읽을 수 없습니다.", .es: "No se puede leer el estado de reproducción.", .fr: "Impossible de lire l'état de lecture.", .de: "Wiedergabestatus kann nicht gelesen werden.", .pt: "Não é possível ler o estado de reprodução.", .ru: "Не удаётся прочитать состояние воспроизведения.", .it: "Impossibile leggere lo stato di riproduzione."],

        // ---- Obsidian 导出 ----
        "md.trackInfo": [.en: "Track", .zhHans: "作品信息", .zhHant: "作品資訊", .ja: "作品情報", .ko: "곡 정보", .es: "Pista", .fr: "Morceau", .de: "Titel", .pt: "Faixa", .ru: "Трек", .it: "Brano"],
        "md.artist": [.en: "Artist", .zhHans: "艺人", .zhHant: "藝人", .ja: "アーティスト", .ko: "아티스트", .es: "Artista", .fr: "Artiste", .de: "Künstler", .pt: "Artista", .ru: "Исполнитель", .it: "Artista"],
        "md.year": [.en: "Year", .zhHans: "年份", .zhHant: "年份", .ja: "年", .ko: "연도", .es: "Año", .fr: "Année", .de: "Jahr", .pt: "Ano", .ru: "Год", .it: "Anno"],
        "md.note": [.en: "Confidence note", .zhHans: "识别说明", .zhHant: "識別說明", .ja: "信頼度メモ", .ko: "신뢰도 메모", .es: "Nota de fiabilidad", .fr: "Note de fiabilité", .de: "Hinweis zur Verlässlichkeit", .pt: "Nota de confiabilidade", .ru: "Примечание о достоверности", .it: "Nota di affidabilità"],
        "md.unknown": [.en: "unknown", .zhHans: "未知", .zhHant: "未知", .ja: "不明", .ko: "알 수 없음", .es: "desconocido", .fr: "inconnu", .de: "unbekannt", .pt: "desconhecido", .ru: "неизвестно", .it: "sconosciuto"],
    ]
    // swiftlint:enable line_length
}
