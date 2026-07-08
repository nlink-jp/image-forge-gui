import XCTest
@testable import ImageForgeGUI

final class GenerationRequestTests: XCTestCase {
    /// Encoding a request must include set fields, use the serve JSON key names,
    /// and omit every nil field (so the engine falls back to profile defaults).
    func testEncodesOnlySetFieldsWithSnakeCaseKeys() throws {
        let req = GenerationRequest(
            prompt: "a cat",
            model: "realvisxl-v5",
            seed: 42,
            steps: 30,
            hires: "auto",
            output: "/tmp/x.png"
        )
        let obj = try object(req)

        XCTAssertEqual(obj["prompt"] as? String, "a cat")
        XCTAssertEqual(obj["model"] as? String, "realvisxl-v5")
        XCTAssertEqual(obj["seed"] as? Int, 42)
        XCTAssertEqual(obj["steps"] as? Int, 30)
        XCTAssertEqual(obj["hires"] as? String, "auto")
        XCTAssertEqual(obj["output"] as? String, "/tmp/x.png")

        // Unset optionals must be absent entirely.
        for key in ["negative", "cfg", "width", "height", "sampler", "scheduler",
                    "clip_skip", "batch", "init", "strength"] {
            XCTAssertNil(obj[key], "expected \(key) to be omitted")
        }
    }

    /// clip_skip / init are custom coding keys; verify they map correctly and the
    /// Swift property names never leak onto the wire.
    func testCustomCodingKeys() throws {
        let req = GenerationRequest(
            prompt: "x",
            clipSkip: 2,
            initPath: "/tmp/in.png",
            strength: 0.6,
            output: "/tmp/o.png"
        )
        let obj = try object(req)
        XCTAssertEqual(obj["clip_skip"] as? Int, 2)
        XCTAssertEqual(obj["init"] as? String, "/tmp/in.png")
        XCTAssertEqual(obj["strength"] as? Double, 0.6)
        XCTAssertNil(obj["clipSkip"])
        XCTAssertNil(obj["initPath"])
    }

    /// A random-seed request carries seed -1 (the engine's "pick a seed" value).
    func testRandomSeedSentinel() throws {
        let req = GenerationRequest(prompt: "x", seed: -1, output: "/tmp/o.png")
        let obj = try object(req)
        XCTAssertEqual(obj["seed"] as? Int, -1)
    }

    private func object(_ req: GenerationRequest) throws -> [String: Any] {
        let data = try JSONEncoder().encode(req)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
