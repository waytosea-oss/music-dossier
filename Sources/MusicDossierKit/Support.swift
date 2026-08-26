import CryptoKit
import Foundation

public enum MusicDossierError: LocalizedError, Sendable {
    case needsSetup
    case missingAPIKey
    case invalidConfiguration(String)
    case network(String)
    case decoding(String)
    case scriptingPermissionDenied
    case scriptingFailure(String)
    case artworkMismatch
    case cacheFailure(String)

    public var errorDescription: String? {
        switch self {
        case .needsSetup:
            return "还没有可用的写作引擎。请打开「设置」，选择一个服务商（如 DeepSeek）并粘贴 API Key。"
        case .missingAPIKey:
            return "缺少 OpenAI API Key。"
        case .invalidConfiguration(let message):
            return "配置无效：\(message)"
        case .network(let message):
            return "网络请求失败：\(message)"
        case .decoding(let message):
            return "解析数据失败：\(message)"
        case .scriptingPermissionDenied:
            return "没有获得控制 Music.app 的自动化权限。"
        case .scriptingFailure(let message):
            return "读取 Music.app 数据失败：\(message)"
        case .artworkMismatch:
            return "封面导出时歌曲已经切换。"
        case .cacheFailure(let message):
            return "缓存读写失败：\(message)"
        }
    }
}

public struct ShellResult: Sendable {
    public let output: String
    public let errorOutput: String
    public let exitCode: Int32
}

public extension String {
    func normalizedTrackToken() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    var htmlEscaped: String {
        var value = self
        let replacements = [
            ("&", "&amp;"),
            ("\"", "&quot;"),
            ("'", "&#39;"),
            ("<", "&lt;"),
            (">", "&gt;"),
        ]

        for (key, replacement) in replacements {
            value = value.replacingOccurrences(of: key, with: replacement)
        }

        return value
    }

    func decodingHTMLEntities(maxPasses: Int = 3) -> String {
        var value = self

        guard value.contains("&"), maxPasses > 0 else {
            return value
        }

        for _ in 0 ..< maxPasses {
            let previous = value
            value = value
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&apos;", with: "'")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
            value = HTMLEntityDecoder.decodeNumericEntities(in: value)
            value = value.replacingOccurrences(of: "&amp;", with: "&")

            if value == previous || !value.contains("&") {
                break
            }
        }

        return value
    }

    var htmlDisplayEscaped: String {
        decodingHTMLEntities().htmlEscaped
    }

    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum HTMLEntityDecoder {
    private static let decimalRegex = try! NSRegularExpression(pattern: "&#([0-9]{1,7});")
    private static let hexRegex = try! NSRegularExpression(pattern: "&#x([0-9A-Fa-f]{1,6});")

    static func decodeNumericEntities(in value: String) -> String {
        let hexDecoded = replacingMatches(in: value, regex: hexRegex, radix: 16)
        return replacingMatches(in: hexDecoded, regex: decimalRegex, radix: 10)
    }

    private static func replacingMatches(in value: String, regex: NSRegularExpression, radix: Int) -> String {
        let range = NSRange(value.startIndex ..< value.endIndex, in: value)
        let matches = regex.matches(in: value, range: range)
        guard !matches.isEmpty else { return value }

        var output = value
        for match in matches.reversed() {
            guard
                match.numberOfRanges > 1,
                let fullRange = Range(match.range(at: 0), in: output),
                let codeRange = Range(match.range(at: 1), in: output)
            else {
                continue
            }

            let codePointString = String(output[codeRange])
            guard
                let scalarValue = UInt32(codePointString, radix: radix),
                let scalar = UnicodeScalar(scalarValue)
            else {
                continue
            }

            output.replaceSubrange(fullRange, with: String(scalar))
        }

        return output
    }
}

public extension Optional where Wrapped == String {
    var normalizedTrackToken: String {
        self?.normalizedTrackToken() ?? ""
    }
}

public enum Hashing {
    public static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public enum ImageSniffing {
    public static func detectedFileExtension(for data: Data) -> String? {
        guard data.count >= 4 else { return nil }
        let bytes = [UInt8](data.prefix(12))

        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "jpg"
        }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "png"
        }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) {
            return "gif"
        }
        if bytes.count >= 12,
           bytes[0 ... 3].elementsEqual([0x52, 0x49, 0x46, 0x46]),
           bytes[8 ... 11].elementsEqual([0x57, 0x45, 0x42, 0x50])
        {
            return "webp"
        }
        return nil
    }

    public static func isRenderableImage(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let sample = try? handle.read(upToCount: 16) ?? Data()
        guard let sample else { return false }
        return detectedFileExtension(for: sample) != nil
    }
}

public extension URL {
    func appendingDirectory(_ name: String) -> URL {
        appendingPathComponent(name, isDirectory: true)
    }

    func appendingFile(_ name: String) -> URL {
        appendingPathComponent(name, isDirectory: false)
    }
}

public enum DateFormatting {
    private static func makeISO8601Formatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }

    public static func parseISO8601(_ value: String) -> Date? {
        makeISO8601Formatter(fractionalSeconds: true).date(from: value)
            ?? makeISO8601Formatter(fractionalSeconds: false).date(from: value)
    }

    public static func displayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy.MM.dd HH:mm"
        return formatter.string(from: date)
    }
}

public enum JSONCoding {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
