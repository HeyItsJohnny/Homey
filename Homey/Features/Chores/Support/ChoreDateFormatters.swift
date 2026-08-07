import Foundation

struct ChoreLocalTime: Codable, Hashable, Sendable, RawRepresentable {
    let rawValue: String

    init?(rawValue: String) {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ChoreLocalTimeFormatter.isValid(trimmedValue) else {
            return nil
        }
        self.rawValue = trimmedValue
    }

    init(hour: Int, minute: Int, second: Int = 0) {
        self.rawValue = String(format: "%02d:%02d:%02d", hour, minute, second)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let time = ChoreLocalTime(rawValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid Postgres time value: \(value)"
            )
        }
        self = time
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum ChoreDateOnlyFormatter {
    static func string(from date: Date, timezone: String) -> String {
        CalendarDateOnlyFormatter.string(from: date, timezone: timezone)
    }

    static func date(from value: String) -> Date? {
        CalendarDateOnlyFormatter.date(from: value)
    }
}

enum ChoreTimestampFormatter {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func string(from date: Date) -> String {
        fractionalFormatter.string(from: date)
    }
}

enum ChoreLocalTimeFormatter {
    private static let pattern = /^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$/

    static func isValid(_ value: String) -> Bool {
        value.wholeMatch(of: pattern) != nil
    }
}
