import XCTest
@testable import Plug

final class HealthResponseTests: XCTestCase {
    func testDecodesSharedFixtureShape() throws {
        let data = Data(#"{"status":"ok","service":"plug-api","environment":"local"}"#.utf8)
        let response = try JSONDecoder().decode(HealthResponse.self, from: data)
        XCTAssertEqual(response, HealthResponse(status: "ok", service: "plug-api", environment: "local"))
    }
}
