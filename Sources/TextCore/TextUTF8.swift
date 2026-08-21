import Foundation

/// UTF-8 utilities ported from the original TextMate `text/utf8.h` (roadmap
/// 1.T3). The engine works in UTF-8 byte offsets, so these helpers mirror the
/// C++ `utf8::iterator_t` / `find_safe_end` / `to_ch` / `to_s` /
/// `remove_malformed` semantics.
///
/// Note: unlike the strict validator in `TextEncoding.isValidUTF8`, the C++
/// length-code logic accepts overlong and above-U+10FFFF sequences (it only
/// checks lead-byte + continuation structure). `removingMalformed` reproduces
/// that exact behavior, not strict UTF-8 well-formedness.
public enum TextUTF8 {

    /// Number of bytes in the sequence starting at `byte`, or nil if it is not a
    /// valid lead byte. Uses the same length-code table as the C++ original.
    static func sequenceLength(_ byte: UInt8) -> Int? {
        let codes: [(mask: UInt8, expect: UInt8)] = [
            (0x80, 0x00), // 1 byte  0x00-0x7F
            (0xE0, 0xC0), // 2 bytes 0xC0-0xDF
            (0xF0, 0xE0), // 3 bytes 0xE0-0xEF
            (0xF8, 0xF0), // 4 bytes 0xF0-0xF7
            (0xFC, 0xF8), // 5 bytes 0xF8-0xFB
            (0xFE, 0xFC), // 6 bytes 0xFC-0xFD
        ]
        for (index, code) in codes.enumerated() where (byte & code.mask) == code.expect {
            return index + 1
        }
        return nil
    }

    /// Returns `last` if `[first, last)` ends on a UTF-8 character boundary,
    /// otherwise the byte offset where the unsplit multi-byte sequence begins —
    /// mirroring `utf8::find_safe_end`.
    public static func findSafeEnd(_ bytes: [UInt8], first: Int, last: Int) -> Int {
        var it = last
        let codes: [(UInt8, UInt8)] = [(0x80, 0x00), (0xE0, 0xC0), (0xF0, 0xE0), (0xF8, 0xF0), (0xFC, 0xF8), (0xFE, 0xFC)]
        for code in codes {
            if it == first { return last }
            it -= 1
            let byte = bytes[it]
            if (byte & code.0) == code.1 { return last }
            if (byte & UInt8(0b1100_0000)) == UInt8(0b1100_0000) { return it }
        }
        return last
    }

    /// Decodes the first code point of `bytes` (`utf8::to_ch`). Supports the
    /// full 1–6 byte range up to 0x7FFFFFFF.
    public static func toScalar(_ bytes: [UInt8]) -> UInt32 {
        precondition(!bytes.isEmpty)
        var value = UInt32(bytes[0])
        var mbLength = 1
        if (value & 0xC0) == 0xC0 {
            precondition((value & 0xFE) != 0xFE)
            while value & (1 << (7 - mbLength)) != 0 { mbLength += 1 }
            precondition(bytes.count >= mbLength)
            value &= (1 << (7 - mbLength)) - 1
            for i in 1..<mbLength {
                precondition((bytes[i] & 0xC0) == 0x80)
                value = (value << 6) | UInt32(bytes[i] & 0x3F)
            }
        }
        return value
    }

    /// Encodes a code point as UTF-8 (`utf8::to_s`). Supports the full 1–6 byte
    /// range up to 0x7FFFFFFF, matching the C++ original.
    public static func fromScalar(_ scalar: UInt32) -> [UInt8] {
        var bitsLeft: UInt32 = 0
        let strLen: Int
        let head: UInt8
        let mask: UInt32
        if scalar <= 0x7F {
            strLen = 1; head = 0x00; bitsLeft =  0; mask = 0x7F
        } else if scalar <= 0x7FF {
            strLen = 2; head = 0xC0; bitsLeft =  6; mask = 0x1F
        } else if scalar <= 0xFFFF {
            strLen = 3; head = 0xE0; bitsLeft = 12; mask = 0x0F
        } else if scalar <= 0x1FFFFF {
            strLen = 4; head = 0xF0; bitsLeft = 18; mask = 0x07
        } else if scalar <= 0x3FFFFFF {
            strLen = 5; head = 0xF8; bitsLeft = 24; mask = 0x03
        } else {
            strLen = 6; head = 0xFC; bitsLeft = 30; mask = 0x01
        }
        var result = [UInt8](repeating: 0, count: strLen)
        result[0] = head | UInt8((scalar >> bitsLeft) & mask)
        var index = 1
        var left = Int(bitsLeft)
        while left >= 6 {
            left -= 6
            result[index] = 0x80 | UInt8((scalar >> UInt32(left)) & 0x3F)
            index += 1
        }
        return result
    }

    /// Removes malformed UTF-8 sequences, returning the sanitized bytes —
    /// mirroring `utf8::remove_malformed`.
    public static func removingMalformed(_ bytes: [UInt8]) -> [UInt8] {
        var dst: [UInt8] = []
        var it = 0
        let last = bytes.count
        while it < last {
            let bt = it
            var valid = false
            let codes: [(UInt8, UInt8)] = [(0x80, 0x00), (0xE0, 0xC0), (0xF0, 0xE0), (0xF8, 0xF0), (0xFC, 0xF8), (0xFE, 0xFC)]
            for code in codes {
                if (bytes[bt] & code.0) == code.1 {
                    valid = true
                    break
                }
                it += 1
                if it == last || (bytes[it] & UInt8(0b1100_0000)) != UInt8(0b1000_0000) {
                    break
                }
            }
            if valid {
                // valid sequence spans [bt, it]
                for k in bt...it where k < last {
                    dst.append(bytes[k])
                }
                it += 1
            } else {
                it = bt + 1
            }
        }
        return dst
    }
}
