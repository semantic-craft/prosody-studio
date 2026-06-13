import XCTest
@testable import ResponsayCore

/// 232 — the streaming-insert chain's pure core: SSE line→event decoding (`SSELineParser`) and the
/// append-only accumulator (`StreamingInsertBuffer`). The live transport
/// `DirectStreamingTransformClient` delegates its decoding to `SSELineParser`, so these stand in
/// for it without a network/server. Real-Mac field insertion = HITL.
final class StreamingTextTransformTests: XCTestCase {

    // MARK: SSELineParser

    private let parser = SSELineParser()

    func testDeltaFrameDecodesToDeltaEvent() {
        XCTAssertEqual(parser.event(for: #"data: {"delta":"你好"}"#), .delta("你好"))
    }

    func testDoneObjectAndDoneSentinelBothTerminate() {
        XCTAssertEqual(parser.event(for: #"data: {"done":true}"#), .done)
        XCTAssertEqual(parser.event(for: "data: [DONE]"), .done)
    }

    func testErrorFrameDecodesToFailedEvent() {
        XCTAssertEqual(parser.event(for: #"data: {"error":"Upstream 401"}"#), .failed("Upstream 401"))
    }

    func testBlankCommentAndNonDataLinesAreIgnored() {
        XCTAssertNil(parser.event(for: ""))
        XCTAssertNil(parser.event(for: "   "))
        XCTAssertNil(parser.event(for: ": keep-alive"))
        XCTAssertNil(parser.event(for: "event: message"))
    }

    func testEmptyDeltaAndMalformedJSONAreIgnored() {
        XCTAssertNil(parser.event(for: #"data: {"delta":""}"#))
        XCTAssertNil(parser.event(for: "data: {not json"))
    }

    func testEventsForLinesStopsAtFirstTerminal() {
        let lines = [
            "",
            #"data: {"delta":"Hel"}"#,
            #"data: {"delta":"lo"}"#,
            "data: [DONE]",
            #"data: {"delta":"ignored after done"}"#,
        ]
        XCTAssertEqual(parser.events(for: lines), [.delta("Hel"), .delta("lo"), .done])
    }

    func testEventsForLinesSurfacesFailureAndStops() {
        let lines = [
            #"data: {"delta":"partial"}"#,
            #"data: {"error":"boom"}"#,
            #"data: {"delta":"after error"}"#,
        ]
        XCTAssertEqual(parser.events(for: lines), [.delta("partial"), .failed("boom")])
    }

    // MARK: StreamingInsertBuffer

    func testBufferReturnsEachDeltaAndAccumulatesFullText() {
        var buffer = StreamingInsertBuffer()
        XCTAssertEqual(buffer.append("Hel"), "Hel")
        XCTAssertEqual(buffer.append("lo "), "lo ")
        XCTAssertEqual(buffer.append("世界"), "世界")
        XCTAssertEqual(buffer.text, "Hello 世界")
    }

    func testBufferIgnoresEmptyDeltas() {
        var buffer = StreamingInsertBuffer()
        _ = buffer.append("a")
        XCTAssertEqual(buffer.append(""), "")
        XCTAssertEqual(buffer.text, "a")
    }

    func testBufferStartsEmpty() {
        XCTAssertEqual(StreamingInsertBuffer().text, "")
    }
}
