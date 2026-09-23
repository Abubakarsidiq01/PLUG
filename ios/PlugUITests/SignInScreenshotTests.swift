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
///     xcodebuild test -project ios/Plug.xcodeproj -scheme Plug -only-testing:PlugUITests \
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

    private func walk(largestText: Bool, suffix: String) {
        var app = launch(largestText: largestText)
        XCTAssertTrue(app.staticTexts["Ask for what you need nearby."].waitForExistence(timeout: 15),
                      "The welcome screen did not appear.")
        screenshot("01-welcome-\(suffix)")

        // The phone path, as far as the environment allows. With a code channel the next
        // screen is code entry; without one it is the honest "codes are unavailable" state.
        // Both are states in the matrix and both are worth a picture.
        let phoneField = app.textFields["Phone number, including country code"]
        if phoneField.waitForExistence(timeout: 5) {
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
                _ = app.staticTexts["That code is not correct"].waitForExistence(timeout: 10)
                screenshot("04-code-invalid-\(suffix)")
            } else {
                screenshot("03-codes-unavailable-\(suffix)")
            }
        }

        // The guest path, from a clean launch, through to the account it produces.
        app = launch(largestText: largestText)
        let guest = app.buttons["Continue as guest"]
        if guest.waitForExistence(timeout: 15) {
            guest.tap()
            if app.buttons["Profile"].waitForExistence(timeout: 15) {
                screenshot("05-signed-in-as-guest-\(suffix)")
                app.buttons["Profile"].tap()
                // The guest limit, stated on the screen rather than only enforced in the API.
                _ = app.staticTexts["Guest account"].waitForExistence(timeout: 5)
                screenshot("06-guest-profile-\(suffix)")
            } else {
                screenshot("05-guest-sign-in-result-\(suffix)")
            }
        }
    }

    /// Launched with no stored session so every run starts from the same place, and pointed
    /// at whichever backend the run supplies.
    private func launch(largestText: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-plug-ui-test-reset"]
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
