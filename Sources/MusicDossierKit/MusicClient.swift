import Foundation

public actor AppleScriptMusicClient {
    private let fileManager: FileManager
    private let artworkTempDirectory: URL

    public init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.artworkTempDirectory = fileManager.temporaryDirectory.appendingDirectory("music-dossier-artwork")
        try fileManager.createDirectory(at: artworkTempDirectory, withIntermediateDirectories: true)
    }

    public func fetchObservation() async throws -> MusicObservation {
        let result = try await runOsaScript(language: "JavaScript", script: Self.metadataScript)
        if result.exitCode != 0 {
            throw mapScriptFailure(result)
        }

        guard let raw = Self.extractJSONObject(from: result) else {
            throw MusicDossierError.decoding("Music 元数据不是有效 JSON。stdout=\(result.output) stderr=\(result.errorOutput)")
        }

        let status = raw["status"] as? String ?? "failed"
        let playerState = PlayerState(rawValue: (raw["playerState"] as? String ?? "").lowercased()) ?? .unknown

        switch status {
        case "not_running":
            return MusicObservation(status: .notRunning, playerState: .stopped, snapshot: nil)
        case "no_track":
            return MusicObservation(status: .noTrack, playerState: playerState, snapshot: nil)
        case "ok":
            guard let title = (raw["title"] as? String)?.trimmedNonEmpty else {
                return MusicObservation(status: .noTrack, playerState: playerState, snapshot: nil)
            }

            let releaseDate = parseDate(raw["releaseDate"] as? String)
            let snapshot = TrackSnapshot(
                persistentId: raw["persistentId"] as? String,
                databaseId: raw["databaseId"] as? Int,
                title: title,
                artist: raw["artist"] as? String,
                album: raw["album"] as? String,
                albumArtist: raw["albumArtist"] as? String,
                composer: raw["composer"] as? String,
                durationSeconds: raw["durationSeconds"] as? Double,
                genre: raw["genre"] as? String,
                year: raw["year"] as? Int,
                releaseDate: releaseDate,
                lyrics: raw["lyrics"] as? String,
                artworkData: nil,
                playerState: playerState,
                kind: raw["kind"] as? String,
                comment: raw["comment"] as? String,
                cloudStatus: raw["cloudStatus"] as? String
            )
            return MusicObservation(status: .ok, playerState: playerState, snapshot: snapshot)
        default:
            return MusicObservation(status: .failed(status), playerState: playerState, snapshot: nil)
        }
    }

    public func fetchFavoritedSnapshots(limit: Int) async throws -> [TrackSnapshot] {
        let resolvedLimit = max(0, limit)
        guard resolvedLimit > 0 else { return [] }

        let result = try await runOsaScript(language: "JavaScript", script: Self.favoritedTracksScript(limit: resolvedLimit))
        if result.exitCode != 0 {
            throw mapScriptFailure(result)
        }

        guard let rawItems = Self.extractJSONArray(from: result) else {
            throw MusicDossierError.decoding("收藏曲目列表不是有效 JSON。stdout=\(result.output) stderr=\(result.errorOutput)")
        }

        return rawItems.compactMap { raw in
            guard let title = (raw["title"] as? String)?.trimmedNonEmpty else {
                return nil
            }

            return TrackSnapshot(
                persistentId: raw["persistentId"] as? String,
                databaseId: raw["databaseId"] as? Int,
                title: title,
                artist: raw["artist"] as? String,
                album: raw["album"] as? String,
                albumArtist: raw["albumArtist"] as? String,
                composer: raw["composer"] as? String,
                durationSeconds: raw["durationSeconds"] as? Double,
                genre: raw["genre"] as? String,
                year: raw["year"] as? Int,
                releaseDate: parseDate(raw["releaseDate"] as? String),
                lyrics: nil,
                artworkData: nil,
                playerState: .stopped,
                kind: raw["kind"] as? String,
                comment: nil,
                cloudStatus: raw["cloudStatus"] as? String
            )
        }
    }

    public func exportArtwork(for snapshot: TrackSnapshot) async throws -> (data: Data, fileExtension: String)? {
        let fileName = "\(Hashing.sha256(snapshot.trackKey)).art"
        let targetURL = artworkTempDirectory.appendingFile(fileName)
        if fileManager.fileExists(atPath: targetURL.path) {
            try? fileManager.removeItem(at: targetURL)
        }

        let script = Self.artworkScript(
            expectedPersistentID: snapshot.persistentId,
            outputPath: targetURL.path
        )

        let result = try await runOsaScript(language: "JavaScript", script: script)
        if result.exitCode != 0 {
            throw mapScriptFailure(result)
        }

        let reply = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if reply == "NO_ARTWORK" || reply == "NO_TRACK" || reply == "NOT_RUNNING" {
            return nil
        }
        if reply == "MISMATCH" {
            throw MusicDossierError.artworkMismatch
        }
        if reply.hasPrefix("ERR:") {
            throw MusicDossierError.scriptingFailure(reply)
        }

        let fileExtension = Self.mapArtworkFormat(reply)
        let data = try Data(contentsOf: targetURL)
        return (data, fileExtension)
    }

    public func exportArtworkForLibraryTrack(_ snapshot: TrackSnapshot) async throws -> (data: Data, fileExtension: String)? {
        let fileName = "\(Hashing.sha256(snapshot.trackKey))-library.art"
        let targetURL = artworkTempDirectory.appendingFile(fileName)
        if fileManager.fileExists(atPath: targetURL.path) {
            try? fileManager.removeItem(at: targetURL)
        }

        let script = Self.libraryArtworkScript(snapshot: snapshot, outputPath: targetURL.path)
        let result = try await runOsaScript(language: "JavaScript", script: script)
        if result.exitCode != 0 {
            throw mapScriptFailure(result)
        }

        let reply = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if reply == "NO_ARTWORK" || reply == "NO_TRACK" || reply == "NOT_RUNNING" {
            return nil
        }
        if reply.hasPrefix("ERR:") {
            throw MusicDossierError.scriptingFailure(reply)
        }

        let fileExtension = Self.mapArtworkFormat(reply)
        let data = try Data(contentsOf: targetURL)
        return (data, fileExtension)
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value = value?.trimmedNonEmpty else { return nil }
        return DateFormatting.parseISO8601(value)
    }

    private func mapScriptFailure(_ result: ShellResult) -> Error {
        let combined = [result.errorOutput, result.output]
            .joined(separator: "\n")
            .lowercased()

        if combined.contains("-1743") || combined.contains("not authorized") || combined.contains("不允许") {
            return MusicDossierError.scriptingPermissionDenied
        }

        return MusicDossierError.scriptingFailure(result.errorOutput.trimmedNonEmpty ?? "exit \(result.exitCode)")
    }

    private func runOsaScript(language: String?, script: String) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")

            var arguments = [String]()
            if let language {
                arguments.append(contentsOf: ["-l", language])
            }
            arguments.append("-e")
            arguments.append(script)
            process.arguments = arguments

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

    private static func mapArtworkFormat(_ value: String) -> String {
        let lowercased = value.lowercased()
        if lowercased.contains("png") {
            return "png"
        }
        if lowercased.contains("gif") {
            return "gif"
        }
        return "jpg"
    }

    private static func extractJSONObject(from result: ShellResult) -> [String: Any]? {
        let candidates = [result.output, result.errorOutput]
            .compactMap(\.trimmedNonEmpty)
            .flatMap { text -> [String] in
                let trimmedLines = text
                    .split(whereSeparator: \.isNewline)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                return [text] + trimmedLines
            }

        for candidate in candidates {
            if let json = decodeJSONObject(candidate) {
                return json
            }

            guard
                let start = candidate.firstIndex(of: "{"),
                let end = candidate.lastIndex(of: "}"),
                start <= end
            else {
                continue
            }

            let slice = String(candidate[start ... end])
            if let json = decodeJSONObject(slice) {
                return json
            }
        }

        return nil
    }

    private static func extractJSONArray(from result: ShellResult) -> [[String: Any]]? {
        let candidates = [result.output, result.errorOutput]
            .compactMap(\.trimmedNonEmpty)
            .flatMap { text -> [String] in
                let trimmedLines = text
                    .split(whereSeparator: \.isNewline)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                return [text] + trimmedLines
            }

        for candidate in candidates {
            if let json = decodeJSONArray(candidate) {
                return json
            }

            guard
                let start = candidate.firstIndex(of: "["),
                let end = candidate.lastIndex(of: "]"),
                start <= end
            else {
                continue
            }

            let slice = String(candidate[start ... end])
            if let json = decodeJSONArray(slice) {
                return json
            }
        }

        return nil
    }

    private static func decodeJSONObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func decodeJSONArray(_ text: String) -> [[String: Any]]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    }

    private static let metadataScript = """
    ObjC.import('Foundation');
    function safe(fn) {
      try {
        const value = fn();
        return value === undefined ? null : value;
      } catch (error) {
        return null;
      }
    }
    function emit(payload) {
      const line = JSON.stringify(payload) + "\\n";
      const data = $(line).dataUsingEncoding($.NSUTF8StringEncoding);
      $.NSFileHandle.fileHandleWithStandardOutput.writeData(data);
    }
    const music = Application("Music");
    if (!music.running()) {
      emit({ status: "not_running", playerState: "stopped" });
    } else {
      const playerState = String(music.playerState()).toLowerCase();
      let track = null;
      try {
        track = music.currentTrack();
      } catch (error) {
        track = null;
      }
      if (!track) {
        emit({ status: "no_track", playerState });
      } else {
        const releaseDate = safe(() => {
          const date = track.releaseDate();
          return date ? (new Date(date)).toISOString() : null;
        });
        emit({
          status: "ok",
          playerState,
          title: safe(() => track.name()),
          artist: safe(() => track.artist()),
          album: safe(() => track.album()),
          albumArtist: safe(() => track.albumArtist()),
          composer: safe(() => track.composer()),
          durationSeconds: safe(() => track.duration()),
          genre: safe(() => track.genre()),
          year: safe(() => track.year()),
          releaseDate,
          lyrics: safe(() => track.lyrics()),
          kind: safe(() => track.kind()),
          comment: safe(() => track.comment()),
          cloudStatus: safe(() => String(track.cloudStatus())),
          databaseId: safe(() => track.databaseID()),
          persistentId: safe(() => track.persistentID())
        });
      }
    }
    """

    private static func favoritedTracksScript(limit: Int) -> String {
        """
        ObjC.import('Foundation');
        function safe(fn) {
          try {
            const value = fn();
            return value === undefined ? null : value;
          } catch (error) {
            return null;
          }
        }
        function emit(payload) {
          const line = JSON.stringify(payload) + "\\n";
          const data = $(line).dataUsingEncoding($.NSUTF8StringEncoding);
          $.NSFileHandle.fileHandleWithStandardOutput.writeData(data);
        }
        function isoDate(value) {
          if (!value) {
            return null;
          }
          try {
            return (new Date(value)).toISOString();
          } catch (error) {
            return null;
          }
        }
        (() => {
          const music = Application("Music");
          if (!music.running()) {
            emit([]);
            return;
          }

          const tracks = music.libraryPlaylists.length ? music.libraryPlaylists[0].tracks() : [];
          const items = [];

          for (let index = 0; index < tracks.length; index += 1) {
            const track = tracks[index];
            let favorited = false;
            try {
              favorited = !!track.favorited();
            } catch (error) {
              favorited = false;
            }
            if (!favorited) {
              continue;
            }

            items.push({
              title: safe(() => track.name()),
              artist: safe(() => track.artist()),
              album: safe(() => track.album()),
              albumArtist: safe(() => track.albumArtist()),
              composer: safe(() => track.composer()),
              durationSeconds: safe(() => track.duration()),
              genre: safe(() => track.genre()),
              year: safe(() => track.year()),
              releaseDate: isoDate(safe(() => track.releaseDate())),
              kind: safe(() => track.kind()),
              cloudStatus: safe(() => String(track.cloudStatus())),
              databaseId: safe(() => track.databaseID()),
              persistentId: safe(() => track.persistentID()),
              dateAdded: isoDate(safe(() => track.dateAdded())),
              playedCount: safe(() => track.playedCount()) || 0
            });
          }

          items.sort((lhs, rhs) => {
            const leftPlayed = lhs.playedCount || 0;
            const rightPlayed = rhs.playedCount || 0;
            if (rightPlayed !== leftPlayed) {
              return rightPlayed - leftPlayed;
            }

            const leftDate = lhs.dateAdded ? Date.parse(lhs.dateAdded) : 0;
            const rightDate = rhs.dateAdded ? Date.parse(rhs.dateAdded) : 0;
            return rightDate - leftDate;
          });

          emit(items.slice(0, \(limit)));
        })();
        """
    }

    private static func artworkScript(expectedPersistentID: String?, outputPath: String) -> String {
        let expectedID = expectedPersistentID?.trimmedNonEmpty ?? ""
        let escapedOutputPath = outputPath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedExpectedID = expectedID
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return """
        ObjC.import('Foundation');

        function hexStringToData(hexString) {
          const data = $.NSMutableData.dataWithLength(hexString.length / 2);
          const bytes = data.mutableBytes;
          for (let index = 0; index < hexString.length; index += 2) {
            bytes[index / 2] = parseInt(hexString.substr(index, 2), 16);
          }
          return data;
        }

        function writeArtworkBytes(rawValue, outputPath) {
          const match = String(rawValue).match(/\\$([0-9A-Fa-f]+)/);
          if (!match) {
            return "ERR:RAW_DATA:UNEXPECTED_FORMAT";
          }
          const data = hexStringToData(match[1]);
          const outputURL = $.NSURL.fileURLWithPath(outputPath);
          const success = data.writeToURLOptionsError(outputURL, 1, null);
          return success ? null : "ERR:WRITE_FAILED";
        }

        (() => {
          const music = Application("Music");
          if (!music.running()) {
            return "NOT_RUNNING";
          }
          try {
            const track = music.currentTrack();
            if (!track) {
              return "NO_TRACK";
            }
            if ("\(escapedExpectedID)" && String(track.persistentID()) !== "\(escapedExpectedID)") {
              return "MISMATCH";
            }

            const artworks = track.artworks();
            if (!artworks || artworks.length === 0) {
              return "NO_ARTWORK";
            }

            const artwork = artworks[0];
            const rawValue = artwork.rawData();
            const writeError = writeArtworkBytes(rawValue, "\(escapedOutputPath)");
            if (writeError) {
              return writeError;
            }

            return String(artwork.format());
          } catch (error) {
            return "ERR:" + error;
          }
        })();
        """
    }

    private static func libraryArtworkScript(snapshot: TrackSnapshot, outputPath: String) -> String {
        let escapedOutputPath = outputPath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedPersistentID = (snapshot.persistentId?.trimmedNonEmpty ?? "")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedDatabaseID = snapshot.databaseId.map(String.init) ?? ""
        let escapedTitle = snapshot.title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedArtist = (snapshot.artist?.trimmedNonEmpty ?? "")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedAlbum = (snapshot.album?.trimmedNonEmpty ?? "")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return """
        ObjC.import('Foundation');

        function hexStringToData(hexString) {
          const data = $.NSMutableData.dataWithLength(hexString.length / 2);
          const bytes = data.mutableBytes;
          for (let index = 0; index < hexString.length; index += 2) {
            bytes[index / 2] = parseInt(hexString.substr(index, 2), 16);
          }
          return data;
        }

        function writeArtworkBytes(rawValue, outputPath) {
          const match = String(rawValue).match(/\\$([0-9A-Fa-f]+)/);
          if (!match) {
            return "ERR:RAW_DATA:UNEXPECTED_FORMAT";
          }
          const data = hexStringToData(match[1]);
          const outputURL = $.NSURL.fileURLWithPath(outputPath);
          const success = data.writeToURLOptionsError(outputURL, 1, null);
          return success ? null : "ERR:WRITE_FAILED";
        }

        function normalize(value) {
          return String(value || "").trim().toLowerCase();
        }

        function safe(fn) {
          try {
            const value = fn();
            return value === undefined ? null : value;
          } catch (error) {
            return null;
          }
        }

        function matchesTrack(track) {
          const persistentID = safe(() => String(track.persistentID()));
          const databaseID = safe(() => String(track.databaseID()));
          if ("\(escapedPersistentID)" && persistentID === "\(escapedPersistentID)") {
            return true;
          }
          if ("\(escapedDatabaseID)" && databaseID === "\(escapedDatabaseID)") {
            return true;
          }

          const title = normalize(safe(() => track.name()));
          const artist = normalize(safe(() => track.artist()));
          const album = normalize(safe(() => track.album()));
          return title === normalize("\(escapedTitle)")
            && artist === normalize("\(escapedArtist)")
            && album === normalize("\(escapedAlbum)");
        }

        (() => {
          const music = Application("Music");
          if (!music.running()) {
            return "NOT_RUNNING";
          }

          try {
            const tracks = music.libraryPlaylists.length ? music.libraryPlaylists[0].tracks() : [];
            let matchedTrack = null;
            for (let index = 0; index < tracks.length; index += 1) {
              const candidate = tracks[index];
              if (matchesTrack(candidate)) {
                matchedTrack = candidate;
                break;
              }
            }

            if (!matchedTrack) {
              return "NO_TRACK";
            }

            const artworks = matchedTrack.artworks();
            if (!artworks || artworks.length === 0) {
              return "NO_ARTWORK";
            }

            const artwork = artworks[0];
            const rawValue = artwork.rawData();
            const writeError = writeArtworkBytes(rawValue, "\(escapedOutputPath)");
            if (writeError) {
              return writeError;
            }

            return String(artwork.format());
          } catch (error) {
            return "ERR:" + error;
          }
        })();
        """
    }
}
