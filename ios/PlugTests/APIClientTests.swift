import XCTest
@testable import Plug

final class APIClientTests: XCTestCase {
    override func tearDown() {
        TestTransport.handler = nil
        super.tearDown()
    }

    private func client() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestTransport.self]
        return APIClient(environment: .local, session: URLSession(configuration: configuration))
    }

    func testHealthUsesTheSharedFixtureAndPreservesCorrelationID() async throws {
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "health-response", withExtension: "json"))
        let fixture = try Data(contentsOf: fixtureURL)
        TestTransport.handler = { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.path, "/health")
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json", "X-Request-Id": "req_fixture-123"]))
            return (response, fixture)
        }
        let result = try await client().health()
        XCTAssertEqual(result.response.status, "UP")
        XCTAssertEqual(result.correlationID, "req_fixture-123")
    }

    func testMalformedResponseDoesNotCountAsConnected() async throws {
        TestTransport.handler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            return (response, Data("{bad".utf8))
        }
        do {
            _ = try await client().health()
            XCTFail("Malformed JSON must not be accepted as a health response.")
        } catch { }
    }

    func testPhoneDevelopmentAddressOverridesStaleSchemeAndEmptySettingsFallThrough() {
        XCTAssertEqual(AppEnvironment.preferredAPISetting(development: "https://current.example",
                       runtime: "https://expired.example", bundled: nil), "https://current.example")
        XCTAssertEqual(AppEnvironment.preferredAPISetting(development: "", runtime: "http://127.0.0.1:8081",
                       bundled: nil), "http://127.0.0.1:8081")
        XCTAssertNil(AppEnvironment.preferredAPISetting(development: "$(UNSET)", runtime: "", bundled: nil))
    }

    func testLocalEnvironmentUsesLoopbackIPv4() {
        XCTAssertEqual(AppEnvironment.local.baseURL?.absoluteString, "http://127.0.0.1:8080")
    }

    func testOfflineFailureIsReturnedToTheScreen() async throws {
        TestTransport.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await client().health()
            XCTFail("An offline request must not report a connection.")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        }
    }

    func testOversizedResponseWithoutContentLengthIsRejected() async throws {
        TestTransport.handler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            return (response, Data(String(repeating: " ", count: 16_385).utf8))
        }
        do {
            _ = try await client().health()
            XCTFail("Oversized responses must be stopped before decoding.")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .dataLengthExceedsMaximum)
        }
    }

    func testInvalidHealthResponsesDoNotCountAsConnected() async throws {
        let cases: [(Int, String, String)] = [
            (503, "application/json", "{\"status\":\"UP\",\"version\":\"0.1.0\"}"),
            (200, "text/html", "{\"status\":\"UP\",\"version\":\"0.1.0\"}"),
            (200, "application/json", "{\"status\":\"DOWN\",\"version\":\"0.1.0\"}"),
            (200, "application/json", "{\"status\":\"UP\",\"version\":\"   \"}")
        ]
        for (status, contentType, body) in cases {
            TestTransport.handler = { request in
                let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: status,
                    httpVersion: nil, headerFields: ["Content-Type": contentType]))
                return (response, Data(body.utf8))
            }
            do {
                _ = try await client().health()
                XCTFail("An invalid health response must not report Connected.")
            } catch { }
        }
    }

    func testFailureMessagesDoNotExposeUnderlyingDiagnostics() {
        let error = NSError(domain: NSURLErrorDomain, code: URLError.cannotConnectToHost.rawValue,
                            userInfo: [NSLocalizedDescriptionKey: "sensitive internal URL and token"])
        XCTAssertEqual(HealthFailure.message(for: error), "The server could not be reached. Please try again.")
    }
}
