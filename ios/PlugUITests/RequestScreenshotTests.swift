import XCTest

/// Synthetic fixture-server screenshots exercise real SwiftUI and HTTP decoding. They
/// are explicitly separate from the connected backend and physical-device G2 evidence.
final class RequestScreenshotTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }

    func testRequestStatesDefaultText() throws { try walk(largest: false) }
    func testRequestStatesLargestText() throws { try walk(largest: true) }

    private func walk(largest: Bool) throws {
        let suffix = largest ? "largest" : "default"
        let app = launch(largest: largest)
        enterGuest(app)
        capture("ask-\(suffix)")
        try submit(app, text: "clarify barber", suffix: suffix)
        let barber = app.buttons["Barber"]
        XCTAssertTrue(barber.waitForExistence(timeout: 12))
        reveal(barber, in: app)
        capture("clarification-\(suffix)")
        barber.tap()
        XCTAssertTrue(app.staticTexts["Your options"].waitForExistence(timeout: 20))
        reveal(app.staticTexts["Your options"], in: app)
        capture("results-\(suffix)")
        let details = app.staticTexts["View details"].firstMatch
        reveal(details, in: app)
        details.tap()
        XCTAssertTrue(app.navigationBars["Offer details"].waitForExistence(timeout: 5))
        capture("offer-detail-\(suffix)")
        app.navigationBars.buttons.firstMatch.tap()
        cancelAndRestart(app, suffix: suffix)

        try submit(app, text: "progress barber", suffix: suffix)
        XCTAssertTrue(app.staticTexts["Checking participating suppliers"].waitForExistence(timeout: 10))
        reveal(app.staticTexts["Checking participating suppliers"], in: app)
        capture("progress-\(suffix)")
        cancelAndRestart(app, suffix: suffix)

        try submit(app, text: "empty barber", suffix: suffix)
        XCTAssertTrue(app.staticTexts["No matches this time"].waitForExistence(timeout: 20))
        reveal(app.staticTexts["No matches this time"], in: app)
        capture("empty-\(suffix)")
        let restart = app.buttons["Start a new request"]
        reveal(restart, in: app); restart.tap()

        try submit(app, text: "unsupported service", suffix: suffix)
        let error = app.staticTexts["PLUG currently supports barber and beauty requests. Nothing was created."]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        reveal(error, in: app)
        capture("parser-error-\(suffix)")

        try submit(app, text: "cached barber", suffix: suffix)
        XCTAssertTrue(app.staticTexts["Your options"].waitForExistence(timeout: 20))
        app.buttons["Refresh"].tap()
        let cached = app.staticTexts["Cached result — refresh to check availability"]
        XCTAssertTrue(cached.waitForExistence(timeout: 10))
        reveal(cached, in: app)
        capture("cached-error-\(suffix)")
    }

    private func launch(largest: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-plug-ui-test-reset"]
        if largest { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment["PLUG_API_URL"] = "http://127.0.0.1:18084"
        app.launchEnvironment["PLUG_REQUESTS_V2_ENABLED"] = "YES"
        app.launch()
        return app
    }
    private func enterGuest(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 10))
        let guest = app.buttons["Continue as guest"]
        reveal(guest, in: app)
        guest.tap()
        XCTAssertTrue(app.navigationBars["Ask PLUG"].waitForExistence(timeout: 15))
    }
    private func submit(_ app: XCUIApplication, text: String, suffix: String) throws {
        let field = app.descendants(matching: .any).matching(identifier: "request-text").firstMatch
        reveal(field, in: app, upward: false)
        XCTAssertTrue(field.exists)
        // The app keeps the previous request's words after "Start a new request". A plain tap
        // can leave the cursor at the start, where deletes remove nothing, so tap the end.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.9)).tap()
        if let value = field.value as? String, !value.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        field.typeText(text)
        app.swipeUp()
        let location = app.buttons["Use my approximate location"]
        reveal(location, in: app)
        location.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Allow While Using App"].waitForExistence(timeout: 2) {
            springboard.buttons["Allow While Using App"].tap()
        }
        // The simulator's location service occasionally answers a one-shot request with
        // "unknown"; the app then correctly offers the address path. Ask again before failing.
        let current = app.staticTexts["Current approximate location"]
        for _ in 0..<2 where !current.waitForExistence(timeout: 10) {
            reveal(location, in: app)
            location.tap()
        }
        XCTAssertTrue(current.waitForExistence(timeout: 10))
        let submit = app.buttons["Find options"]
        reveal(submit, in: app)
        submit.tap()
    }
    private func cancelAndRestart(_ app: XCUIApplication, suffix: String) {
        let cancel = app.buttons["request-cancel"]
        reveal(cancel, in: app)
        cancel.tap()
        XCTAssertTrue(app.staticTexts["Request canceled"].waitForExistence(timeout: 10))
        reveal(app.staticTexts["Request canceled"], in: app)
        capture("canceled-\(suffix)")
        let restart = app.buttons["Start a new request"]
        reveal(restart, in: app); restart.tap()
    }
    /// Scrolls in the preferred direction first, then the other: at the largest text size a
    /// control that is normally on screen can sit on either side of the viewport.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        // Polling re-renders the progress screen; asking for hittability while a control has
        // no frame yet fails outright instead of returning false.
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate { candidate, _ in
                guard let candidate = candidate as? XCUIElement, candidate.exists else { return false }
                return !candidate.frame.isEmpty
            }, object: element)
        _ = XCTWaiter().wait(for: [settled], timeout: 5)
        for direction in [upward, !upward] {
            for _ in 0..<10 where !element.isHittable { direction ? app.swipeUp() : app.swipeDown() }
            if element.isHittable { return }
        }
        XCTAssertTrue(element.isHittable, "Expected control to remain reachable when scrolling")
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "synthetic-p2-\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
