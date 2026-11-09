import XCTest
import Alamofire
@testable import ErghiSDK

final class InsightsContractTests: XCTestCase {
    typealias Stub = AuthContractTests.Stub

    func makeInsights(_ json: [String: Any] = [:], status: Int = 200, raw: Data? = nil) -> InsightsResource {
        Stub.seen = []
        Stub.rawBody = raw
        Stub.respond = { _ in (status, json) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        let config = ErghiConfig(apiURL: URL(string: "https://erghi.test")!)
        let session = Session(configuration: configuration)
        return InsightsResource(config: config, session: session, auth: AuthResource(config: config, session: session))
    }

    override func tearDown() {
        Stub.rawBody = nil
        super.tearDown()
    }

    private func query(_ index: Int = 0) throws -> [String: String] {
        let url = try XCTUnwrap(Stub.seen[index].request.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func testSummarySendsOnlySetFiltersAndMapsBody() async throws {
        let insights = makeInsights([
            "total": 4, "aiResolvedRate": 0.5,
            "outcomes": [["key": "ResolvedByAi", "count": 2]],
            "sentiments": [], "categories": [],
            "topics": [["key": "refund", "count": 3]],
            "languages": [["key": "ar", "count": 4]],
        ])
        let result = try await insights.summary(InsightFilter(
            from: Date(timeIntervalSince1970: 1_793_491_200), topic: "",
            outcome: "resolved_by_ai", minConfidence: 0.5))
        XCTAssertEqual(Stub.seen[0].request.httpMethod, "GET")
        XCTAssertEqual(Stub.seen[0].request.url?.path, "/api/v1/insights/summary")
        XCTAssertEqual(try query(), [
            "from": "2026-11-01T00:00:00.000Z", "outcome": "resolved_by_ai", "minConfidence": "0.5",
        ])
        XCTAssertEqual(result.total, 4)
        XCTAssertEqual(result.aiResolvedRate, 0.5)
        XCTAssertEqual(result.topics.first?.key, "refund")
    }

    func testListConversationsPagesAndParsesRows() async throws {
        let row: [String: Any] = [
            "conversationId": "7b1c0d2e-0000-4000-8000-000000000001", "topic": "refund",
            "category": "billing", "sentiment": "Negative", "sentimentEnd": "Neutral",
            "outcome": "ResolvedByAgent", "language": "ar-EG", "summary": "Asked for a refund.",
            "confidence": 0.9, "classifiedAt": "2026-11-09T10:14:03.1234567Z", "stale": false,
        ]
        let insights = makeInsights(["total": 1, "page": 2, "pageSize": 50, "items": [row]])
        let page = try await insights.listConversations(
            InsightFilter(channel: "widget", sentiment: "negative"), page: 2, pageSize: 50)
        XCTAssertEqual(Stub.seen[0].request.url?.path, "/api/v1/insights/conversations")
        XCTAssertEqual(try query(), [
            "channel": "widget", "sentiment": "negative", "page": "2", "pageSize": "50",
        ])
        XCTAssertEqual(page.pageSize, 50)
        XCTAssertEqual(page.items.first?.language, "ar-EG")
        XCTAssertEqual(page.items.first?.sentimentEnd, "Neutral")
        XCTAssertNotNil(page.items.first?.classifiedAt)
    }

    func testExportCSVReturnsRawBytes() async throws {
        let csv = Data([0xEF, 0xBB, 0xBF]) + Data("conversation_id,classified_at\r\n".utf8)
        let insights = makeInsights(raw: csv)
        let data = try await insights.exportCSV(InsightFilter(to: Date(timeIntervalSince1970: 1_796_083_200)))
        XCTAssertEqual(Stub.seen[0].request.url?.path, "/api/v1/insights/export.csv")
        XCTAssertEqual(data, csv)
    }

    func testInvalidFilterThrows() async throws {
        let insights = makeInsights(["error": "sentiment must be positive, neutral or negative.", "code": "invalid_filter"], status: 400)
        do {
            _ = try await insights.summary(InsightFilter(sentiment: "angry"))
            XCTFail("expected an error")
        } catch {
            XCTAssertNotNil(error)
        }
    }
}
