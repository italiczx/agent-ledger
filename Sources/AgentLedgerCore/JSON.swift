import Foundation

enum JSONValue {
    static func object(data: Data) -> [String: Any]? {
        guard data.count < 2_000_000 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func pick(_ object: [String: Any], _ keys: String...) -> Any? {
        for key in keys {
            if let value = object[key], !(value is NSNull) {
                return value
            }
        }
        return nil
    }

    static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    static func array(_ value: Any?) -> [Any]? {
        value as? [Any]
    }

    static func string(_ value: Any?) -> String? {
        if value is NSNull || value == nil { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber, !(value is Bool) {
            return number.stringValue
        }
        return nil
    }

    static func bool(_ value: Any?) -> Bool? {
        guard let value, !(value is NSNull) else { return nil }
        if isJSONBoolean(value) { return (value as? NSNumber)?.boolValue ?? (value as? Bool) }
        if let string = value as? String {
            switch string.lowercased() {
            case "true", "yes": return true
            case "false", "no": return false
            default: return nil
            }
        }
        return nil
    }

    static func double(_ value: Any?) -> Double? {
        guard let value, !(value is NSNull), !isJSONBoolean(value) else { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String {
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    static func int64(_ value: Any?) -> Int64 {
        guard let value, !(value is NSNull), !isJSONBoolean(value) else { return 0 }
        if let number = value as? NSNumber { return number.int64Value }
        if let string = value as? String, let parsed = Int64(string) { return parsed }
        if let number = double(value) { return Int64(number) }
        return 0
    }

    private static func isJSONBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    static func epochDate(_ value: Any?) -> Date? {
        guard let number = double(value) else {
            if let string = string(value) { return isoDate(string) }
            return nil
        }
        if number > 10_000_000_000 {
            return Date(timeIntervalSince1970: number / 1000)
        }
        return Date(timeIntervalSince1970: number)
    }

    static func isoDate(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        if let date = basic.date(from: string) { return date }
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.timeZone = TimeZone(secondsFromGMT: 0)
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return fallback.date(from: string)
    }
}
