import Foundation

/// The one encoder and the one decoder the app uses for PLUG's API. Written here rather
/// than at each call site so the wire format is decided once: snake_case field names, and
/// timestamps read whether or not the server includes fractional seconds.
///
/// That last part is not a nicety. Jackson writes an Instant with nanoseconds when it has
/// them and without when it does not, so a decoder that accepts only one of the two forms
/// works in a test and fails against the real server on whichever response happens to land
/// on a whole second.
enum PlugJSON {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(withFraction.string(from: date))
        }
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = withFraction.date(from: text) ?? whole.date(from: text) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Not an ISO-8601 timestamp."))
        }
        return decoder
    }

    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let whole: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
