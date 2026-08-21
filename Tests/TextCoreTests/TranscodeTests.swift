import XCTest
@testable import TextCore

/// Ported from the original TextMate `text/tests/t_transcode.cc` (roadmap 3.T2 /
/// issue #27). The C++ suite runs each case through both a batch converter and
/// a streaming one; results are identical, so the Swift batch implementation
/// covers both paths.
final class TranscodeTests: XCTestCase {

    /// `"\xAEblegr\xBFd"` — "Æblegrød" in MacRoman.
    private let macRoman: [UInt8] = [0xAE, 0x62, 0x6C, 0x65, 0x67, 0x72, 0xBF, 0x64]

    private func escaped(_ string: String) -> [UInt8] { Array(string.utf8) }

    func testCharsetConversions() {
        // MACINTOSH → UTF-8 / UTF-8//BOM
        XCTAssertEqual(TextTranscode.transcode(macRoman, from: .macintosh, to: .utf8), Array("Æblegrød".utf8))
        XCTAssertEqual(
            TextTranscode.transcode(macRoman, from: .macintosh, to: .utf8WithBOM),
            [0xEF, 0xBB, 0xBF] + Array("Æblegrød".utf8)
        )

        // MACINTOSH → ASCII (unrepresentable chars become \xHH escapes)
        XCTAssertEqual(
            TextTranscode.transcode(macRoman, from: .macintosh, to: .ascii),
            escaped("\\xAEblegr\\xBFd")
        )
        XCTAssertEqual(
            TextTranscode.transcode(macRoman, from: .macintosh, to: .ascii, ignoreUnrepresentable: true),
            escaped("blegrd")
        )

        // UTF-8 → MACINTOSH
        XCTAssertEqual(
            TextTranscode.transcode(Array("Æblegrød".utf8), from: .utf8, to: .macintosh),
            macRoman
        )
        // UTF-8//BOM strips the leading BOM
        XCTAssertEqual(
            TextTranscode.transcode([0xEF, 0xBB, 0xBF] + Array("Æblegrød".utf8), from: .utf8WithBOM, to: .macintosh),
            macRoman
        )
        // UTF-8 (no BOM variant) with a stray BOM char → escaped as its source bytes
        XCTAssertEqual(
            TextTranscode.transcode([0xEF, 0xBB, 0xBF] + Array("Æblegrød".utf8), from: .utf8, to: .macintosh),
            escaped("\\xEF\\xBB\\xBF") + macRoman
        )

        // UTF-8 → ISO-8859-1: Æ/ø are representable (literal 0xC6/0xF8), the
        // malformed 0xA0 byte is escaped. Mirrors the C++ expected string
        // "\xC6""ble\\xA0gr\xF8""d" where \xC6/\xF8 are hex escapes.
        let latin1Input: [UInt8] = [0xC3, 0x86, 0x62, 0x6C, 0x65, 0xA0, 0x67, 0x72, 0xC3, 0xB8, 0x64]
        var expectedLatin1: [UInt8] = [0xC6]
        expectedLatin1 += Array("ble".utf8)
        expectedLatin1 += escaped("\\xA0")
        expectedLatin1 += Array("gr".utf8)
        expectedLatin1 += [0xF8]
        expectedLatin1 += Array("d".utf8)
        XCTAssertEqual(
            TextTranscode.transcode(latin1Input, from: .utf8, to: .isoLatin1),
            expectedLatin1
        )

        // UTF-8 → WINDOWS-1252 (€ → 0x80; incomplete sequences escaped)
        XCTAssertEqual(
            TextTranscode.transcode([0xE2, 0x82, 0xAC], from: .utf8, to: .windows1252),
            [0x80]
        )
        XCTAssertEqual(
            TextTranscode.transcode([0xE2, 0x82], from: .utf8, to: .windows1252),
            escaped("\\xE2\\x82")
        )
        XCTAssertEqual(
            TextTranscode.transcode([0xE2], from: .utf8, to: .windows1252),
            escaped("\\xE2")
        )
    }

    func testBOMStrip() {
        // UTF-32/16 with BOM → UTF-8
        XCTAssertEqual(
            TextTranscode.transcode([0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0x00, 0x51], from: .utf32BEWithBOM, to: .utf8),
            Array("Q".utf8)
        )
        XCTAssertEqual(
            TextTranscode.transcode([0xFF, 0xFE, 0x00, 0x00, 0x51, 0x00, 0x00, 0x00], from: .utf32LEWithBOM, to: .utf8),
            Array("Q".utf8)
        )
        XCTAssertEqual(
            TextTranscode.transcode([0xFE, 0xFF, 0x00, 0x51], from: .utf16BEWithBOM, to: .utf8),
            Array("Q".utf8)
        )
        XCTAssertEqual(
            TextTranscode.transcode([0xFF, 0xFE, 0x51, 0x00], from: .utf16LEWithBOM, to: .utf8),
            Array("Q".utf8)
        )
    }

