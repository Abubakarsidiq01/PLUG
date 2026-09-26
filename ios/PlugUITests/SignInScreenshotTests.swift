import XCTest

/// Walks the real sign-in screens in the running app and photographs each state.
///
/// This is the tool that produces the evidence manual.docx §12.3 asks for. Run it on the
/// Simulator while building, and on a physical iPhone before the gate — same test, same
/// states, and on the device the captures are real-device captures. Screenshots taken by
/// hand get forgotten, retaken inconsistently and quietly go stale; this does not.
///
/// Every state is photographed at the default text size and again at the largest one,
/// because the largest size is where a fixed height or a truncation shows up.
///
///     # with a Phase 1 backend running (see docs/phases/P1-ONE.md §1)
///     xcodebuild test -project ios/Plug.xcodeproj -scheme PlugUI -only-testing:PlugUITests \
///       -destination '<simulator or device>' \
///       TEST_RUNNER_PLUG_API_URL=http://127.0.0.1:8080
final class SignInScreenshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testSignInStatesAtDefaultTextSize() {
        walk(largestText: false, suffix: "default")
    }

    func testSignInStatesAtLargestTextSize() {
        walk(largestText: true, suffix: "largest-text")
    }

    func testPhoneSignupConflictAndSigninUsingLocalTestDelivery() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let api = environment["PLUG_API_URL"], URL(string: api)?.host == "127.0.0.1",
              let codeFile = environment["PLUG_DEV_CODES"] else {
            throw XCTSkip("Requires an isolated localhost backend with development delivery; never real SMS.")
        }
        let number = "+1555\(Int.random(in: 1000000...9999999))"
        let app = launch(largestText: false)
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 10))
        app.buttons["Get started"].tap()
        try verifyLocalPhone(app, number: number, codeFile: codeFile)
        XCTAssertTrue(app.buttons["Profile"].waitForExistence(timeout: 10))
        app.buttons["Profile"].tap()
        let provider = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ OR value == %@", "Phone number", "Phone number")).firstMatch
        XCTAssertTrue(provider.waitForExistence(timeout: 5))
        screenshot("13-phone-account")
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 10))
        app.buttons["Get started"].tap()
        try verifyLocalPhone(app, number: number, codeFile: codeFile)
        XCTAssertTrue(app.staticTexts["You already have an account"].waitForExistence(timeout: 10))
        screenshot("14-phone-account-exists")
        app.buttons["Sign in"].tap()
        try verifyLocalPhone(app, number: number, codeFile: codeFile)
        XCTAssertTrue(app.buttons["Profile"].waitForExistence(timeout: 10))
    }

    private func verifyLocalPhone(_ app: XCUIApplication, number: String, codeFile: String) throws {
        app.buttons["Continue with phone"].tap()
        let phone = app.textFields["Phone number, including country code"]
        XCTAssertTrue(phone.waitForExistence(timeout: 5))
        phone.tap()
        if let value = phone.value as? String, value.hasPrefix("+") {
            phone.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        phone.typeText(number)
        app.buttons["Send me a code"].tap()
        let field = app.textFields["Six-digit code"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let rows = try String(contentsOfFile: codeFile, encoding: .utf8).split(separator: "\n")
        let row = try XCTUnwrap(rows.last { $0.split(separator: " ").dropFirst().first == Substring(number) })
        let code = try XCTUnwrap(row.split(separator: " ").last)
        field.tap()
        field.typeText(String(code))
        app.buttons["Continue"].tap()
    }

    func testSignUpAndRecoveryOnlyShowTheChosenMethod() {
        let app = launch(largestText: false)
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["Phone number, including country code"].exists)
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.staticTexts["Create your account"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["Phone number, including country code"].exists)
        XCTAssertFalse(app.buttons["Trouble signing in?"].exists)
        app.buttons["Sign in"].tap()
        app.buttons["Trouble signing in?"].tap()
        app.buttons["Google"].tap()
        XCTAssertTrue(app.staticTexts["Recover your Google account"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["Phone number, including country code"].exists)
        screenshot("08-google-recovery")
        app.buttons["Other sign-in methods"].tap()
        app.buttons["Create account"].tap()
        app.buttons["Continue with phone"].tap()
        XCTAssertTrue(app.staticTexts["Sign up with your phone"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Send me a code"].isEnabled)
        screenshot("09-phone-sign-up")
    }

    func testPhoneAvailabilityIsExplainedAndGoogleUsesSignUpLabel() {
        let app = launch(largestText: false, phoneEnabled: false)
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 10))
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.buttons["googleAuthButton"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["googleAuthButton"].label, "Sign up with Google")
        XCTAssertTrue(app.buttons["Continue with phone"].exists)
        XCTAssertTrue(app.staticTexts["Phone verification is not available yet."].exists)
        XCTAssertFalse(app.buttons["Sign up with Apple"].exists)
        screenshot("10-configured-sign-up")
        app.buttons["Sign in"].tap()
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["googleAuthButton"].label, "Sign in with Google")
        XCTAssertTrue(app.buttons["Create account"].isHittable)
        screenshot("10-configured-sign-in")
        app.buttons["Continue with phone"].tap()
        XCTAssertTrue(app.staticTexts["Phone sign-in is not available yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Send me a code"].exists)
        XCTAssertTrue(app.buttons["Other sign-in methods"].isHittable)
    }

    func testLegalAndHelpDocumentsOpenAndDismiss() {
        let app = launch(largestText: false, phoneEnabled: false)
        XCTAssertTrue(app.buttons["Terms"].waitForExistence(timeout: 10))
        for (link, title) in [("Terms", "Terms of Service"), ("Privacy Policy", "Privacy Policy"),
                              ("Help", "Help with PLUG")] {
            app.buttons[link].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            screenshot("11-document-\(link)")
            app.buttons["Done"].tap()
            XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 5))
        }
    }

    func testLogoReturnsHomeAndLandscapeControlsRemainReachable() {
        let app = launch(largestText: false, phoneEnabled: false)
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 10))
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.buttons["googleAuthButton"].waitForExistence(timeout: 5))
        app.buttons["PLUG home"].tap()
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let signIn = app.buttons["I have an account"]
        for _ in 0..<5 where !signIn.isHittable { app.swipeUp() }
        XCTAssertTrue(signIn.isHittable)
        signIn.tap()
        XCTAssertTrue(app.buttons["googleAuthButton"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["googleAuthButton"].label, "Sign in with Google")
        XCTAssertTrue(app.buttons["PLUG home"].isHittable)
        screenshot("12-landscape-sign-in")
    }

    private func walk(largestText: Bool, suffix: String) {
        var app = launch(largestText: largestText)
        XCTAssertTrue(app.staticTexts["Real-time truth.\nBetter local decisions."].waitForExistence(timeout: 15),
                      "The welcome screen did not appear.")
        screenshot("01-welcome-\(suffix)")

        // The phone path, as far as the environment allows. With a code channel the next
        // screen is code entry; without one it is the honest "codes are unavailable" state.
        // Both are states in the matrix and both are worth a picture.
        app.buttons["I have an account"].tap()
        app.buttons["Continue with phone"].tap()
        let phoneField = app.textFields["Phone number, including country code"]
        XCTAssertTrue(phoneField.waitForExistence(timeout: 5))
        do {
            phoneField.tap()
            phoneField.typeText("+1555\(Int.random(in: 1000000...9999999))")
            screenshot("02-phone-entered-\(suffix)")
            app.buttons["Send me a code"].tap()

            let codeField = app.textFields["Six-digit code"]
            if codeField.waitForExistence(timeout: 10) {
                screenshot("03-awaiting-code-\(suffix)")
                codeField.tap()
                codeField.typeText("000000")
                app.buttons["Continue"].tap()
                // A wrong code is a state the person sees often, and the one most likely to
                // be written carelessly, so it gets its own capture.
                XCTAssertTrue(app.staticTexts["That code is not correct"].waitForExistence(timeout: 10))
                screenshot("04-code-invalid-\(suffix)")
            } else {
                XCTAssertTrue(app.staticTexts["Sign-in is unavailable"].waitForExistence(timeout: 5))
                screenshot("03-codes-unavailable-\(suffix)")
            }
        }

        // The guest path, from a clean launch, through to the account it produces.
        app = launch(largestText: largestText)
        let guest = app.buttons["Continue as guest"]
        XCTAssertTrue(guest.waitForExistence(timeout: 15))
        guest.tap()
        XCTAssertTrue(app.buttons["Profile"].waitForExistence(timeout: 15))
        screenshot("05-signed-in-as-guest-\(suffix)")
        app.buttons["Profile"].tap()
        // The guest limit and the upgrade action must both be reachable.
        let guestSection = app.staticTexts["Guest account"]
        for _ in 0..<5 where !guestSection.exists { app.swipeUp() }
        XCTAssertTrue(guestSection.waitForExistence(timeout: 5))
        screenshot("06-guest-profile-\(suffix)")
        let upgrade = app.buttons["Create account or sign in"]
        for _ in 0..<5 where !upgrade.isHittable { app.swipeUp() }
        XCTAssertTrue(upgrade.waitForExistence(timeout: 5))
        upgrade.tap()
        XCTAssertTrue(app.buttons["I have an account"].waitForExistence(timeout: 5))
        screenshot("07-guest-upgrade-\(suffix)")
    }

    /// Launched with no stored session so every run starts from the same place, and pointed
    /// at whichever backend the run supplies.
    private func launch(largestText: Bool, phoneEnabled: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-plug-ui-test-reset"]
        app.launchEnvironment["PLUG_PHONE_SIGN_IN_ENABLED"] = phoneEnabled ? "YES" : "NO"
        if largestText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        // TEST_RUNNER_PLUG_API_URL reaches this runner as PLUG_API_URL; forwarding it is
        // what lets the same test photograph staging as easily as a local backend.
        if let api = ProcessInfo.processInfo.environment["PLUG_API_URL"], !api.isEmpty {
            app.launchEnvironment["PLUG_API_URL"] = api
        }
        if let web = ProcessInfo.processInfo.environment["PLUG_WEB_URL"], !web.isEmpty {
            app.launchEnvironment["PLUG_WEB_URL"] = web
        }
        app.launch()
        return app
    }

    /// The whole screen rather than the application element: the app's own screenshot is
    /// cropped to its accessibility frame, which loses the status bar and, on some devices,
    /// part of the layout — exactly the edges a reviewer is checking.
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
