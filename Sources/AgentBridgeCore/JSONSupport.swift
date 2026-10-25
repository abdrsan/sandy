import Foundation

public typealias JSONObject = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? { self[key] as? String }
    func object(_ key: String) -> JSONObject? { self[key] as? JSONObject }
    func array(_ key: String) -> [Any]? { self[key] as? [Any] }
    func int(_ key: String) -> Int? {
        guard let number = self[key] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.intValue
    }
}

enum JSONSupport {
    static func object(from data: Data) -> JSONObject? {
        guard !data.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? JSONObject
    }

    /// Первое строковое значение поля `"key":"…"` в куске сырого JSON.
    /// Нужен для строк, которые не влезли в предел длины и не разбираются целиком.
    static func sniffString(_ key: String, in text: String) -> String? {
        let pattern = "\"" + NSRegularExpression.escapedPattern(for: key) + "\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        // Значение в кавычках — валидная JSON-строка, разворачиваем экранирование.
        let quoted = "\"" + text[range] + "\""
        return (try? JSONSerialization.jsonObject(with: Data(quoted.utf8), options: [.fragmentsAllowed])) as? String
    }

    /// Все строковые значения поля по порядку.
    static func sniffStrings(_ key: String, in text: String) -> [String] {
        let pattern = "\"" + NSRegularExpression.escapedPattern(for: key) + "\"\\s*:\\s*\"([^\"\\\\]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    /// Последнее целое значение поля `"key":123`.
    static func sniffLastInt(_ key: String, in text: String) -> Int? {
        let pattern = "\"" + NSRegularExpression.escapedPattern(for: key) + "\"\\s*:\\s*(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[range])
    }
}

/// Строка, пригодная для идентификатора: буквы, цифры и `-_.:`.
enum Identifier {
    static func sanitized(_ raw: String?, maxLength: Int = 128) -> String? {
        guard let raw, !raw.isEmpty, raw.count <= maxLength else { return nil }
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:")
        guard raw.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return raw
    }

    /// Абсолютный путь без управляющих символов.
    static func path(_ raw: String?, maxLength: Int = 4096) -> String? {
        guard let raw, raw.hasPrefix("/"), raw.utf8.count <= maxLength,
              !raw.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
        else { return nil }
        return raw
    }
}
