import XCTest
@testable import TextCore

/// Ported from TextMate Frameworks/text/tests/t_utf8.cc (roadmap 1.T2 / 1.T3).
final class UTF8Tests: XCTestCase {

    private func scalar(_ s: String) -> UInt32 { TextUTF8.toScalar(Array(s.utf8)) }
    private func toS(_ v: UInt32) -> String { String(decoding: TextUTF8.fromScalar(v), as: UTF8.self) }
    private func sanitize(_ bytes: [UInt8]) -> [UInt8] { TextUTF8.removingMalformed(bytes) }
    // Byte-level round trip — mirrored on `std::string` (byte transparent) in the
    // C++ original, which Swift String cannot hold for values above U+10FFFF.
    private func roundTrip(_ v: UInt32) -> UInt32 { TextUTF8.toScalar(TextUTF8.fromScalar(v)) }

    func testSafeEnd() {
        let s = Array("æblegrød".utf8)
        let first = 0, last = s.count
        XCTAssertEqual(TextUTF8.findSafeEnd(s, first: first, last: first), first)
        XCTAssertEqual(TextUTF8.findSafeEnd(s, first: first, last: first + 1), first)
        XCTAssertEqual(TextUTF8.findSafeEnd(s, first: first, last: first + 2), first + 2)
        XCTAssertEqual(TextUTF8.findSafeEnd(s, first: first, last: first + 3), first + 3)
        XCTAssertEqual(TextUTF8.findSafeEnd(s, first: first, last: last), last)
        XCTAssertEqual(TextUTF8.findSafeEnd(s, first: first, last: last - 1), last - 1)
        XCTAssertEqual(TextUTF8.findSafeEnd(s, first: first, last: last - 2), last - 3)
        XCTAssertEqual(TextUTF8.findSafeEnd(s, first: first, last: last - 3), last - 3)
        XCTAssertEqual(TextUTF8.findSafeEnd(s, first: first, last: last - 4), last - 4)
        XCTAssertEqual(TextUTF8.findSafeEnd(s, first: first + 1, last: first + 2), first + 2)
    }

    func testIterate() {
        let str = "“Æblegrød…” — 𠻵"
        let expected: [UInt32] = [0x201C, 0xC6, 0x62, 0x6C, 0x65, 0x67, 0x72, 0xF8, 0x64, 0x2026, 0x201D, 0x20, 0x2014, 0x20, 0x20EF5]
        let scalars = str.unicodeScalars.map { $0.value }
        XCTAssertEqual(scalars, expected)
    }

    func testToCh() {
        XCTAssertEqual(scalar("♥"), 0x2665)
        XCTAssertEqual(scalar("𠻵"), 0x20EF5)
        XCTAssertEqual(scalar("\u{10FFFF}"), 0x10FFFF)

        XCTAssertEqual(roundTrip(0x00000003), 0x00000003)
        XCTAssertEqual(roundTrip(0x00000030), 0x00000030)
        XCTAssertEqual(roundTrip(0x00000300), 0x00000300)
        XCTAssertEqual(roundTrip(0x00003000), 0x00003000)
        XCTAssertEqual(roundTrip(0x00030000), 0x00030000)
        XCTAssertEqual(roundTrip(0x00300000), 0x00300000)
        XCTAssertEqual(roundTrip(0x03000000), 0x03000000)
        XCTAssertEqual(roundTrip(0x30000000), 0x30000000)

        XCTAssertEqual(roundTrip(0x20000003), 0x20000003)
        XCTAssertEqual(roundTrip(0x02000030), 0x02000030)
        XCTAssertEqual(roundTrip(0x00200300), 0x00200300)
        XCTAssertEqual(roundTrip(0x00023000), 0x00023000)
        XCTAssertEqual(roundTrip(0x00032000), 0x00032000)
        XCTAssertEqual(roundTrip(0x00300200), 0x00300200)
        XCTAssertEqual(roundTrip(0x03000020), 0x03000020)
        XCTAssertEqual(roundTrip(0x30000002), 0x30000002)

        XCTAssertEqual(roundTrip(0x3FFFFFFF), 0x3FFFFFFF)
        XCTAssertEqual(roundTrip(0x40000000), 0x40000000)
    }

