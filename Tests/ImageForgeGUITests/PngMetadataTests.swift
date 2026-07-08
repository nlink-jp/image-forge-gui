import XCTest
@testable import ImageForgeGUI

/// Exercises the pure PNG text-chunk parser against chunks built in-code with
/// correct CRC-32 (mirroring image-forge's `internal/engine/pngmeta.go` writer).
final class PngMetadataTests: XCTestCase {
    /// A `tEXt` `image-forge` JSON chunk decodes prompt / seed / size and friends.
    func testDecodesForgeJSONFromTEXt() throws {
        let json = """
        {"prompt":"a red apple","negative":"blurry","seed":12345,"steps":30,\
        "cfg":7,"width":512,"height":768,"model":"realvisxl-v5",\
        "sampler":"euler_a","scheduler":"karras"}
        """
        let png = pngWith([tEXt("image-forge", json)])
        let meta = try XCTUnwrap(PngMetadata.read(png))
        XCTAssertEqual(meta.prompt, "a red apple")
        XCTAssertEqual(meta.negative, "blurry")
        XCTAssertEqual(meta.seed, 12345)
        XCTAssertEqual(meta.steps, 30)
        XCTAssertEqual(meta.cfg, 7)
        XCTAssertEqual(meta.width, 512)
        XCTAssertEqual(meta.height, 768)
        XCTAssertEqual(meta.model, "realvisxl-v5")
        XCTAssertEqual(meta.sampler, "euler_a")
        XCTAssertEqual(meta.scheduler, "karras")
    }

    /// A UTF-8 `iTXt` chunk round-trips a Japanese prompt.
    func testDecodesJapanesePromptFromITXt() throws {
        let json = #"{"prompt":"赤いりんご、山の風景","seed":999,"width":640,"height":640}"#
        let png = pngWith([iTXt("image-forge", json)])
        let meta = try XCTUnwrap(PngMetadata.read(png))
        XCTAssertEqual(meta.prompt, "赤いりんご、山の風景")
        XCTAssertEqual(meta.seed, 999)
        XCTAssertEqual(meta.width, 640)
        XCTAssertEqual(meta.height, 640)
    }

    /// A PNG with no text chunks yields nil.
    func testNoTextChunksReturnsNil() {
        XCTAssertNil(PngMetadata.read(pngWith([])))
    }

    /// Non-PNG data yields nil.
    func testNonPNGReturnsNil() {
        XCTAssertNil(PngMetadata.read(Data([0x00, 0x01, 0x02, 0x03])))
    }

    /// The AUTOMATIC1111 `parameters` chunk is used when there's no `image-forge`
    /// JSON: line 1 is the prompt, then the negative + settings lines.
    func testFallsBackToA1111Parameters() throws {
        let params = """
        a scenic mountain
        Negative prompt: lowres, blurry
        Steps: 24, Sampler: euler, CFG scale: 5.5, Seed: 77, Size: 832x1216, Model: juggernaut
        """
        let png = pngWith([tEXt("parameters", params)])
        let meta = try XCTUnwrap(PngMetadata.read(png))
        XCTAssertEqual(meta.prompt, "a scenic mountain")
        XCTAssertEqual(meta.negative, "lowres, blurry")
        XCTAssertEqual(meta.seed, 77)
        XCTAssertEqual(meta.steps, 24)
        XCTAssertEqual(meta.cfg, 5.5)
        XCTAssertEqual(meta.width, 832)
        XCTAssertEqual(meta.height, 1216)
        XCTAssertEqual(meta.sampler, "euler")
        XCTAssertEqual(meta.model, "juggernaut")
    }

