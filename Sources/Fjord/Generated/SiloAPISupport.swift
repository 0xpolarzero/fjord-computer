import Foundation

/// A lossless Codable value for schema fields whose payload is deliberately open JSON.
enum SiloJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case signed(Int64)
    case unsigned(UInt64)
    case decimal(Decimal)
    case double(Double)
    case string(String)
    case array([SiloJSONValue])
    case object([String: SiloJSONValue])

    init(from decoder: Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            var values: [SiloJSONValue] = []
            while !array.isAtEnd { values.append(try array.decode(SiloJSONValue.self)) }
            self = .array(values)
            return
        }
        if let object = try? decoder.container(keyedBy: SiloJSONKey.self) {
            var values: [String: SiloJSONValue] = [:]
            for key in object.allKeys { values[key.stringValue] = try object.decode(SiloJSONValue.self, forKey: key) }
            self = .object(values)
            return
        }

        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let signed = try? value.decode(Int64.self) { self = .signed(signed) }
        else if let unsigned = try? value.decode(UInt64.self) { self = .unsigned(unsigned) }
        else if let decimal = try? value.decode(Decimal.self) { self = .decimal(decimal) }
        else if let double = try? value.decode(Double.self) { self = .double(double) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else {
            throw DecodingError.typeMismatch(SiloJSONValue.self, .init(codingPath: decoder.codingPath,
                debugDescription: "Expected a JSON value."))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .signed(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .unsigned(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .decimal(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .double(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .array(let value):
            var container = encoder.unkeyedContainer()
            for member in value { try container.encode(member) }
        case .object(let value):
            var container = encoder.container(keyedBy: SiloJSONKey.self)
            for (key, member) in value { try container.encode(member, forKey: SiloJSONKey(stringValue: key)) }
        }
    }
}

private struct SiloJSONKey: CodingKey, Hashable {
    var stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

/// Codable representation of Rust's checked `DisplayAxis(u16)` range.
struct SiloDisplayAxis: Codable, Equatable, Sendable {
    let rawValue: UInt16

    init(_ value: UInt16) throws {
        guard value <= 32_767 else { throw Self.outOfRange() }
        rawValue = value
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(UInt16.self)
        guard value <= 32_767 else { throw Self.outOfRange(codingPath: decoder.codingPath) }
        rawValue = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func outOfRange(codingPath: [CodingKey] = []) -> DecodingError {
        .dataCorrupted(.init(codingPath: codingPath, debugDescription: "Display axis must be between 0 and 32767."))
    }
}

/// A method result whose canonical JSON value is `null`.
struct SiloNull: Codable, Equatable, Sendable {
    init() {}

    init(from decoder: Decoder) throws {
        guard try decoder.singleValueContainer().decodeNil() else {
            throw DecodingError.typeMismatch(SiloNull.self, .init(codingPath: decoder.codingPath,
                debugDescription: "Expected JSON null."))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}
