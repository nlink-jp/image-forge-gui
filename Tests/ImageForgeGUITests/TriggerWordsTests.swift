import XCTest
@testable import ImageForgeGUI

/// A LoRA whose trigger words are absent from the prompt loads but does nothing.
/// The Composer detects that and offers to insert them; these back that logic.
final class TriggerWordsTests: XCTestCase {
    func testModelInfoDecodesTriggerWords() throws {
        let json = """
        [{"name":"mythic","arch":"sdxl","kind":"lora","path":"/m/x.safetensors",
          "trigger_words":["mythp0rt"]},
         {"name":"lcm","arch":"sdxl","kind":"lora","path":"/m/l.safetensors"}]
        """.data(using: .utf8)!
        let models = try ModelInfo.decodeInstalled(from: json)
        XCTAssertEqual(models[0].triggerWords, ["mythp0rt"])
        XCTAssertNil(models[1].triggerWords, "absent trigger_words decode to nil")
    }

    func testMissingTriggersIsCaseInsensitive() {
        XCTAssertEqual(AppModel.missingTriggers(in: "a MythP0rt knight", triggers: ["mythp0rt"]), [])
        XCTAssertEqual(AppModel.missingTriggers(in: "a knight", triggers: ["mythp0rt"]), ["mythp0rt"])
        XCTAssertEqual(
            AppModel.missingTriggers(in: "genba_neko here", triggers: ["genba_neko", "chibi"]),
            ["chibi"])
    }

    func testInsertPrependsMissingTriggers() {
        XCTAssertEqual(
            AppModel.prompt("a knight in a forest", insertingTriggers: ["mythp0rt"]),
            "mythp0rt, a knight in a forest")
    }

    func testInsertIntoEmptyPromptJustTriggers() {
        XCTAssertEqual(AppModel.prompt("", insertingTriggers: ["a", "b"]), "a, b")
        XCTAssertEqual(AppModel.prompt("   ", insertingTriggers: ["a"]), "a")
    }

    func testInsertIsIdempotentAndOnlyAddsMissing() {
        // Already present → unchanged.
        XCTAssertEqual(
            AppModel.prompt("mythp0rt, a knight", insertingTriggers: ["mythp0rt"]),
            "mythp0rt, a knight")
        // Only the missing one is added.
        XCTAssertEqual(
            AppModel.prompt("chibi cat", insertingTriggers: ["genba_neko", "chibi"]),
            "genba_neko, chibi cat")
    }

    func testInsertNoTriggersIsNoOp() {
        XCTAssertEqual(AppModel.prompt("a cat", insertingTriggers: []), "a cat")
    }

    private let loras: [ModelInfo] = [
        ModelInfo(name: "mythic", arch: "sdxl", kind: "lora", triggerWords: ["mythp0rt"]),
        ModelInfo(name: "neko", arch: "sdxl", kind: "lora", triggerWords: ["genba_neko", "chibi"]),
        ModelInfo(name: "lcm", arch: "sdxl", kind: "lora"),                 // no triggers
        ModelInfo(name: "dupe", arch: "sdxl", kind: "lora", triggerWords: ["Chibi", "extra"]),
    ]

    /// Stacked LoRAs combine their triggers, de-duplicated (case-insensitive),
    /// preserving order — the list shown and merged at generation. Triggers stay
    /// OUT of the prompt so switching a LoRA can't pile up stale tokens.
    func testCombinedTriggerWordsDedupsAndKeepsOrder() {
        XCTAssertEqual(
            AppModel.combinedTriggerWords(forLoRAs: ["mythic", "neko"], models: loras),
            ["mythp0rt", "genba_neko", "chibi"])
        // "Chibi" from dupe is dropped (already have "chibi"); the new one is kept.
        XCTAssertEqual(
            AppModel.combinedTriggerWords(forLoRAs: ["neko", "dupe"], models: loras),
            ["genba_neko", "chibi", "extra"])
        // No-trigger LoRAs contribute nothing; unknown names are ignored.
        XCTAssertEqual(
            AppModel.combinedTriggerWords(forLoRAs: ["lcm", "ghost", "mythic"], models: loras),
            ["mythp0rt"])
        XCTAssertEqual(AppModel.combinedTriggerWords(forLoRAs: [], models: loras), [])
    }
}
