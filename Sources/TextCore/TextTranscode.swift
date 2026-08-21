import Foundation

/// Character-set transcoding (roadmap 3.T2 / issue #27), ported from the
/// original TextMate `text/transcode.cc` / `text/transcode.h`. Semantics match
/// the C++ original, including its escape convention: characters that cannot be
/// represented in the target charset are emitted as `\xHH` hex escapes of their
/// *source* bytes (unless `ignoreUnrepresentable` is set, in which case they are
/// dropped).
public enum TextTranscode {

    /// A character set, with TextMate's `//BOM` variants.
    public enum Charset: Equatable {
        case macintosh
        case ascii
        case isoLatin1
        case windows1252
        case utf8
        case utf8WithBOM
        case utf16LE, utf16BE
        case utf16LEWithBOM, utf16BEWithBOM
        case utf32LE, utf32BE
        case utf32LEWithBOM, utf32BEWithBOM

        /// Whether a leading byte-order mark is consumed on decode (and emitted
        /// on encode) for this charset.
        var usesBOM: Bool {
            switch self {
            case .utf8WithBOM, .utf16LEWithBOM, .utf16BEWithBOM,
                 .utf32LEWithBOM, .utf32BEWithBOM:
                return true
            default:
                return false
            }
        }

        var bom: [UInt8]? {
            switch self {
            case .utf8WithBOM: return [0xEF, 0xBB, 0xBF]
            case .utf16LEWithBOM: return [0xFF, 0xFE]
            case .utf16BEWithBOM: return [0xFE, 0xFF]
            case .utf32LEWithBOM: return [0xFF, 0xFE, 0x00, 0x00]
            case .utf32BEWithBOM: return [0x00, 0x00, 0xFE, 0xFF]
            default: return nil
            }
        }
    }

    // MARK: - Tables (generated from the platform codecs; 0xFFFF = undefined)

    private static let macRomanTable: [UInt16] = [
        0x00C4, 0x00C5, 0x00C7, 0x00C9, 0x00D1, 0x00D6, 0x00DC, 0x00E1,
        0x00E0, 0x00E2, 0x00E4, 0x00E3, 0x00E5, 0x00E7, 0x00E9, 0x00E8,
        0x00EA, 0x00EB, 0x00ED, 0x00EC, 0x00EE, 0x00EF, 0x00F1, 0x00F3,
        0x00F2, 0x00F4, 0x00F6, 0x00F5, 0x00FA, 0x00F9, 0x00FB, 0x00FC,
        0x2020, 0x00B0, 0x00A2, 0x00A3, 0x00A7, 0x2022, 0x00B6, 0x00DF,
        0x00AE, 0x00A9, 0x2122, 0x00B4, 0x00A8, 0x2260, 0x00C6, 0x00D8,
        0x221E, 0x00B1, 0x2264, 0x2265, 0x00A5, 0x00B5, 0x2202, 0x2211,
        0x220F, 0x03C0, 0x222B, 0x00AA, 0x00BA, 0x03A9, 0x00E6, 0x00F8,
        0x00BF, 0x00A1, 0x00AC, 0x221A, 0x0192, 0x2248, 0x2206, 0x00AB,
        0x00BB, 0x2026, 0x00A0, 0x00C0, 0x00C3, 0x00D5, 0x0152, 0x0153,
        0x2013, 0x2014, 0x201C, 0x201D, 0x2018, 0x2019, 0x00F7, 0x25CA,
        0x00FF, 0x0178, 0x2044, 0x20AC, 0x2039, 0x203A, 0xFB01, 0xFB02,
        0x2021, 0x00B7, 0x201A, 0x201E, 0x2030, 0x00C2, 0x00CA, 0x00C1,
        0x00CB, 0x00C8, 0x00CD, 0x00CE, 0x00CF, 0x00CC, 0x00D3, 0x00D4,
        0xF8FF, 0x00D2, 0x00DA, 0x00DB, 0x00D9, 0x0131, 0x02C6, 0x02DC,
        0x00AF, 0x02D8, 0x02D9, 0x02DA, 0x00B8, 0x02DD, 0x02DB, 0x02C7,
    ]