    func testToS() {
        XCTAssertEqual(toS(0x2665), "♥")
        XCTAssertEqual(toS(0x20EF5), "𠻵")
        XCTAssertEqual(toS(0x10FFFF), "\u{10FFFF}")

        let chars: [UInt32] = [0x201C, 0xC6, 0x62, 0x6C, 0x65, 0x67, 0x72, 0xF8, 0x64, 0x2026, 0x201D, 0x20, 0x2014, 0x20, 0x20EF5]
        var str = ""
        for ch in chars { str += toS(ch) }
        XCTAssertEqual(str, "“Æblegrød…” — 𠻵")
    }

    private func b(_ array: [UInt8]) -> [UInt8] { array }
    private func eq(_ lhs: [UInt8], _ rhs: [UInt8], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs, rhs, file: file, line: line)
    }

    func testSanitize() {
        // "Æblegrød" — all valid
        eq(sanitize(b("Æblegrød".utf8.map { $0 })), b("Æblegrød".utf8.map { $0 }))

        // "Æb\xFFlegrød"
        eq(sanitize([0xC3, 0x86, 0x62, 0xFF, 0x6C, 0x65, 0x67, 0x72, 0xC3, 0xB8, 0x64]),
           b("Æblegrød".utf8.map { $0 }))
        // "Æb\xC0legrød"
        eq(sanitize([0xC3, 0x86, 0x62, 0xC0, 0x6C, 0x65, 0x67, 0x72, 0xC3, 0xB8, 0x64]),
           b("Æblegrød".utf8.map { $0 }))
        // "Æb\xC0\xFElegrød"
        eq(sanitize([0xC3, 0x86, 0x62, 0xC0, 0xFE, 0x6C, 0x65, 0x67, 0x72, 0xC3, 0xB8, 0x64]),
           b("Æblegrød".utf8.map { $0 }))
        // "Æb\xFE\xC0legrød"
        eq(sanitize([0xC3, 0x86, 0x62, 0xFE, 0xC0, 0x6C, 0x65, 0x67, 0x72, 0xC3, 0xB8, 0x64]),
           b("Æblegrød".utf8.map { $0 }))
        // "Æblegrød\xFE"
        eq(sanitize([0xC3, 0x86, 0x62, 0x6C, 0x65, 0x67, 0x72, 0xC3, 0xB8, 0x64, 0xFE]),
           b("Æblegrød".utf8.map { $0 }))

        // "x\xE2\x99\xA5y"
        eq(sanitize([0x78, 0xE2, 0x99, 0xA5, 0x79]), [0x78, 0xE2, 0x99, 0xA5, 0x79])
        // "x\xE2\x99y"
        eq(sanitize([0x78, 0xE2, 0x99, 0x79]), [0x78, 0x79])
        // "x\xE2y"
        eq(sanitize([0x78, 0xE2, 0x79]), [0x78, 0x79])
        // "x\x99\xA5y"
        eq(sanitize([0x78, 0x99, 0xA5, 0x79]), [0x78, 0x79])
        // "x\xA5y"
        eq(sanitize([0x78, 0xA5, 0x79]), [0x78, 0x79])

        // "\xE2\x99\xA5"
        eq(sanitize([0xE2, 0x99, 0xA5]), [0xE2, 0x99, 0xA5])
        // "\xE2\x99"
        eq(sanitize([0xE2, 0x99]), [])
        // "\xE2"
        eq(sanitize([0xE2]), [])
        // "\x99\xA5"
        eq(sanitize([0x99, 0xA5]), [])
        // "\xA5"
        eq(sanitize([0xA5]), [])

        // "x\xF0\xA0\xBB\xB5y" (valid 4-byte)
        eq(sanitize([0x78, 0xF0, 0xA0, 0xBB, 0xB5, 0x79]), [0x78, 0xF0, 0xA0, 0xBB, 0xB5, 0x79])
        eq(sanitize([0x78, 0xF0, 0xA0, 0xBB, 0x79]), [0x78, 0x79])
        eq(sanitize([0x78, 0xF0, 0xA0, 0x79]), [0x78, 0x79])
        eq(sanitize([0x78, 0xF0, 0x79]), [0x78, 0x79])

        eq(sanitize([0xF0, 0xA0, 0xBB, 0xB5]), [0xF0, 0xA0, 0xBB, 0xB5])
        eq(sanitize([0xF0, 0xA0, 0xBB]), [])
        eq(sanitize([0xF0, 0xA0]), [])
        eq(sanitize([0xF0]), [])
    }
}
