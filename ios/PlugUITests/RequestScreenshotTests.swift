import XCTest

/// Synthetic fixture-server screenshots exercise real SwiftUI and HTTP decoding. They
/// are explicitly separate from the connected backend and physical-device G2 evidence.
/// The walk follows manual v4 Figures A1 to A3: ask, working, offers, unknown, the web
/// answer, and offering a service from the same account.
final class RequestScreenshotTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }

    func testRequestStatesDefaultText() throws { try walk(largest: false) }
    func testRequestStatesLargestText() throws { try walk(largest: true) }

    private func walk(largest: Bool) throws {
        let suffix = largest ? "largest" : "default"
        let app = launch(largest: largest)
        enterGuest(app)
        capture("ask-\(suffix)")

        // Figure A2: offer a service on this same account; the Inbox tab appears after.
        let offer = app.buttons["offer-service"]
        reveal(offer, in: app)
        offer.tap()
        let describe = app.descendants(matching: .any).matching(identifier: "provider-description").firstMatch
        XCTAssertTrue(describe.waitForExistence(timeout: 5))
        describe.tap()
        describe.typeText("I do knotless braids, wig installs and crochet locs")
        dismissKeyboard(app)
        let find = app.buttons["Find my skills"]
        reveal(find, in: app)
        find.tap()
        XCTAssertTrue(app.buttons["Braids"].waitForExistence(timeout: 10))
        capture("provider-skills-\(suffix)")
        let base = app.buttons["Use my approximate location"]
        reveal(base, in: app)
        base.tap()
        allowLocation()
        let located = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Current approximate location'")).firstMatch
        // The simulator's one-shot location occasionally answers "unknown"; ask again before failing.
        for _ in 0..<2 where !located.waitForExistence(timeout: 10) {
            reveal(base, in: app)
            base.tap()
        }
        XCTAssertTrue(located.waitForExistence(timeout: 10))
        let save = app.buttons["provider-save"]
        reveal(save, in: app)
        capture("provider-setup-\(suffix)")
        save.tap()
        let inbox = app.tabBars.buttons["Inbox"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 10))
        inbox.tap()
        XCTAssertTrue(app.descendants(matching: .any)["inbox-empty"].waitForExistence(timeout: 5))
        capture("inbox-\(suffix)")
        app.tabBars.buttons["Ask"].tap()

        // One clarifying question, then offers with their evidence.
        try submit(app, text: "clarify this for me")
        let barber = app.buttons["Barber"]
        XCTAssertTrue(barber.waitForExistence(timeout: 12))
        reveal(barber, in: app)
        capture("clarification-\(suffix)")
        barber.tap()
        let details = app.buttons["View details"].firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 20))
        // Counts tick to the server's numbers; capture once they have settled.
        let settled = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Providers notified' AND NOT (label ENDSWITH ' 0')")).firstMatch
        _ = settled.waitForExistence(timeout: 5)
        capture("results-\(suffix)")
        reveal(details, in: app)
        details.tap()
        XCTAssertTrue(app.navigationBars["Offer"].waitForExistence(timeout: 5))
        capture("offer-detail-\(suffix)")
        swipeBack(app)
        XCTAssertTrue(app.buttons["View details"].firstMatch.waitForExistence(timeout: 5))
        stopAndRestart(app, suffix: suffix)

        try submit(app, text: "progress barber")
        let progress = app.descendants(matching: .any)["request-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        app.swipeDown()
        capture("progress-\(suffix)")
        // Swiping back from a request that is still asking keeps it running and reachable.
        swipeBack(app)
        let resume = app.buttons["ask-resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        capture("resume-\(suffix)")
        reveal(resume, in: app, upward: false)
        resume.tap()
        XCTAssertTrue(app.descendants(matching: .any)["request-progress"].waitForExistence(timeout: 10))
        stopAndRestart(app, suffix: suffix)

        try submit(app, text: "empty barber")
        XCTAssertTrue(app.staticTexts["No offers"].waitForExistence(timeout: 20))
        capture("empty-\(suffix)")
        askAgain(app)

        try submit(app, text: "restricted request")
        let error = app.staticTexts["PLUG cannot help with this request. No suppliers were contacted."]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        reveal(error, in: app)
        capture("restricted-\(suffix)")

        // Figure A1 screens 2 and 4 for a place question: real counts, then Unknown and the dashed web answer.
        try submit(app, text: "How long is the line at Walmart right now?")
        XCTAssertTrue(app.descendants(matching: .any)["place-progress"].waitForExistence(timeout: 10))
        capture("place-asking-\(suffix)")
        XCTAssertTrue(app.staticTexts["No answers"].waitForExistence(timeout: 20))
        capture("place-unknown-\(suffix)")
        let web = app.staticTexts["Usually busy at this hour"]
        reveal(web, in: app)
        capture("place-web-\(suffix)")
        askAgain(app)

        try submit(app, text: "cached barber")
        XCTAssertTrue(app.buttons["View details"].firstMatch.waitForExistence(timeout: 20))
        app.buttons["Refresh"].tap()
        let cached = app.staticTexts["Saved result. Refresh to check it is still current."]
        XCTAssertTrue(cached.waitForExistence(timeout: 10))
        reveal(cached, in: app, upward: false)
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
        XCTAssertTrue(app.staticTexts["What do you need to know?"].waitForExistence(timeout: 15))
    }
    private func submit(_ app: XCUIApplication, text: String) throws {
        let field = app.descendants(matching: .any).matching(identifier: "request-text").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        reveal(field, in: app, upward: false)
        // "Ask something else" keeps the previous words. A plain tap can leave the cursor at
        // the start, where deletes remove nothing, so tap the end.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.9)).tap()
        if let value = field.value as? String, !value.isEmpty, value != "Type anything, or tap an example" {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        field.typeText(text)
        dismissKeyboard(app)
        let ask = app.buttons["ask-submit"]
        reveal(ask, in: app, upward: false)
        ask.tap()
        allowLocation()
        // The simulator's location service occasionally answers a one-shot request with
        // "unknown"; the app then offers the address path. Ask again before failing.
        let address = app.descendants(matching: .any).matching(identifier: "request-address").firstMatch
        if address.waitForExistence(timeout: 3) {
            reveal(ask, in: app, upward: false)
            ask.tap()
        }
    }
    /// The system back gesture: a drag from the left edge of the screen.
    private func swipeBack(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
    }
    private func allowLocation() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Allow While Using App"].waitForExistence(timeout: 2) {
            springboard.buttons["Allow While Using App"].tap()
        }
    }
    private func dismissKeyboard(_ app: XCUIApplication) {
        let done = app.toolbars.buttons["Done"]
        if done.waitForExistence(timeout: 2) { done.tap() }
    }
    private func stopAndRestart(_ app: XCUIApplication, suffix: String) {
        let stop = app.buttons["request-cancel"]
        reveal(stop, in: app)
        stop.tap()
        let stopped = app.staticTexts["You stopped asking"]
        XCTAssertTrue(stopped.waitForExistence(timeout: 10))
        reveal(stopped, in: app, upward: false)
        capture("stopped-\(suffix)")
        askAgain(app)
    }
    private func askAgain(_ app: XCUIApplication) {
        let again = app.buttons["Ask something else"]
        reveal(again, in: app)
        again.tap()
        XCTAssertTrue(app.staticTexts["What do you need to know?"].waitForExistence(timeout: 5))
    }
    /// Scrolls in the preferred direction first, then the other: at the largest text size a
    /// control that is normally on screen can sit on either side of the viewport.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        // Polling re-renders the answer screen; asking for hittability while a control has
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
