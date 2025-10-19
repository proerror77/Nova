import XCTest

/// End-to-end UI tests for critical user journeys
/// Run on iOS Simulator with test environment
final class CriticalUserJourneysUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment = [
            "MOCK_API": "true",
            "TEST_MODE": "true"
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Journey 1: Onboarding → Sign Up → Feed

    func testJourney1_OnboardingToFeed() throws {
        // Onboarding screen
        XCTAssertTrue(app.otherElements["OnboardingView"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Welcome to Nova"].exists)

        // Tap Get Started
        app.buttons["Get Started"].tap()

        // Auth selection screen
        XCTAssertTrue(app.buttons["Sign Up"].waitForExistence(timeout: 2))
        app.buttons["Sign Up"].tap()

        // Sign up form
        XCTAssertTrue(app.textFields["Username"].waitForExistence(timeout: 2))

        let username = "testuser_\(Int.random(in: 1000...9999))"
        let usernameField = app.textFields["Username"]
        usernameField.tap()
        usernameField.typeText(username)

        let emailField = app.textFields["Email"]
        emailField.tap()
        emailField.typeText("\(username)@test.com")

        let passwordField = app.secureTextFields["Password"]
        passwordField.tap()
        passwordField.typeText("SecurePass123!")

        // Submit sign up
        app.buttons["Create Account"].tap()

        // Should navigate to feed
        XCTAssertTrue(app.otherElements["FeedView"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Feed"].exists)
    }

    // MARK: - Journey 2: Sign In → Like Post → View Comments

    func testJourney2_SignInAndInteractWithFeed() throws {
        // Navigate to sign in
        app.buttons["Get Started"].tap()
        app.buttons["Sign In"].tap()

        // Sign in form
        let emailField = app.textFields["Email"]
        emailField.tap()
        emailField.typeText("test@example.com")

        let passwordField = app.secureTextFields["Password"]
        passwordField.tap()
        passwordField.typeText("password123")

        app.buttons["Sign In"].tap()

        // Wait for feed to load
        XCTAssertTrue(app.otherElements["FeedView"].waitForExistence(timeout: 5))

        // Find first post card
        let firstPost = app.otherElements["PostCard"].firstMatch
        XCTAssertTrue(firstPost.waitForExistence(timeout: 3))

        // Tap like button
        let likeButton = firstPost.buttons["LikeButton"]
        XCTAssertTrue(likeButton.exists)
        likeButton.tap()

        // Verify like state changed
        XCTAssertTrue(firstPost.buttons["UnlikeButton"].waitForExistence(timeout: 2))

        // Tap comment button
        let commentButton = firstPost.buttons["CommentButton"]
        commentButton.tap()

        // Comments sheet should appear
        XCTAssertTrue(app.otherElements["CommentsSheet"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["Comment input"].exists)

        // Close sheet
        app.buttons["Close"].tap()
        XCTAssertFalse(app.otherElements["CommentsSheet"].exists)
    }

    // MARK: - Journey 3: Create Post Flow

    func testJourney3_CreatePost() throws {
        // Sign in first
        signInTestUser()

        // Tap create tab
        app.tabBars.buttons["Create"].tap()

        // Create view should appear
        XCTAssertTrue(app.otherElements["CreateView"].waitForExistence(timeout: 2))

        // Tap select photo
        app.buttons["Select Photo"].tap()

        // Photo picker should appear
        XCTAssertTrue(app.otherElements["PhotoPicker"].waitForExistence(timeout: 3))

        // Select first photo (in test environment, mock photos are provided)
        let firstPhoto = app.images.firstMatch
        if firstPhoto.exists {
            firstPhoto.tap()
        }

        // Proceed to edit
        app.buttons["Next"].tap()

        // Image editor should appear
        XCTAssertTrue(app.otherElements["ImageEditor"].waitForExistence(timeout: 2))

        // Proceed to publish
        app.buttons["Next"].tap()

        // Publish form should appear
        XCTAssertTrue(app.otherElements["PublishForm"].waitForExistence(timeout: 2))

        // Enter caption
        let captionField = app.textViews["Caption"]
        captionField.tap()
        captionField.typeText("Test post from UI test")

        // Publish
        app.buttons["Publish"].tap()

        // Should navigate back to feed
        XCTAssertTrue(app.otherElements["FeedView"].waitForExistence(timeout: 5))

        // Post should appear in feed (may need to scroll to top)
        // Note: In test environment, post appears immediately
    }

    // MARK: - Journey 4: Search Users

    func testJourney4_SearchUsers() throws {
        // Sign in
        signInTestUser()

        // Tap search tab
        app.tabBars.buttons["Search"].tap()

        // Search view should appear
        XCTAssertTrue(app.otherElements["SearchView"].waitForExistence(timeout: 2))

        // Tap search field
        let searchField = app.searchFields["Search users"]
        searchField.tap()
        searchField.typeText("test")

        // Wait for search results
        XCTAssertTrue(app.tables["SearchResults"].waitForExistence(timeout: 3))

        // Results should appear
        let firstResult = app.cells.firstMatch
        if firstResult.exists {
            // Tap first result
            firstResult.tap()

            // User profile should appear
            XCTAssertTrue(app.otherElements["UserProfileView"].waitForExistence(timeout: 2))

            // Follow button should exist
            XCTAssertTrue(app.buttons["Follow"].exists || app.buttons["Following"].exists)
        }
    }

    // MARK: - Journey 5: Profile Navigation

    func testJourney5_ProfileAndSettings() throws {
        // Sign in
        signInTestUser()

        // Tap profile tab
        app.tabBars.buttons["Profile"].tap()

        // Profile view should appear
        XCTAssertTrue(app.otherElements["ProfileView"].waitForExistence(timeout: 2))

        // Tap settings button
        app.buttons["Settings"].tap()

        // Settings view should appear
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2))

        // Verify settings options exist
        XCTAssertTrue(app.cells["Edit Profile"].exists)
        XCTAssertTrue(app.cells["Privacy"].exists)
        XCTAssertTrue(app.cells["Sign Out"].exists)

        // Go back
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.otherElements["ProfileView"].exists)
    }

    // MARK: - Journey 6: Feed Scroll and Pagination

    func testJourney6_FeedScrollAndPagination() throws {
        // Sign in
        signInTestUser()

        // Feed should be visible
        XCTAssertTrue(app.otherElements["FeedView"].waitForExistence(timeout: 5))

        // Get initial post count
        let initialPostCount = app.otherElements.matching(identifier: "PostCard").count

        // Scroll to bottom
        let feedScrollView = app.scrollViews.firstMatch
        feedScrollView.swipeUp()
        feedScrollView.swipeUp()
        feedScrollView.swipeUp()

        // Wait for pagination
        sleep(2)

        // Should have more posts loaded
        let newPostCount = app.otherElements.matching(identifier: "PostCard").count
        XCTAssertGreaterThan(newPostCount, initialPostCount, "More posts should be loaded after scrolling")
    }

    // MARK: - Journey 7: Pull to Refresh

    func testJourney7_PullToRefresh() throws {
        // Sign in
        signInTestUser()

        // Feed should be visible
        XCTAssertTrue(app.otherElements["FeedView"].waitForExistence(timeout: 5))

        // Pull to refresh
        let feedScrollView = app.scrollViews.firstMatch
        let start = feedScrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        let end = feedScrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        start.press(forDuration: 0.1, thenDragTo: end)

        // Refresh indicator should appear briefly
        // Wait for refresh to complete
        sleep(2)

        // Feed should still be visible and functional
        XCTAssertTrue(app.otherElements["FeedView"].exists)
    }

    // MARK: - Journey 8: Post Detail View

    func testJourney8_PostDetailView() throws {
        // Sign in
        signInTestUser()

        // Wait for feed
        XCTAssertTrue(app.otherElements["FeedView"].waitForExistence(timeout: 5))

        // Tap on first post image
        let firstPost = app.otherElements["PostCard"].firstMatch
        XCTAssertTrue(firstPost.exists)

        let postImage = firstPost.images.firstMatch
        postImage.tap()

        // Post detail view should appear
        XCTAssertTrue(app.otherElements["PostDetailView"].waitForExistence(timeout: 2))

        // Should show same post content
        XCTAssertTrue(app.images["Post image"].exists)
        XCTAssertTrue(app.buttons["LikeButton"].exists || app.buttons["UnlikeButton"].exists)

        // Go back
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.otherElements["FeedView"].exists)
    }

    // MARK: - Journey 9: Accessibility

    func testJourney9_VoiceOverSupport() throws {
        // Sign in
        signInTestUser()

        // Check accessibility labels on feed
        let firstPost = app.otherElements["PostCard"].firstMatch
        XCTAssertTrue(firstPost.waitForExistence(timeout: 5))

        // Verify accessibility elements
        XCTAssertNotNil(firstPost.value(forKey: "accessibilityLabel"))

        let likeButton = firstPost.buttons["LikeButton"]
        if likeButton.exists {
            XCTAssertNotNil(likeButton.value(forKey: "accessibilityLabel"))
            XCTAssertNotNil(likeButton.value(forKey: "accessibilityHint"))
        }
    }

    // MARK: - Journey 10: Error Handling

    func testJourney10_NetworkErrorHandling() throws {
        // Launch app with network error simulation
        app.terminate()
        app.launchEnvironment = [
            "MOCK_API": "true",
            "SIMULATE_NETWORK_ERROR": "true"
        ]
        app.launch()

        // Try to sign in
        app.buttons["Get Started"].tap()
        app.buttons["Sign In"].tap()

        let emailField = app.textFields["Email"]
        emailField.tap()
        emailField.typeText("test@example.com")

        let passwordField = app.secureTextFields["Password"]
        passwordField.tap()
        passwordField.typeText("password")

        app.buttons["Sign In"].tap()

        // Error message should appear
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3) ||
                     app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'error'")).firstMatch.exists)
    }

    // MARK: - Helper Methods

    private func signInTestUser() {
        app.buttons["Get Started"].tap()
        app.buttons["Sign In"].tap()

        let emailField = app.textFields["Email"]
        emailField.tap()
        emailField.typeText("test@example.com")

        let passwordField = app.secureTextFields["Password"]
        passwordField.tap()
        passwordField.typeText("password123")

        app.buttons["Sign In"].tap()

        // Wait for feed
        _ = app.otherElements["FeedView"].waitForExistence(timeout: 5)
    }

    // MARK: - Performance Tests

    func testPerformance_AppLaunchTime() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
        }
    }

    func testPerformance_FeedScrolling() throws {
        signInTestUser()

        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric]) {
            let feedScrollView = app.scrollViews.firstMatch
            for _ in 0..<5 {
                feedScrollView.swipeUp()
            }
        }
    }
}