    /// The `image-forge` JSON is preferred over `parameters` when both are present.
    func testForgeJSONPreferredOverParameters() throws {
        let png = pngWith([
            tEXt("parameters", "wrong prompt\nSteps: 1, Seed: 1, Size: 8x8"),
            tEXt("image-forge", #"{"prompt":"right prompt","seed":42}"#),
        ])
        let meta = try XCTUnwrap(PngMetadata.read(png))
        XCTAssertEqual(meta.prompt, "right prompt")
        XCTAssertEqual(meta.seed, 42)
    }

    // MARK: - PNG assembly helpers (mirror pngmeta.go)

    /// A minimal PNG: signature + IHDR (1×1 RGB) + the given chunks + IEND.
    private func pngWith(_ chunks: [[UInt8]]) -> Data {
        var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let ihdr: [UInt8] = be(1) + be(1) + [8, 2, 0, 0, 0] // w, h, depth, RGB, comp, filter, interlace
        bytes += chunk("IHDR", ihdr)
        for c in chunks { bytes += c }
        bytes += chunk("IEND", [])
        return Data(bytes)
    }

    /// `tEXt`: keyword \0 latin1(text).
    private func tEXt(_ keyword: String, _ text: String) -> [UInt8] {
        var data = Array(keyword.utf8)
        data.append(0x00)
        data += text.unicodeScalars.map { UInt8($0.value & 0xFF) } // Latin-1
        return chunk("tEXt", data)
    }

    /// `iTXt`: keyword \0 compFlag(0) compMethod(0) langtag\0 transkw\0 utf8(text).
    private func iTXt(_ keyword: String, _ text: String) -> [UInt8] {
        var data = Array(keyword.utf8)
        data.append(0x00)                       // keyword null separator
        data += [0x00, 0x00]                     // compression flag, method
        data += [0x00, 0x00]                     // empty language tag, translated keyword
        data += Array(text.utf8)
        return chunk("iTXt", data)
    }

    /// One PNG chunk: length(4 BE) + type + data + CRC-32(4 BE over type+data).
    private func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
        let typeAndData = Array(type.utf8) + data
        return be(UInt32(data.count)) + typeAndData + be(crc32(typeAndData))
    }

    private func be(_ v: UInt32) -> [UInt8] {
        [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }

    /// CRC-32 (IEEE / reflected, polynomial 0xEDB88320) — matches Go's crc32.IEEE.
    private func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for b in bytes {
            crc ^= UInt32(b)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : (crc >> 1)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    /// Parse a REAL image-forge PNG (verifies the parser against the actual writer,
    /// not just constructed chunks). Skipped unless IMAGE_FORGE_GUI_TEST_PNG is set.
    func testReadsRealImageForgePNG() throws {
        guard let path = ProcessInfo.processInfo.environment["IMAGE_FORGE_GUI_TEST_PNG"] else {
            throw XCTSkip("set IMAGE_FORGE_GUI_TEST_PNG=<a real image-forge PNG>")
        }
        let meta = PngMetadata.read(contentsOf: URL(fileURLWithPath: path))
        XCTAssertNotNil(meta, "should parse a real image-forge PNG")
        XCTAssertNotNil(meta?.prompt, "should recover the prompt")
        XCTAssertNotNil(meta?.seed, "should recover the seed")
    }

    /// pixelSize reads the true dimensions from IHDR (independent of any text
    /// metadata) — this is what the gallery shows after hires / upscale.
    func testPixelSizeFromIHDR() {
        var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] // signature
        bytes += [0, 0, 0, 13]           // IHDR length
        bytes += Array("IHDR".utf8)      // chunk type
        bytes += [0, 0, 0x06, 0x00]      // width  = 1536
        bytes += [0, 0, 0x0C, 0x00]      // height = 3072
        let size = PngMetadata.pixelSize(Data(bytes))
        XCTAssertEqual(size?.width, 1536)
        XCTAssertEqual(size?.height, 3072)
    }

    func testPixelSizeRejectsNonPNG() {
        XCTAssertNil(PngMetadata.pixelSize(Data([0, 1, 2, 3])))
        XCTAssertNil(PngMetadata.pixelSize(Data()))
    }
}
