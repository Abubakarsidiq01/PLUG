import XCTest
@testable import Plug

final class HealthResponseTests: XCTestCase {
    func testDecodesSharedFixtureShape() throws {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "health-response", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let response = try JSONDecoder().decode(HealthResponse.self, from: data)
        XCTAssertEqual(response, HealthResponse(status: "UP", version: "0.1.0", commit: "a91f3c2"))
    }
}
