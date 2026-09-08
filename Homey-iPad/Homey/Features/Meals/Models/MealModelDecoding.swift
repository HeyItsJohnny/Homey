import Foundation

enum MealModelDecoding {
    static func decodeDecimalIfPresent<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> Decimal? {
        guard container.contains(key), try !container.decodeNil(forKey: key) else {
            return nil
        }

        if let decimal = try? container.decode(Decimal.self, forKey: key) {
            return decimal
        }

        if let double = try? container.decode(Double.self, forKey: key) {
            return Decimal(double)
        }

        if let string = try? container.decode(String.self, forKey: key) {
            let trimmedValue = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedValue.isEmpty {
                return nil
            }
            if let decimal = Decimal(string: trimmedValue, locale: Locale(identifier: "en_US_POSIX")) {
                return decimal
            }
        }

        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Expected a decimal number, numeric string, or null."
        )
    }
}
