import XCTest

final class JTUITests: XCTestCase {

    let jtBundle = "com.justinwhitehead.JourneyTracker"
    let healthBundle = "com.apple.Health"

    override func setUp() {
        continueAfterFailure = false
    }

    func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    // Tap "Turn On All" then "Allow" on the HealthKit permission sheet.
    func testAllowHealth() {
        let app = XCUIApplication(bundleIdentifier: jtBundle)
        app.activate()
        sleep(3)
        let privacy = XCUIApplication(bundleIdentifier: "com.apple.HealthPrivacyService")
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        let turnOn = privacy.staticTexts["Turn On All"].firstMatch
        if turnOn.waitForExistence(timeout: 5) {
            turnOn.tap()
            sleep(1)
        }

        var dismissed = false
        for attempt in 0..<4 {
            let allow = privacy.buttons["Allow"].firstMatch
            if allow.exists && allow.isHittable && attempt < 2 {
                allow.tap()
            } else {
                // Coordinate fallback: Allow button sits at ~85.5% screen height.
                sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.855)).tap()
            }
            sleep(3)
            if !privacy.staticTexts["Health Access"].firstMatch.exists {
                dismissed = true
                break
            }
        }
        XCTAssertTrue(dismissed, "Health Access sheet did not dismiss")
        sleep(2)
        shot(app, "after-grant")
    }

    // Foreground JT, then add a distance sample in Health, return to JT,
    // tap Re-run query now.
    func testAddDistanceAndRerun() {
        addDistanceSampleInHealthApp()

        let app = XCUIApplication(bundleIdentifier: jtBundle)
        app.activate()
        sleep(2)
        app.swipeUp()
        let rerun = app.buttons["Re-run query now"]
        XCTAssertTrue(rerun.waitForExistence(timeout: 10), "Re-run button not found")
        rerun.tap()
        sleep(3)
        shot(app, "after-rerun")
    }

    // Add a sample while JT is backgrounded, then just reactivate (no re-run tap).
    func testAddDistanceWhileBackgroundedThenReopen() {
        // Make sure JT is running first, then background it via Health app.
        let app = XCUIApplication(bundleIdentifier: jtBundle)
        app.activate()
        _ = app.staticTexts["Request phase"].waitForExistence(timeout: 10)
        sleep(1)

        addDistanceSampleInHealthApp()
        // Wait a bit while backgrounded so observer/background delivery can fire.
        sleep(10)

        app.activate()
        _ = app.staticTexts["Request phase"].waitForExistence(timeout: 10)
        sleep(5)
        shot(app, "after-bg-reopen")
    }

    // Just foreground JT and idle (used to check advisory timing etc).
    func testIdleForeground() {
        let app = XCUIApplication(bundleIdentifier: jtBundle)
        app.activate()
        _ = app.staticTexts["Request phase"].waitForExistence(timeout: 10)
        sleep(3)
        shot(app, "idle")
    }

    // Tap re-run twice with a pause (to advance consecutive zero readings).
    func testRerunTwice() {
        let app = XCUIApplication(bundleIdentifier: jtBundle)
        app.activate()
        sleep(2)
        app.swipeUp()
        let rerun = app.buttons["Re-run query now"]
        XCTAssertTrue(rerun.waitForExistence(timeout: 10))
        rerun.tap()
        sleep(2)
        rerun.tap()
        sleep(2)
        shot(app, "rerun-twice")
    }


    func testScrollTop() {
        let app = XCUIApplication(bundleIdentifier: jtBundle)
        app.activate()
        sleep(2)
        app.swipeDown()
        app.swipeDown()
        sleep(1)
        shot(app, "top")
    }


    // Verify the top-level debug identifiers resolve, and print their values.
    //
    // KAN-10: a FRESH install has a fully-seeded catalog but ZERO journey
    // instances by design (creating a run is a user action — KAN-11), so the
    // per-journey rows (debug.journey.*) are NOT asserted here — they only exist
    // once instances do (e.g. after a migration from the pre-KAN-10 store, or
    // once KAN-11 lets a user start a journey). This test asserts the always-
    // present top-level fields; per-instance rows are reported soft.
    func testReadIdentifiers() {
        let app = XCUIApplication(bundleIdentifier: jtBundle)
        app.activate()
        sleep(2)
        // Move to the Debug tab (the journey list is now the first tab).
        let debugTab = app.tabBars.buttons["Debug"].firstMatch
        if debugTab.waitForExistence(timeout: 5) { debugTab.tap() }
        sleep(1)
        app.swipeDown(); app.swipeDown()
        sleep(1)
        // Always-present, instance-independent fields.
        let requiredIDs = ["debug.requestPhase", "debug.requestStatus", "debug.lastQuery",
                           "debug.cumulativeDistance", "debug.steps", "debug.rerunButton"]
        var report: [String] = []
        for id in requiredIDs {
            var el = app.descendants(matching: .any).matching(identifier: id).firstMatch
            if el.waitForExistence(timeout: 4) {
                report.append("FOUND \(id) = [\(el.label)]")
            } else {
                app.swipeUp()
                el = app.descendants(matching: .any).matching(identifier: id).firstMatch
                if el.waitForExistence(timeout: 3) {
                    report.append("FOUND \(id) = [\(el.label)]")
                } else {
                    report.append("MISSING \(id)")
                }
            }
        }

        // Per-instance rows: soft-reported, not required. When instances exist,
        // each carries a status/accumulated/progress row keyed by journey name.
        let instanceRows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'debug.journey.'"))
        let instanceCount = instanceRows.count
        report.append("INSTANCE-ROWS present = \(instanceCount)")

        let advisory = app.descendants(matching: .any).matching(identifier: "debug.advisory").firstMatch
        report.append(advisory.exists ? "ADVISORY visible = [\(advisory.label)]" : "ADVISORY not visible")
        NSLog("IDREPORT-BEGIN | %@ | IDREPORT-END", report.joined(separator: " | "))
        let att = XCTAttachment(string: report.joined(separator: "\n"))
        att.name = "identifier-report"; att.lifetime = .keepAlways
        add(att)
        shot(app, "identifiers")
        XCTAssertFalse(report.contains(where: { $0.hasPrefix("MISSING") }),
                       report.joined(separator: "; "))
    }

    // Check whether the advisory is visible right now (no assertions on values).
    func testAdvisoryVisible() {
        let app = XCUIApplication(bundleIdentifier: jtBundle)
        app.activate()
        sleep(2)
        app.swipeDown(); app.swipeDown()
        sleep(1)
        let advisory = app.descendants(matching: .any).matching(identifier: "debug.advisory").firstMatch
        NSLog("ADVISORYCHECK: %@", advisory.waitForExistence(timeout: 4) ? "VISIBLE" : "NOT-VISIBLE")
        shot(app, "advisory-check")
    }


    // Enumerate every element whose identifier starts with debug.journey.
    func testProbeJourneyIdentifiers() {
        let app = XCUIApplication(bundleIdentifier: jtBundle)
        app.activate()
        sleep(2)
        app.swipeDown(); app.swipeDown()
        sleep(1)
        let q = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'debug.journey'"))
        var lines: [String] = []
        let n = q.count
        for i in 0..<min(n, 20) {
            let el = q.element(boundBy: i)
            lines.append("[\(el.elementType.rawValue)] id=\(el.identifier) label=\(el.label)")
        }
        NSLog("JPROBE-BEGIN count=%d | %@ | JPROBE-END", n, lines.joined(separator: " | "))
    }

    // MARK: Health app driving



    func addDistanceSampleInHealthApp() {
        let health = XCUIApplication(bundleIdentifier: healthBundle)
        // Fresh launch for deterministic navigation state.
        health.terminate()
        sleep(1)
        health.launch()
        sleep(3)

        // Drive multi-page Health onboarding to completion.
        for i in 0..<16 {
            if health.tabBars.buttons["Browse"].exists { NSLog("ONB[%d]: Browse tab present", i); break }
            if health.searchFields.firstMatch.exists { NSLog("ONB[%d]: search field present", i); break }
            let labels = ["Continue", "Next", "Done", "Get Started", "Skip", "Not Now", "Set Up Later", "Dismiss"]
            var found: String? = nil
            for label in labels where health.buttons[label].firstMatch.exists {
                found = label
                break
            }
            if let label = found {
                NSLog("ONB[%d]: tapping bottom-center (saw %@)", i, label)
                health.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.932)).tap()
                sleep(3)
            } else {
                NSLog("ONB[%d]: no onboarding button visible; done", i)
                break
            }
        }

        let browse = health.tabBars.buttons["Browse"]
        if browse.waitForExistence(timeout: 3) {
            browse.tap()
            sleep(1)
        } else {
            // iOS 26 Health: magnifier button bottom-right opens search.
            let searchButton = health.buttons["Search"].firstMatch
            if searchButton.waitForExistence(timeout: 3) && searchButton.isHittable {
                searchButton.tap()
            } else {
                health.coordinate(withNormalizedOffset: CGVector(dx: 0.87, dy: 0.94)).tap()
            }
            sleep(2)
        }

        let search = health.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8), "No search field in Health app")
        search.tap()
        sleep(1)
        let clear = search.buttons["Clear text"].firstMatch
        if clear.exists { clear.tap() }
        search.typeText("distance")
        sleep(2)

        let cell = health.staticTexts["Walking + Running Distance"].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 8), "Could not find Walking + Running Distance in Health app")
        cell.tap()
        sleep(2)

        let add = health.buttons["Add Data"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 8), "Add Data button not found")
        add.tap()
        sleep(2)

        // Type the value on the numeric keypad (field is pre-focused).
        let field = health.textFields.firstMatch
        if field.exists {
            field.tap()
        }
        health.typeText("1")
        sleep(1)

        var confirmed = false
        for label in ["Add", "Done", "Confirm", "Save"] {
            let b = health.buttons[label].firstMatch
            if b.exists && b.isHittable {
                b.tap()
                confirmed = true
                break
            }
        }
        if !confirmed {
            // Blue checkmark, top-right of the Add Data sheet.
            health.coordinate(withNormalizedOffset: CGVector(dx: 0.905, dy: 0.114)).tap()
        }
        sleep(2)
        // The Add Data sheet should be gone; "Add Data" button visible again.
        XCTAssertTrue(health.buttons["Add Data"].firstMatch.waitForExistence(timeout: 8),
                      "Add Data sheet did not dismiss — sample may not have been saved")
    }
}
