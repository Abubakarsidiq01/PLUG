import XCTest

/// Synthetic fixture-server screenshots exercise real SwiftUI and HTTP decoding. They
/// are explicitly separate from the connected backend and physical-device G2 evidence.
/// The walk follows manual v4 Figures A1 to A3: ask, working, offers, unknown, the web
/// answer, and offering a service from the same account.
final class RequestScreenshotTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }

    func testRequestStatesDefaultText() throws { try walk(largest: false) }
    func testRequestStatesLargestText() throws { try walk(largest: true) }

    func testVisualAskHome() throws {
        for largest in [false, true] {
            let suffix = largest ? "largest" : "default"
            let app = launch(largest: largest)
            enterGuest(app)
            capture("visual-home-\(suffix)")
            let example = app.buttons["ask-example-barber"]
            reveal(example, in: app)
            if largest { app.swipeUp() }
            capture("visual-examples-\(suffix)", onlyIfChanged: true)
            example.tap()
            let field = app.textFields["request-text"]
            XCTAssertEqual(field.value as? String, "Someone to do knotless braids, $120 max")
            XCTAssertFalse(app.navigationBars["Your ask"].exists)
            dismissKeyboard(app)
            let place = app.buttons["ask-example-place"]
            reveal(place, in: app)
            place.tap()
            XCTAssertEqual(field.value as? String, "How long is the line at Walmart right now?")
        }
    }

    func testDirectSkillEntryWithoutSuggestions() throws {
        for largest in [false, true] {
            let app = launch(largest: largest)
            enterGuest(app)
            let offer = app.buttons["offer-service"]
            reveal(offer, in: app)
            offer.tap()
            let field = app.descendants(matching: .any).matching(identifier: "provider-description").firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 20))
            field.tap()
            field.typeText("Wig install")
            dismissKeyboard(app)
            if largest {
                let find = app.buttons["Find my skills"]
                reveal(find, in: app)
                find.tap()
                XCTAssertTrue(app.staticTexts["Suggestions are unavailable. You can still add each skill directly above."].waitForExistence(timeout: 20))
            }
            let add = app.buttons["provider-add-skill"]
            reveal(add, in: app, upward: false)
            add.tap()
            let skill = app.buttons["Wig install"]
            XCTAssertTrue(skill.waitForExistence(timeout: 20))
            XCTAssertTrue(skill.isSelected)
            capture("direct-skill-\(largest ? "largest" : "default")")
            let base = app.buttons["Use my approximate location"]
            reveal(base, in: app)
            base.tap()
            let located = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS 'Current approximate location'")).firstMatch
            allowLocation(unless: { located.exists })
            for _ in 0..<2 where !located.waitForExistence(timeout: 20) {
                reveal(base, in: app)
                base.tap()
            }
            XCTAssertTrue(located.waitForExistence(timeout: 20))
            let save = app.buttons["provider-save"]
            reveal(save, in: app)
            XCTAssertTrue(save.isEnabled)
            save.tap()
            XCTAssertTrue(app.buttons["Inbox"].waitForExistence(timeout: 20))
        }
    }

    /// Apple's accessibility audit (contrast, element detection, hit regions, clipped and
    /// non-scaling text, traits) on every main screen. Issues are recorded as attachments.
    func testAccessibilityAudit() throws {
        let app = launch(largest: false)
        enterGuest(app)
        func audit(_ screen: String) throws {
            var issues: [String] = []
            try app.performAccessibilityAudit(for: .all) { issue in
                let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' \($0.identifier)" } ?? "-"
                let bar = app.buttons["navigation-ask"]
                // The bar's background starts above its buttons; text under it is not visible.
                let barTop = bar.exists && !bar.frame.isEmpty ? bar.frame.minY - 16 : .greatestFiniteMagnitude
                let accepted = Self.acceptedAuditFinding(issue, barTop: barTop)
                issues.append("\(accepted ? "accepted" : "FAIL") | \(screen) | \(issue.compactDescription) | \(element)")
                return true
            }
            let report = XCTAttachment(string: issues.isEmpty ? "\(screen) | no issues" : issues.joined(separator: "\n"))
            report.name = "accessibility-audit-\(screen).txt"
            report.lifetime = .keepAlways
            add(report)
            let failures = issues.filter { $0.hasPrefix("FAIL") }
            XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
        }
        try audit("ask-home")
        // The place tile sits under the bottom bar at first; audit it again once it is in view.
        let placeTile = app.buttons["ask-example-place"]
        reveal(placeTile, in: app)
        try audit("ask-home-scrolled")
        try submit(app, text: "business sorting barber under $35")
        XCTAssertTrue(app.buttons["View details"].firstMatch.waitForExistence(timeout: 20))
        try audit("results")
        let details = app.buttons["View details"].firstMatch
        reveal(details, in: app)
        details.tap()
        XCTAssertTrue(app.navigationBars["Offer"].waitForExistence(timeout: 20))
        try audit("offer-detail")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["navigation-activity"].tap()
        try audit("activity")
        app.buttons["navigation-profile"].tap()
        try audit("profile")
        app.buttons["navigation-ask"].tap()
        swipeBack(app)
        let offer = app.buttons["offer-service"]
        XCTAssertTrue(offer.waitForExistence(timeout: 20))
        reveal(offer, in: app)
        offer.tap()
        XCTAssertTrue(app.descendants(matching: .any)["provider-description"].waitForExistence(timeout: 20))
        try audit("provider-setup")
    }

    /// Documented exceptions; everything else fails the audit. Manual v4 §11.6 caps the bottom
    /// navigation labels at xxxLarge with the large-content viewer, the wordmark is a fixed logo (the P mark plus "LUG"),
    /// disabled controls are exempt from contrast (WCAG 1.4.3), system controls are Apple's, and a
    /// partial Dynamic Type or text finding without an element (off-screen) is not actionable. The
    /// Ask field's own line is short, but its whole 70 pt box focuses it on a tap. PLUG's type scale
    /// grows through @ScaledMetric rather than system text styles, which the audit reports as
    /// "partially unsupported"; the largest-size device screenshots show it scaling. Text that
    /// does not scale at all still fails, except the wordmark. Contrast is measured from the
    /// pixels on screen, so text scrolled beneath the opaque bottom bar is measured against the
    /// bar; that text is audited again once scrolled into view (ask-home-scrolled).
    static func acceptedAuditFinding(_ issue: XCUIAccessibilityAuditIssue, barTop: CGFloat) -> Bool {
        guard let element = issue.element else { return true }
        let navigation = ["Ask", "Inbox", "Activity", "Profile"].contains(element.label)
        switch issue.auditType {
        case .dynamicType:
            return issue.compactDescription.contains("partially") || navigation
                || ["PLUG", "LUG"].contains(element.label) || element.label == "Cancel"
        case .contrast:
            return !element.isEnabled || element.frame.maxY > barTop
        case .hitRegion:
            return element.identifier == "request-text"
        default:
            return false
        }
    }

    func testAnsweredPlaceEvidence() throws {
        for largest in [false, true] {
            let suffix = largest ? "largest" : "default"
            let app = launch(largest: largest)
            enterGuest(app)
            try submit(app, text: "How busy is the demo place? answered place")
            XCTAssertTrue(app.staticTexts["12–15 min"].waitForExistence(timeout: 20))
            capture("place-answered-\(suffix)")
            let sources = app.staticTexts["Who answered"]
            reveal(sources, in: app)
            XCTAssertTrue(app.staticTexts["Who answered"].exists)
            capture("place-sources-\(suffix)", onlyIfChanged: true)
        }
    }

    func testBusinessProfilesAndHomeCancellation() throws {
        for largest in [false, true] {
            let suffix = largest ? "largest" : "default"
            let app = launch(largest: largest)
            enterGuest(app)
            try submit(app, text: "business sorting barber under $35")
            let details = app.buttons["View details"].firstMatch
            XCTAssertTrue(details.waitForExistence(timeout: 20))
            let priceSort = app.buttons["Lowest price"]
            reveal(priceSort, in: app, upward: false)
            priceSort.tap()
            XCTAssertTrue(priceSort.isSelected)
            XCTAssertLessThan(app.staticTexts["Studio B · Test profile"].frame.minY,
                              app.staticTexts["Sharp Cuts Studio"].frame.minY)
            let forYou = app.buttons["For you"]
            reveal(forYou, in: app, upward: false)
            forYou.tap()
            XCTAssertTrue(forYou.isSelected)
            XCTAssertLessThan(app.staticTexts["Sharp Cuts Studio"].frame.minY,
                              app.staticTexts["Studio B · Test profile"].frame.minY)
            let closest = app.buttons["Closest"]
            reveal(closest, in: app, upward: false)
            closest.tap()
            XCTAssertTrue(closest.isSelected)
            XCTAssertLessThan(app.staticTexts["Studio B · Test profile"].frame.minY,
                              app.staticTexts["Sharp Cuts Studio"].frame.minY)
            capture("business-results-\(suffix)")
            reveal(details, in: app)
            details.tap()
            XCTAssertTrue(app.staticTexts["Studio B · Test profile"].waitForExistence(timeout: 20))
            let links = app.staticTexts["See their work"]
            reveal(links, in: app)
            XCTAssertTrue(links.exists)
            capture("business-detail-\(suffix)")
            swipeBack(app)
            swipeBack(app)
            app.buttons["navigation-profile"].tap()
            XCTAssertTrue(app.staticTexts["Your corner of PLUG"].waitForExistence(timeout: 20))
            capture("marketplace-profile-\(suffix)")
            app.buttons["navigation-activity"].tap()
            XCTAssertTrue(app.staticTexts["Your asks, in one place"].waitForExistence(timeout: 20))
            capture("activity-\(suffix)")
            app.buttons["Go to Ask"].tap()
            let stop = app.buttons["ask-stop"]
            XCTAssertTrue(stop.waitForExistence(timeout: 20))
            reveal(stop, in: app)
            capture("business-home-active-\(suffix)")
            stop.tap()
            XCTAssertTrue(app.staticTexts["Ask stopped"].waitForExistence(timeout: 20))
            XCTAssertFalse(app.buttons["ask-stop"].exists)
            capture("business-home-stopped-\(suffix)")
            app.buttons["navigation-profile"].tap()
            let upgrade = app.buttons["Create account or sign in"]
            reveal(upgrade, in: app)
            upgrade.tap()
            XCTAssertTrue(app.buttons["I have an account"].waitForExistence(timeout: 20))
            enterGuest(app)
            // Signing in resets the app to Ask once the session loads; open Profile after that.
            let profileTitle = app.staticTexts["Your corner of PLUG"]
            for _ in 0..<3 where !profileTitle.waitForExistence(timeout: 3) { app.buttons["navigation-profile"].tap() }
            XCTAssertTrue(profileTitle.exists)
            let signOut = app.buttons["Sign out"]
            reveal(signOut, in: app)
            signOut.tap()
            XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 20))
        }
    }

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
        XCTAssertTrue(describe.waitForExistence(timeout: 20))
        describe.tap()
        describe.typeText("I do knotless braids, wig installs and crochet locs")
        dismissKeyboard(app)
        let find = app.buttons["Find my skills"]
        reveal(find, in: app)
        find.tap()
        XCTAssertTrue(app.buttons["Braids"].waitForExistence(timeout: 20))
        capture("provider-skills-\(suffix)")
        // A word PLUG does not list becomes the provider's own skill on a tap (ADR-011).
        let own = app.buttons["chimney sweeping"]
        reveal(own, in: app)
        own.tap()
        // Capture the settled selected state, not the press highlight.
        _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: own)], timeout: 3)
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        XCTAssertTrue(own.isSelected)
        capture("provider-own-skill-\(suffix)")
        // Optional public fields stay tucked away until the provider chooses them.
        let business = app.staticTexts["provider-business-section"]
        reveal(business, in: app)
        business.tap()
        let businessName = app.textFields["Business name (optional)"]
        reveal(businessName, in: app)
        XCTAssertTrue(businessName.exists)
        capture("provider-business-expanded-\(suffix)")
        reveal(business, in: app, upward: false)
        business.tap()
        XCTAssertFalse(businessName.exists)
        let base = app.buttons["Use my approximate location"]
        reveal(base, in: app)
        base.tap()
        let located = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Current approximate location'")).firstMatch
        allowLocation(unless: { located.exists })
        // The simulator's one-shot location occasionally answers "unknown"; ask again before failing.
        for _ in 0..<2 where !located.waitForExistence(timeout: 20) {
            reveal(base, in: app)
            base.tap()
        }
        XCTAssertTrue(located.waitForExistence(timeout: 20))
        let save = app.buttons["provider-save"]
        reveal(save, in: app)
        capture("provider-setup-\(suffix)")
        save.tap()
        let inbox = app.buttons["navigation-inbox"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 20))
        inbox.tap()
        XCTAssertTrue(app.descendants(matching: .any)["inbox-empty"].waitForExistence(timeout: 20))
        capture("inbox-\(suffix)")
        app.buttons["navigation-ask"].tap()

        // One clarifying question, then offers with their evidence.
        try submit(app, text: "clarify this for me")
        let barber = app.buttons["Barber"]
        XCTAssertTrue(barber.waitForExistence(timeout: 12))
        reveal(barber, in: app)
        capture("clarification-\(suffix)")
        barber.tap()
        let details = app.buttons["View details"].firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 20))
        // Counts tick to the server's numbers; capture once they have settled. A request that
        // already has its offers shows no counts, and there is nothing to wait for.
        let notified = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Notified'")).firstMatch
        _ = until({ !notified.exists || !notified.label.hasSuffix(" 0") }, timeout: 20)
        capture("results-\(suffix)")
        reveal(details, in: app)
        details.tap()
        XCTAssertTrue(app.navigationBars["Offer"].waitForExistence(timeout: 20))
        capture("offer-detail-\(suffix)")
        swipeBack(app)
        XCTAssertTrue(app.buttons["View details"].firstMatch.waitForExistence(timeout: 20))
        stopAndRestart(app, suffix: suffix)

        try submit(app, text: "progress barber")
        let progress = app.descendants(matching: .any)["request-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 20))
        app.swipeDown()
        capture("progress-\(suffix)")
        // Swiping back from a request that is still asking keeps it running and reachable.
        swipeBack(app)
        let resume = app.buttons["ask-resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 20))
        capture("resume-\(suffix)")
        reveal(resume, in: app, upward: false)
        resume.tap()
        XCTAssertTrue(app.descendants(matching: .any)["request-progress"].waitForExistence(timeout: 20))
        stopAndRestart(app, suffix: suffix)

        try submit(app, text: "empty barber")
        XCTAssertTrue(app.staticTexts["No offers"].waitForExistence(timeout: 20))
        capture("empty-\(suffix)")
        // Nobody covers this service: the screen invites the person to offer it instead of ending there.
        let gap = app.buttons["offer-the-gap"]
        reveal(gap, in: app)
        capture("empty-offer-gap-\(suffix)", onlyIfChanged: true)
        askAgain(app)

        try submit(app, text: "restricted request")
        let error = app.staticTexts["PLUG cannot help with this request. Nobody was contacted."]
        XCTAssertTrue(error.waitForExistence(timeout: 20))
        reveal(error, in: app)
        capture("restricted-\(suffix)")

        // Figure A1 screens 2 and 4 for a place question: real counts, then Unknown and the dashed web answer.
        try submit(app, text: "How long is the line at Walmart right now?")
        XCTAssertTrue(app.descendants(matching: .any)["place-progress"].waitForExistence(timeout: 20))
        capture("place-asking-\(suffix)")
        XCTAssertTrue(app.staticTexts["No answers"].waitForExistence(timeout: 20))
        let web = app.staticTexts["Usually busy at this hour"]
        reveal(web, in: app)
        capture("place-web-\(suffix)")
        askAgain(app)

        // Unknown on its own: nobody answered and there is no web summary either.
        try submit(app, text: "How long is the line at Walmart right now? no web")
        XCTAssertTrue(app.staticTexts["No answers"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["From the web"].exists)
        capture("place-unknown-\(suffix)")
        askAgain(app)

        try submit(app, text: "cached barber")
        XCTAssertTrue(app.buttons["View details"].firstMatch.waitForExistence(timeout: 20))
        app.buttons["Refresh"].tap()
        let cached = app.staticTexts["Saved result. Refresh to check it is still current."]
        XCTAssertTrue(cached.waitForExistence(timeout: 20))
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
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 20))
        let guest = app.buttons["Continue as guest"]
        reveal(guest, in: app)
        guest.tap()
        XCTAssertTrue(app.staticTexts["ask-home-title"].waitForExistence(timeout: 15))
    }
    private func submit(_ app: XCUIApplication, text: String) throws {
        let field = app.descendants(matching: .any).matching(identifier: "request-text").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        reveal(field, in: app, upward: false)
        // Earlier words stay after "Ask something else"; the field's Clear button removes them.
        let clear = app.buttons["request-clear"]
        if clear.exists { clear.tap() }
        field.tap()
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text)
        dismissKeyboard(app)
        let ask = app.buttons["ask-submit"]
        reveal(ask, in: app, upward: false)
        ask.tap()
        // The simulator's location service occasionally answers a one-shot request with
        // "unknown"; the app then offers the address path. Ask again before failing. Leaving
        // the composer means the ask went through, so neither wait runs its full length.
        let address = app.descendants(matching: .any).matching(identifier: "request-address").firstMatch
        allowLocation(unless: { address.exists || !ask.exists })
        if until({ address.exists || !ask.exists }, timeout: 3), address.exists {
            reveal(ask, in: app, upward: false)
            ask.tap()
        }
    }
    /// Back to the previous screen with the edge swipe a person uses. On a physical iPhone with
    /// iOS 26.7 the synthesized swipe is sometimes ignored, so the screen is checked, the swipe
    /// tried once more, and then the visible back button is tapped.
    private func swipeBack(_ app: XCUIApplication) {
        let bar = app.navigationBars.firstMatch
        let title = bar.exists ? bar.identifier : ""
        for _ in 0..<2 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
            if title.isEmpty { return }
            let left = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                 object: app.navigationBars[title])
            if XCTWaiter().wait(for: [left], timeout: 2) == .completed { return }
        }
        let back = app.navigationBars[title].buttons.firstMatch
        if back.exists { back.tap() }
    }
    /// Answers the location prompt if it appears. The app asks for permission before it moves
    /// on, so once `settled` holds no prompt is coming and the wait ends there.
    private func allowLocation(unless settled: @escaping () -> Bool) {
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow While Using App"]
        if until({ allow.exists || settled() }, timeout: 2), allow.exists { allow.tap() }
    }
    /// True as soon as `condition` holds, false if it still does not after `timeout` seconds.
    private func until(_ condition: @escaping () -> Bool, timeout: TimeInterval) -> Bool {
        let met = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter().wait(for: [met], timeout: timeout) == .completed
    }
    private func dismissKeyboard(_ app: XCUIApplication) {
        let done = app.toolbars.buttons["Done"]
        if done.waitForExistence(timeout: 2) { done.tap() }
        // The keyboard animates away; wait for it so a following scroll is not hidden behind it.
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 0"), object: app.keyboards)
        if XCTWaiter().wait(for: [gone], timeout: 3) != .completed, done.exists { done.tap() }
    }
    private func stopAndRestart(_ app: XCUIApplication, suffix: String) {
        let stop = app.buttons["request-cancel"]
        let stopped = app.staticTexts["You stopped asking"]
        // Offers arriving re-lay out the page, so a tap can land as the button moves. Stopping is
        // idempotent on the server, so tap again if the first one did not take.
        for _ in 0..<3 where !stopped.exists && stop.exists {
            reveal(stop, in: app)
            stop.tap()
            _ = stopped.waitForExistence(timeout: 8)
        }
        XCTAssertTrue(stopped.waitForExistence(timeout: 20))
        reveal(stopped, in: app, upward: false)
        capture("stopped-\(suffix)")
        askAgain(app)
    }
    private func askAgain(_ app: XCUIApplication) {
        let again = app.buttons["Ask something else"]
        reveal(again, in: app)
        again.tap()
        XCTAssertTrue(app.staticTexts["ask-home-title"].waitForExistence(timeout: 20))
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
        // Page content may scroll beneath the bottom navigation, as on any iOS tab bar, so a
        // control counts as reachable only when it is hittable and clear of that bar.
        func clear() -> Bool {
            guard element.isHittable else { return false }
            let bar = app.buttons["navigation-ask"]
            guard bar.exists, !bar.frame.isEmpty else { return true }
            return element.frame.midY < bar.frame.minY - 4
        }
        for direction in [upward, !upward] {
            for _ in 0..<10 where !clear() { direction ? app.swipeUp() : app.swipeDown() }
            if clear() { return }
        }
        XCTAssertTrue(clear(), "Expected control to remain reachable when scrolling")
    }
    private var lastCapture: Data?

    /// A second view of the same state is kept only when the screen moved. At default text size
    /// the lower part is often already on screen, and an identical file is not evidence of anything.
    private func capture(_ name: String, onlyIfChanged: Bool = false) {
        let shot = XCUIScreen.main.screenshot()
        if onlyIfChanged && shot.pngRepresentation == lastCapture { return }
        lastCapture = shot.pngRepresentation
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "synthetic-p2-\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