    private static let cp1252Table: [UInt16] = [
        0x20AC, 0xFFFF, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
        0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0xFFFF, 0x017D, 0xFFFF,
        0xFFFF, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
        0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0xFFFF, 0x017E, 0x0178,
        0x00A0, 0x00A1, 0x00A2, 0x00A3, 0x00A4, 0x00A5, 0x00A6, 0x00A7,
        0x00A8, 0x00A9, 0x00AA, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x00AF,
        0x00B0, 0x00B1, 0x00B2, 0x00B3, 0x00B4, 0x00B5, 0x00B6, 0x00B7,
        0x00B8, 0x00B9, 0x00BA, 0x00BB, 0x00BC, 0x00BD, 0x00BE, 0x00BF,
        0x00C0, 0x00C1, 0x00C2, 0x00C3, 0x00C4, 0x00C5, 0x00C6, 0x00C7,
        0x00C8, 0x00C9, 0x00CA, 0x00CB, 0x00CC, 0x00CD, 0x00CE, 0x00CF,
        0x00D0, 0x00D1, 0x00D2, 0x00D3, 0x00D4, 0x00D5, 0x00D6, 0x00D7,
        0x00D8, 0x00D9, 0x00DA, 0x00DB, 0x00DC, 0x00DD, 0x00DE, 0x00DF,
        0x00E0, 0x00E1, 0x00E2, 0x00E3, 0x00E4, 0x00E5, 0x00E6, 0x00E7,
        0x00E8, 0x00E9, 0x00EA, 0x00EB, 0x00EC, 0x00ED, 0x00EE, 0x00EF,
        0x00F0, 0x00F1, 0x00F2, 0x00F3, 0x00F4, 0x00F5, 0x00F6, 0x00F7,
        0x00F8, 0x00F9, 0x00FA, 0x00FB, 0x00FC, 0x00FD, 0x00FE, 0x00FF,
    ]

    private static var macRomanReverse: [UInt32: UInt8] = {
        var map: [UInt32: UInt8] = [:]
        for (index, scalar) in macRomanTable.enumerated() where scalar != 0xFFFF {
            map[UInt32(scalar)] = UInt8(index + 0x80)
        }
        return map
    }()

    private static var cp1252Reverse: [UInt32: UInt8] = {
        var map: [UInt32: UInt8] = [:]
        for (index, scalar) in cp1252Table.enumerated() where scalar != 0xFFFF {
            map[UInt32(scalar)] = UInt8(index + 0x80)
        }
        return map
    }()

    // MARK: - Transcoding

    /// A decoded unit: either a code point with its source bytes (for escaping),
    /// or a malformed source byte that could not be decoded.
    private enum Unit {
        case scalar(UInt32, source: [UInt8])
        case malformed(UInt8)
    }

    /// Transcodes `bytes` from `source` to `target`. Characters the target
    /// cannot represent become `\xHH` escapes of their source bytes, or are
    /// dropped when `ignoreUnrepresentable` is true.
    public static func transcode(_ bytes: [UInt8], from source: Charset, to target: Charset, ignoreUnrepresentable: Bool = false) -> [UInt8] {
        var input = bytes
        if source.usesBOM, let bom = source.bom, input.starts(with: bom) {
            input.removeFirst(bom.count)
        }

        var output: [UInt8] = []
        if let bom = target.bom { output.append(contentsOf: bom) }

        for unit in decode(input, charset: source) {
            switch unit {
            case .scalar(let scalar, let sourceBytes):
                if let encoded = encode(scalar, to: target) {
                    output.append(contentsOf: encoded)
                } else if !ignoreUnrepresentable {
                    output.append(contentsOf: escape(sourceBytes))
                }
            case .malformed(let byte):
                if !ignoreUnrepresentable {
                    output.append(contentsOf: escape([byte]))
                }
            }
        }
        return output
    }

