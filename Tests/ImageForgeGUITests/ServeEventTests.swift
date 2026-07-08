import XCTest
@testable import ImageForgeGUI

final class ServeEventTests: XCTestCase {
    private func decode(_ json: String) throws -> ServeEvent {
        try JSONDecoder().decode(ServeEvent.self, from: Data(json.utf8))
    }

    func testReady() throws {
        let ev = try decode(#"{"kind":"ready","message":"send one JSON request per line"}"#)
        XCTAssertEqual(ev.kind, .ready)
        XCTAssertEqual(ev.message, "send one JSON request per line")
        XCTAssertNil(ev.progress)
        XCTAssertNil(ev.output)
    }

    func testLoad() throws {
        let ev = try decode(#"{"kind":"load","message":"loading realvisxl-v5"}"#)
        XCTAssertEqual(ev.kind, .load)
        XCTAssertEqual(ev.message, "loading realvisxl-v5")
    }

    func testProgress() throws {
        let ev = try decode(#"{"kind":"progress","progress":0.5,"message":"step 15/30"}"#)
        XCTAssertEqual(ev.kind, .progress)
        XCTAssertEqual(ev.progress ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(ev.message, "step 15/30")
    }

    func testDone() throws {
        let ev = try decode(#"{"kind":"done","progress":1,"output":"/lib/abc.png","seed":123456}"#)
        XCTAssertEqual(ev.kind, .done)
        XCTAssertEqual(ev.output, "/lib/abc.png")
        XCTAssertEqual(ev.seed, 123456)
        XCTAssertEqual(ev.progress ?? 0, 1, accuracy: 0.0001)
    }

    func testError() throws {
        let ev = try decode(#"{"kind":"error","message":"prompt is required"}"#)
        XCTAssertEqual(ev.kind, .error)
        XCTAssertEqual(ev.message, "prompt is required")
    }

    /// An unrecognized kind decodes to `.unknown` rather than throwing.
    func testUnknownKind() throws {
        let ev = try decode(#"{"kind":"future_event","message":"?"}"#)
        XCTAssertEqual(ev.kind, .unknown)
    }
}

final class LineBufferTests: XCTestCase {
    /// A line split across two reads is buffered until its newline arrives.
    func testBuffersPartialLineAcrossReads() {
        var lb = LineBuffer()
        XCTAssertTrue(lb.append(Data(#"{"kind":"rea"#.utf8)).isEmpty)
        let lines = lb.append(Data("dy\"}\n{\"kind\":\"done\"}\n".utf8))
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(String(data: lines[0], encoding: .utf8), #"{"kind":"ready"}"#)
        XCTAssertEqual(String(data: lines[1], encoding: .utf8), #"{"kind":"done"}"#)
    }

    /// Blank lines are dropped; a trailing partial line is retained for later.
    func testDropsBlankLinesAndRetainsRemainder() {
        var lb = LineBuffer()
        let lines = lb.append(Data("\n{\"kind\":\"progress\"}\npartial".utf8))
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(String(data: lines[0], encoding: .utf8), #"{"kind":"progress"}"#)
        // The partial tail comes out once completed.
        let more = lb.append(Data("-tail\n".utf8))
        XCTAssertEqual(more.count, 1)
        XCTAssertEqual(String(data: more[0], encoding: .utf8), "partial-tail")
    }

    /// The buffered lines decode as real ServeEvents (end-to-end).
    func testBufferedLinesDecodeAsEvents() throws {
        var lb = LineBuffer()
        let lines = lb.append(Data(
            "{\"kind\":\"ready\"}\n{\"kind\":\"done\",\"output\":\"/o.png\",\"seed\":7}\n".utf8))
        let events = try lines.map { try JSONDecoder().decode(ServeEvent.self, from: $0) }
        XCTAssertEqual(events.map(\.kind), [.ready, .done])
        XCTAssertEqual(events[1].output, "/o.png")
        XCTAssertEqual(events[1].seed, 7)
    }
}