    func testBOMEmit() {
        // UTF-8 → UTF-32/16 with BOM
        XCTAssertEqual(
            TextTranscode.transcode(Array("Q".utf8), from: .utf8, to: .utf32BEWithBOM),
            [0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0x00, 0x51]
        )
        XCTAssertEqual(
            TextTranscode.transcode(Array("Q".utf8), from: .utf8, to: .utf32LEWithBOM),
            [0xFF, 0xFE, 0x00, 0x00, 0x51, 0x00, 0x00, 0x00]
        )
        XCTAssertEqual(
            TextTranscode.transcode(Array("Q".utf8), from: .utf8, to: .utf16BEWithBOM),
            [0xFE, 0xFF, 0x00, 0x51]
        )
        XCTAssertEqual(
            TextTranscode.transcode(Array("Q".utf8), from: .utf8, to: .utf16LEWithBOM),
            [0xFF, 0xFE, 0x51, 0x00]
        )
    }

    func testNoBOM() {
        XCTAssertEqual(
            TextTranscode.transcode(Array("Q".utf8), from: .utf8, to: .utf32BE),
            [0x00, 0x00, 0x00, 0x51]
        )
        XCTAssertEqual(
            TextTranscode.transcode(Array("Q".utf8), from: .utf8, to: .utf32LE),
            [0x51, 0x00, 0x00, 0x00]
        )
        XCTAssertEqual(
            TextTranscode.transcode(Array("Q".utf8), from: .utf8, to: .utf16BE),
            [0x00, 0x51]
        )
        XCTAssertEqual(
            TextTranscode.transcode(Array("Q".utf8), from: .utf8, to: .utf16LE),
            [0x51, 0x00]
        )
    }

    func testSurrogatePairRoundTrip() {
        // U+1F600 😀 survives UTF-16 surrogate pairing.
        let emoji = Array("😀".utf8)
        let utf16BE = TextTranscode.transcode(emoji, from: .utf8, to: .utf16BE)
        XCTAssertEqual(utf16BE, [0xD8, 0x3D, 0xDE, 0x00])
        XCTAssertEqual(TextTranscode.transcode(utf16BE, from: .utf16BE, to: .utf8), emoji)
    }

    // MARK: - Detection (document layer)

    func testDetection() {
        XCTAssertEqual(TextTranscode.detect([0xEF, 0xBB, 0xBF] + Array("hi".utf8)), .utf8WithBOM)
        XCTAssertEqual(TextTranscode.detect([0xFF, 0xFE, 0x51, 0x00]), .utf16LEWithBOM)
        XCTAssertEqual(TextTranscode.detect([0xFE, 0xFF, 0x00, 0x51]), .utf16BEWithBOM)
        XCTAssertEqual(TextTranscode.detect([0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0x00, 0x51]), .utf32BEWithBOM)
        XCTAssertEqual(TextTranscode.detect([0xFF, 0xFE, 0x00, 0x00, 0x51, 0x00, 0x00, 0x00]), .utf32LEWithBOM)
        XCTAssertEqual(TextTranscode.detect(Array("plain text".utf8)), .utf8)
        XCTAssertEqual(TextTranscode.detect([0xE2, 0x82, 0xAC]), .utf8) // € is valid UTF-8
        XCTAssertEqual(TextTranscode.detect([0xAE, 0x62]), .macintosh) // MacRoman high byte
        XCTAssertEqual(TextTranscode.detect([0x80]), .windows1252)     // CP1252-range byte
        XCTAssertEqual(TextTranscode.detect([0xE9]), .macintosh)       // é in MacRoman (0xE9 ≠ Latin-1 0xE9? — equal, so falls through)
    }

    func testDocumentRoundTrip() {
        // Bytes that decode via MacRoman and re-encode to the same bytes.
        let original: [UInt8] = [0xAE, 0x62, 0x6C, 0x65, 0x67, 0x72, 0xBF, 0x64]
        let charset = TextTranscode.detect(original)
        XCTAssertEqual(charset, .macintosh)
        guard let text = TextTranscode.string(from: original, charset: charset) else {
            return XCTFail("decode failed")
        }
        XCTAssertEqual(text, "Æblegrød")
        XCTAssertEqual(TextTranscode.data(from: text, charset: charset), original)
    }

    func testUTF16DocumentRoundTrip() {
        let body = "héllo wörld".data(using: .utf16LittleEndian).map { [UInt8]($0) } ?? []
        let original = [0xFF, 0xFE] + body
        let charset = TextTranscode.detect(original)
        XCTAssertEqual(charset, .utf16LEWithBOM)
        guard let text = TextTranscode.string(from: original, charset: charset) else {
            return XCTFail("decode failed")
        }
        XCTAssertEqual(text, "héllo wörld")
        XCTAssertEqual(TextTranscode.data(from: text, charset: charset), original)
    }
}