    private static func decode(_ bytes: [UInt8], charset: Charset) -> [Unit] {
        switch charset {
        case .macintosh, .isoLatin1, .windows1252, .ascii:
            return bytes.map { byte in
                guard let scalar = singleByteScalar(byte, charset: charset) else { return .malformed(byte) }
                return .scalar(scalar, source: [byte])
            }

        case .utf8, .utf8WithBOM:
            var result: [Unit] = []
            var index = 0
            while index < bytes.count {
                let byte = bytes[index]
                if byte < 0x80 {
                    result.append(.scalar(UInt32(byte), source: [byte]))
                    index += 1
                } else if let length = TextUTF8.sequenceLength(byte), index + length <= bytes.count {
                    var valid = true
                    for k in (index + 1)..<(index + length) where (bytes[k] & 0xC0) != 0x80 { valid = false }
                    if valid {
                        let source = Array(bytes[index..<(index + length)])
                    result.append(.scalar(TextUTF8.toScalar(source), source: source))
                    index += length
                    } else {
                        result.append(.malformed(byte))
                        index += 1
                    }
                } else {
                    result.append(.malformed(byte))
                    index += 1
                }
            }
            return result

        case .utf16LE, .utf16BE, .utf16LEWithBOM, .utf16BEWithBOM:
            let little = (charset == .utf16LE || charset == .utf16LEWithBOM)
            var result: [Unit] = []
            var index = 0
            while index < bytes.count {
                guard index + 1 < bytes.count else {
                    result.append(.malformed(bytes[index]))
                    break
                }
                let unit = little
                    ? UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
                    : UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
                if unit >= 0xD800 && unit <= 0xDBFF {
                    guard index + 3 < bytes.count else {
                        result.append(.malformed(bytes[index]))
                        result.append(.malformed(bytes[index + 1]))
                        break
                    }
                    let low = little
                        ? UInt16(bytes[index + 2]) | UInt16(bytes[index + 3]) << 8
                        : UInt16(bytes[index + 2]) << 8 | UInt16(bytes[index + 3])
                    if low >= 0xDC00 && low <= 0xDFFF {
                        let scalar = 0x10000 + (UInt32(unit - 0xD800) << 10) + UInt32(low - 0xDC00)
                        result.append(.scalar(scalar, source: Array(bytes[index..<(index + 4)])))
                        index += 4
                    } else {
                        result.append(.malformed(bytes[index]))
                        result.append(.malformed(bytes[index + 1]))
                        index += 2
                    }
                } else if unit >= 0xDC00 && unit <= 0xDFFF {
                    result.append(.malformed(bytes[index]))
                    result.append(.malformed(bytes[index + 1]))
                    index += 2
                } else {
                    result.append(.scalar(UInt32(unit), source: [bytes[index], bytes[index + 1]]))
                    index += 2
                }
            }
            return result

        case .utf32LE, .utf32BE, .utf32LEWithBOM, .utf32BEWithBOM:
            let little = (charset == .utf32LE || charset == .utf32LEWithBOM)
            var result: [Unit] = []
            var index = 0
            while index < bytes.count {
                guard index + 3 < bytes.count else {
                    for k in index..<bytes.count { result.append(.malformed(bytes[k])) }
                    break
                }
                let value = little
                    ? UInt32(bytes[index]) | UInt32(bytes[index + 1]) << 8 | UInt32(bytes[index + 2]) << 16 | UInt32(bytes[index + 3]) << 24
                    : UInt32(bytes[index]) << 24 | UInt32(bytes[index + 1]) << 16 | UInt32(bytes[index + 2]) << 8 | UInt32(bytes[index + 3])
                if value <= 0x10FFFF && !(value >= 0xD800 && value <= 0xDFFF) {
                    result.append(.scalar(value, source: Array(bytes[index..<(index + 4)])))
                } else {
                    for k in index..<(index + 4) { result.append(.malformed(bytes[k])) }
                }
                index += 4
            }
            return result
        }
    }

