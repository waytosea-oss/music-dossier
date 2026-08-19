# Music Dossier · 听歌档案

[中文](README.md) · **English**

> A music critic for your Apple Music. Whatever is playing, a dossier appears beside it: **editor's notes, listening notes, album, people, gallery, anecdotes, timeline, further listening, sources** — with pictures, with citations, written in ~2 minutes, instant the next time.

![macOS](https://img.shields.io/badge/macOS-14%2B%20only-blue) ![Swift](https://img.shields.io/badge/Swift-6-orange) ![Claude](https://img.shields.io/badge/engine-Claude%20Code%20CLI-8A63D2) ![License](https://img.shields.io/badge/license-MIT-green) ![i18n](https://img.shields.io/badge/languages-11-purple)

<p align="center">
  <img src="docs/screenshots/demo-switch.gif" width="560" alt="Switch tracks, the dossier follows">
  <br><sub>Switch tracks, the dossier follows: Glenn Gould → Nirvana Unplugged → Public Service Broadcasting → Bach</sub>
</p>

<table align="center">
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/02-story.jpg" width="440" alt="Editor's notes"><br><sub>Editor's notes: three paragraphs with detail and a point of view</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/06-gallery.jpg" width="440" alt="Gallery"><br><sub>Gallery: people / original work / venue / instrument, from Wikipedia</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/05-people.jpg" width="440" alt="People"><br><sub>People: portrait + short bio + Wikipedia link</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/04-album.jpg" width="440" alt="Album"><br><sub>Album card: summary + other tracks worth hearing</sub></td>
  </tr>
</table>

<details>
<summary>📷 More screenshots (header / listen-for / anecdotes / timeline / further listening / sources / toolbar / night mode)</summary>
<p align="center">
  <img src="docs/screenshots/01-hero.jpg" width="720" alt="Header"><br><sub>Header: cover · title · artist · album · length · a one-line hook</sub><br><br>
  <img src="docs/screenshots/03-listening-notes.jpg" width="720" alt="Listen for"><br><sub>Listen for: where to put your ears</sub><br><br>
  <img src="docs/screenshots/07-anecdotes.jpg" width="720" alt="Anecdotes"><br><sub>Anecdotes, with sources</sub><br><br>
  <img src="docs/screenshots/08-timeline.jpg" width="720" alt="Timeline"><br><sub>Timeline</sub><br><br>
  <img src="docs/screenshots/09-related.jpg" width="720" alt="Further listening"><br><sub>Further listening with cover art</sub><br><br>
  <img src="docs/screenshots/10-sources.jpg" width="720" alt="Sources"><br><sub>Sources: collapsed by default; each notes what it supports</sub><br><br>
  <img src="docs/screenshots/11-toolbar.jpg" width="720" alt="Toolbar"><br><sub>Toolbar: Night · Pin · Refresh · Sources (screenshots show the Chinese UI; the panel follows your system language)</sub><br><br>
  <img src="docs/screenshots/demo-theme.gif" width="480" alt="Day / night"><br><sub>Same page, day and night</sub>
</p>
</details>

The screenshots above are from a Chinese-language session; the same layout renders in whichever language you pick.

---

## ⚠️ Before you start

| Requirement | What you need | Notes |
|---|---|---|
| OS | **macOS 14 (Sonoma) or later** | Apple Silicon or Intel (built from source) |
| Build tools | Xcode 15+ or Command Line Tools | `xcode-select --install`; Swift 6 |
| Player | **Apple Music (Music.app)** | Local library or streaming; Spotify etc. not supported yet |
| Research engine | A **logged-in Claude Code CLI** (`claude`) | Run `claude` once and `/login` |
| Cost | ~2 minutes and ~$0.2–0.5 per track | Default `claude-opus-4-8` + web search; cached tracks are free |
| Network | Access to Anthropic, Wikipedia, iTunes | Images come from Wikimedia Commons and the iTunes Search API |

**Privacy**: no server, no account. Dossiers and images live in `~/Library/Application Support/MusicDossier/`. The only data that leaves your Mac is the track's title / artist / album / length.

## 1. What it is

The things you'd like to know while a song plays — how it was written, what happened in the studio, who this person is, why it still matters — used to mean opening a browser. **Music Dossier** removes that step: it watches what Music is playing, reads a handful of sources for you, and puts an opinionated dossier next to the player.

Top to bottom, a dossier contains:

| Section | Content |
|---|---|
| **Header** | Cover · title · artist · album · length · a hook of ~15 words |
| **Editor's Notes** | ~3 paragraphs: who wrote it in what circumstances, key recording decisions, what happened after release, why it is still worth hearing |
| **Listen For** | 2–4 items pointing at concretely audible things |
| **Album** | Cover · year · label · 3–5 sentences · 2–5 other tracks worth hearing |
| **People** | 2–4 key people: Wikipedia portrait · short bio · article link |
| **Gallery** | 3–6 images: people / original work / venue / studio / instrument / related work, each with a caption and source |
| **Key Facts** | Charts, samples, film & TV use, version differences, recording technique |
| **Anecdotes** | 2–4 sourced stories |
| **Timeline** | 4–7 moments |
| **Further Listening** | 4–6 items with the relation explained, cover art auto-fetched |
| **Sources** | ≥4 openable URLs, each annotated; collapsed by default |

Verified facts and inferences are marked separately: uncertain items carry a small **inferred** tag.

## 2. Install (3 steps)

```bash
git clone https://github.com/waytosea-oss/music-dossier.git
cd music-dossier
Scripts/install.sh --launcher --autolaunch
```

1. The script checks `swift` and `claude`, builds and packages `/Applications/Music Dossier.app`, and writes a default config.
2. `--launcher` (optional): puts a launcher icon on your Desktop.
3. `--autolaunch` (optional): opens the panel automatically whenever Music.app starts — once per Music session, so closing it stays closed. Remove with `Scripts/install_autolaunch.sh --remove`.

Then `open "/Applications/Music Dossier.app"`, play a song, wait two minutes.

## 3. First launch

**1. "Allow control of Music?"** — macOS asks for Automation permission on first launch. Click **Allow**; it is the only way the panel reads the current track and cover. If you declined: System Settings → Privacy & Security → Automation → Music Dossier → tick Music.

**2. Gatekeeper** — the app is ad-hoc signed, not notarised. If macOS refuses to open it: System Settings → Privacy & Security → "Open Anyway", or `xattr -dr com.apple.quarantine "/Applications/Music Dossier.app"`.

**3. Claude Code login** — if the panel starts but stays on "Preparing the dossier", `claude` is probably not logged in:

```bash
claude        # then type /login, finish in the browser, then /exit
```

**4. Renaming** (e.g. "Tilo's Music Dossier"): put two lines in `Scripts/local.env` and run `Scripts/install.sh` again:

```bash
MUSIC_DOSSIER_APP_NAME="Tilo's Music Dossier"
MUSIC_DOSSIER_BUNDLE_ID="com.yourname.musicdossier"
```

## 4. Using it

- **11 languages** — dossier text and UI follow your system language (English, Simplified/Traditional Chinese, Japanese, Korean, Spanish, French, German, Portuguese, Russian, Italian), or pin one with `"language"` in the config.
- **Follows Music** — new track, new dossier; if you skip quickly, the previous research is cancelled so you don't pay for it.
- **Night / Day** — two colour schemes; your choice is remembered.
- **Pin** — hold the current track even when Music moves on; **Unpin** to follow again.
- **Refresh** — throw the cached dossier away and research again.
- **Sources** — open every cited page in your browser at once.
- **Cache** — researched tracks open instantly; when the cache exceeds its cap (300 MB by default) the oldest entries are pruned.
- **Obsidian mirror** (optional) — also write each dossier as Markdown (with images) into your vault, building a listening journal as you go.

## 5. Configuration

`~/Library/Application Support/MusicDossier/config.json` (copied from [`config.example.json`](config.example.json) at install):

| Key | Default | Meaning |
|---|---|---|
| `language` | `auto` | Dossier & UI language: `auto` (system) / `en` / `zh-Hans` / `zh-Hant` / `ja` / `ko` / `es` / `fr` / `de` / `pt` / `ru` / `it` |
| `researchProvider` | `claude-cli` | Engine: `claude-cli` (recommended) / `auto` / `openai-responses` / `codex-cli` |
| `claudeModel` | `claude-opus-4-8` | Passed to `claude --model` |
| `claudeEffort` | `medium` | `low` is cheaper, `high` more thorough |
| `cacheMaxAgeDays` | 30 | When a dossier counts as stale |
| `cacheMaxTotalMB` | 300 | Cap for images + pages; oldest entries pruned beyond it |
| `pollIntervalSeconds` | 1.5 | How often to ask Music what is playing |
| `enableObsidianMirror` / `obsidianVaultPath` / `obsidianExportRelativePath` | off | Write a Markdown note per track to `<vault>/20_Music Dossier/` |
| `enableFavoritesPrewarm` / `favoritesPrewarmLimit` | off | Research your favourites in the background at start-up (costs money; off by default) |
| `openAIAPIKey` / `openAIModel` / `openAIBaseURL` | empty | Alternative engines, only if you don't use Claude |

Environment variables of the same name override the file (`MUSIC_DOSSIER_LANGUAGE`, `MUSIC_DOSSIER_CLAUDE_MODEL`, `MUSIC_DOSSIER_CACHE_MAX_MB`, …).

## 6. How it works

1. **Listen** — every 1.5 s it asks Music via AppleScript for the current track: title, artist, album, length, cover (falling back to iTunes for streaming tracks without local artwork).
2. **Research** — it calls your local `claude -p` with a system prompt ("you are a senior music editor writing in *language* … verify the exact version first, then research background, people, recording details, reviews and anecdotes; at least four searches; if you can't find it, write less — never invent") and constrains the output with a JSON Schema (`--json-schema`). Transient network errors are retried twice.
3. **Pictures** — the model only decides *which Wikipedia article* an image should come from; the app fetches the article's lead image and page URL from the Wikipedia REST API. Album and further-listening covers come from the iTunes Search API. Everything is downscaled to ≤1200 px before it hits the disk. Let each side do what it is good at.
4. **Store** — SQLite for the dossier JSON, per-track image cache; missing images are back-filled when a cached dossier is shown; orphaned files and over-cap entries are pruned at start-up.

## 7. FAQ

**Q: It stays on "Preparing the dossier".**
A: Look at `~/Library/Application Support/MusicDossier/workspace/last-run.log` — it records the exit code and output of the last `claude` call. Usually the CLI is not logged in, or the network is down.

**Q: Too slow / too expensive?**
A: Set `claudeEffort` to `low`, or `claudeModel` to a cheaper model. Quality will differ.

**Q: The gallery is empty.**
A: Images are the lead images of Wikipedia articles; if an article has none, nothing is fetched. The entry is kept and retried next time the dossier is shown.

**Q: I want another language.**
A: It follows your system language by default. To pin one, set `"language": "ja"` (or `en`, `ko`, `es`, `fr`, `de`, `pt`, `ru`, `it`, `zh-Hans`, `zh-Hant`) in `config.json` and restart; UI and dossiers switch together. Already-cached tracks keep the language they were written in — press Refresh to rewrite. To add a language, add a column of strings and a language name in [`Localization.swift`](Sources/MusicDossierKit/Localization.swift) — PRs welcome.

**Q: Uninstall?**
A: `Scripts/install_autolaunch.sh --remove`; delete `/Applications/Music Dossier.app`, the Desktop launcher, and `~/Library/Application Support/MusicDossier/`.

## Platform support

| Platform | Status |
|---|---|
| macOS 14+ (Apple Silicon / Intel) | ✅ build from source, one command |
| Windows / Linux | ❌ not supported |
| Spotify / other players | ❌ not yet (PRs welcome — only a "now playing" reader is missing, see `MusicClient.swift`) |

Why macOS-only: the panel is AppKit/WebKit and the "now playing" reader is AppleScript against Music.app. The research / rendering / caching layers (`MusicDossierKit`) are plain Swift and portable — a Spotify or MPRIS reader is the missing piece.

## Development

```bash
swift build
swift run MusicDossierApp          # run without packaging
swift run MusicDossierSmokeTests   # smoke tests
script/build_and_run.sh            # stop old instance → package → open
```

```
Sources/MusicDossierKit/
  ClaudeCLIResearchClient.swift   Claude Code CLI engine (prompt, schema, retries, last-run.log)
  DossierPipeline.swift           research → images → cache → export
  HTMLRenderer.swift              page rendering (day / night palettes)
  Localization.swift              UI strings in 11 languages + language resolution
  WikipediaImageResolver.swift    Wikipedia lead images
  ITunesArtworkLookup.swift       cover art
  ImageDownscaler.swift           downscale before writing
  CacheStore.swift                SQLite + file cache, pruning
  ObsidianExporter.swift          optional Markdown mirror
  MusicClient.swift               AppleScript reader for Music
  OpenAIResearchClient.swift / CodexCLIResearchClient.swift   alternative engines
Sources/MusicDossierApp/          NSPanel + WKWebView panel and state machine
Scripts/                          install / package / launcher / autolaunch
```

## Credits

- Prompt and page structure by [Tilo Liang](https://github.com/waytosea-oss); code written with Claude.
- Images from [Wikipedia / Wikimedia Commons](https://commons.wikimedia.org) and the [iTunes Search API](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/); rights remain with their owners.

MIT License · Copyright (c) 2026 Tilo Liang
