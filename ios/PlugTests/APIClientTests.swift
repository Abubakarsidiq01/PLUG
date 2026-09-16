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
                headerFields: ["Content-Type": "application/json", "X-Correlation-ID": "corr_fixture-123"]))
            return (response, fixture)
        }
        let result = try await client().health()
        XCTAssertEqual(result.response.status, "ok")
        XCTAssertEqual(result.correlationID, "corr_fixture-123")
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

    func testLocalEnvironmentUsesLoopbackIPv4() {
        XCTAssertEqual(AppEnvironment.local.baseURL?.absoluteString, "http://127.0.0.1:8080")
    }

    func testOfflineFailureIsReturnedToTheScreen() async throws {
        TestTransport.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await client().health()
            XCTFail("An offline request must not report a connection.")
        } catch { }
    }
}

private final class TestTransport: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