    private static func singleByteScalar(_ byte: UInt8, charset: Charset) -> UInt32? {
        switch charset {
        case .isoLatin1: return UInt32(byte)
        case .ascii: return byte <= 0x7F ? UInt32(byte) : nil
        case .macintosh:
            return byte < 0x80 ? UInt32(byte) : UInt32(macRomanTable[Int(byte) - 0x80])
        case .windows1252:
            if byte < 0x80 { return UInt32(byte) }
            let scalar = cp1252Table[Int(byte) - 0x80]
            return scalar == 0xFFFF ? nil : UInt32(scalar)
        default: return nil
        }
    }

    private static func encode(_ scalar: UInt32, to target: Charset) -> [UInt8]? {
        switch target {
        case .ascii: return scalar <= 0x7F ? [UInt8(scalar)] : nil
        case .isoLatin1: return scalar <= 0xFF ? [UInt8(scalar)] : nil
        case .macintosh:
            if scalar < 0x80 { return [UInt8(scalar)] } // ASCII is a subset
            return macRomanReverse[scalar].map { [$0] }
        case .windows1252:
            if scalar < 0x80 { return [UInt8(scalar)] }
            return cp1252Reverse[scalar].map { [$0] }
        case .utf8, .utf8WithBOM: return TextUTF8.fromScalar(scalar)
        case .utf16LE, .utf16LEWithBOM: return utf16(scalar, little: true)
        case .utf16BE, .utf16BEWithBOM: return utf16(scalar, little: false)
        case .utf32LE, .utf32LEWithBOM: return utf32(scalar, little: true)
        case .utf32BE, .utf32BEWithBOM: return utf32(scalar, little: false)
        }
    }

    private static func utf16(_ scalar: UInt32, little: Bool) -> [UInt8] {
        var units: [UInt16]
        if scalar <= 0xFFFF {
            units = [UInt16(scalar)]
        } else {
            let value = scalar - 0x10000
            units = [UInt16(0xD800 + (value >> 10)), UInt16(0xDC00 + (value & 0x3FF))]
        }
        return units.flatMap { unit -> [UInt8] in
            little ? [UInt8(unit & 0xFF), UInt8(unit >> 8)] : [UInt8(unit >> 8), UInt8(unit & 0xFF)]
        }
    }

    private static func utf32(_ scalar: UInt32, little: Bool) -> [UInt8] {
        little
            ? [UInt8(scalar & 0xFF), UInt8((scalar >> 8) & 0xFF), UInt8((scalar >> 16) & 0xFF), UInt8((scalar >> 24) & 0xFF)]
            : [UInt8((scalar >> 24) & 0xFF), UInt8((scalar >> 16) & 0xFF), UInt8((scalar >> 8) & 0xFF), UInt8(scalar & 0xFF)]
    }

    /// `\xHH` escape of a source byte, as ASCII bytes (uppercase hex, matching
    /// the C++ original).
    private static func escape(_ source: [UInt8]) -> [UInt8] {
        let hex: [UInt8] = Array("0123456789ABCDEF".utf8)
        return source.flatMap { byte -> [UInt8] in
            [0x5C, 0x78, hex[Int(byte >> 4)], hex[Int(byte & 0x0F)]]
        }
    }

    // MARK: - Document encoding detection (roadmap 3.S1)

    /// Detects the charset of a byte sequence: BOM-based, then strict UTF-8,
    /// then single-byte fallbacks (Windows-1252, MacRoman, ISO Latin-1).
    public static func detect(_ bytes: [UInt8]) -> Charset {
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return .utf8WithBOM }
        if bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) { return .utf32BEWithBOM }
        if bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00]) { return .utf32LEWithBOM }
        if bytes.starts(with: [0xFE, 0xFF]) { return .utf16BEWithBOM }
        if bytes.starts(with: [0xFF, 0xFE]) { return .utf16LEWithBOM }
        if TextEncoding.isValidUTF8(bytes) { return .utf8 }
        // Single-byte heuristics: CP1252 if the 0x80–0x9F range is used (Latin-1
        // would show control chars there), otherwise MacRoman if high bytes map
        // to something other than Latin-1, else Latin-1 (never fails).
        var hasCP1252Range = false
        var hasHighBytes = false
        for byte in bytes where byte >= 0x80 {
            hasHighBytes = true
            if byte <= 0x9F { hasCP1252Range = true }
        }
        if !hasHighBytes { return .ascii }
        if hasCP1252Range { return .windows1252 }
        for byte in bytes where byte >= 0x80 {
            let latin1 = UInt32(byte)
            if macRomanTable[Int(byte) - 0x80] != latin1 { return .macintosh }
        }
        return .isoLatin1
    }

    /// Decodes bytes in `charset` to a Swift String (nil on failure).
    public static func string(from bytes: [UInt8], charset: Charset) -> String? {
        switch charset {
        case .macintosh, .isoLatin1, .windows1252, .ascii:
            let encoding: String.Encoding
            switch charset {
            case .macintosh: encoding = .macOSRoman
            case .windows1252: encoding = .windowsCP1252
            case .ascii: encoding = .ascii
            default: encoding = .isoLatin1
            }
            return String(data: Data(bytes), encoding: encoding)
        case .utf8:
            return String(decoding: bytes, as: UTF8.self)
        case .utf8WithBOM:
            var stripped = bytes
            if stripped.starts(with: [0xEF, 0xBB, 0xBF]) { stripped.removeFirst(3) }
            return String(decoding: stripped, as: UTF8.self)
        case .utf16LEWithBOM:
            return String(data: Data(bytes), encoding: .utf16) // BOM-aware
        case .utf16BEWithBOM:
            return String(data: Data(bytes), encoding: .utf16BigEndian)
        case .utf16LE:
            return String(data: Data(bytes), encoding: .utf16LittleEndian)
        case .utf16BE:
            return String(data: Data(bytes), encoding: .utf16BigEndian)
        case .utf32LEWithBOM:
            return String(data: Data(bytes), encoding: .utf32LittleEndian)
        case .utf32BEWithBOM:
            return String(data: Data(bytes), encoding: .utf32BigEndian)
        case .utf32LE:
            return String(data: Data(bytes), encoding: .utf32LittleEndian)
        case .utf32BE:
            return String(data: Data(bytes), encoding: .utf32BigEndian)
        }
    }

    /// Encodes a string into `charset` bytes, preserving a BOM when the charset
    /// uses one (nil on failure).
    public static func data(from string: String, charset: Charset) -> [UInt8]? {
        switch charset {
        case .macintosh, .isoLatin1, .windows1252, .ascii:
            let encoding: String.Encoding
            switch charset {
            case .macintosh: encoding = .macOSRoman
            case .windows1252: encoding = .windowsCP1252
            case .ascii: encoding = .ascii
            default: encoding = .isoLatin1
            }
            return string.data(using: encoding).map { [UInt8]($0) }
        case .utf8:
            return Array(string.utf8)
        case .utf8WithBOM:
            return [0xEF, 0xBB, 0xBF] + Array(string.utf8)
        case .utf16LE:
            return string.data(using: .utf16LittleEndian).map { [UInt8]($0) }
        case .utf16BE:
            return string.data(using: .utf16BigEndian).map { [UInt8]($0) }
        case .utf16LEWithBOM:
            var out: [UInt8] = [0xFF, 0xFE]
            if let data = string.data(using: .utf16LittleEndian) { out.append(contentsOf: data) }
            return out
        case .utf16BEWithBOM:
            var out: [UInt8] = [0xFE, 0xFF]
            if let data = string.data(using: .utf16BigEndian) { out.append(contentsOf: data) }
            return out
        case .utf32LE:
            return string.data(using: .utf32LittleEndian).map { [UInt8]($0) }
        case .utf32BE:
            return string.data(using: .utf32BigEndian).map { [UInt8]($0) }
        case .utf32LEWithBOM:
            var out: [UInt8] = [0xFF, 0xFE, 0x00, 0x00]
            if let data = string.data(using: .utf32LittleEndian) { out.append(contentsOf: data) }
            return out
        case .utf32BEWithBOM:
            var out: [UInt8] = [0x00, 0x00, 0xFE, 0xFF]
            if let data = string.data(using: .utf32BigEndian) { out.append(contentsOf: data) }
            return out
        }
    }
}
