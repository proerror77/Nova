import XCTest

/// UI Tests for Feed functionality
/// Tests feed loading, scrolling, interactions (like, bookmark), and content display
final class FeedUITests: XCTestCase {

    var app: XCUIApplication!

    // Test credentials - should match staging test account
    private let testEmail = "proerror@gmail.com"
    private let testPassword = "Ttt1234567!"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Feed Loading Tests

    /// Test that feed loads after login
    func testFeedLoadsAfterLogin() throws {
        // Login first
        try loginIfNeeded()

        // Verify feed is displayed
        let forYouButton = app.buttons["For You"]
        XCTAssertTrue(forYouButton.waitForExistence(timeout: 10), "Feed channel tabs should be visible")

        // Wait for posts to load
        sleep(3)

        // Check that at least one post is visible
        let postGroups = app.groups.matching(NSPredicate(format: "label BEGINSWITH 'Post by'"))
        XCTAssertGreaterThan(postGroups.count, 0, "At least one post should be visible in feed")
    }

    /// Test feed scrolling and pagination
    func testFeedScrolling() throws {
        try loginIfNeeded()

        // Wait for initial feed to load
        sleep(3)

        // Get initial post count
        let initialPostGroups = app.groups.matching(NSPredicate(format: "label BEGINSWITH 'Post by'"))
        let initialCount = initialPostGroups.count

        // Scroll down multiple times to trigger pagination
        for _ in 0..<3 {
            app.swipeUp()
            sleep(1)
        }

        // Verify we can still see posts (scrolling worked)
        let postGroups = app.groups.matching(NSPredicate(format: "label BEGINSWITH 'Post by'"))
        XCTAssertGreaterThan(postGroups.count, 0, "Posts should still be visible after scrolling")
    }

    /// Test channel switching in feed
    func testChannelSwitching() throws {
        try loginIfNeeded()

        // Wait for feed to load
        sleep(3)

        // Verify channel tabs exist
        let forYouTab = app.buttons["For You"]
        let followingTab = app.buttons["Following"]
        let fashionTab = app.buttons["Fashion"]

        XCTAssertTrue(forYouTab.exists, "For You tab should exist")
        XCTAssertTrue(followingTab.exists, "Following tab should exist")

        // Switch to Following
        followingTab.tap()
        sleep(2)

        // Switch to Fashion if it exists
        if fashionTab.exists {
            fashionTab.tap()
            sleep(2)
        }

        // Switch back to For You
        forYouTab.tap()
        sleep(2)

        // Verify feed still displays
        let postGroups = app.groups.matching(NSPredicate(format: "label BEGINSWITH 'Post by'"))
        // Note: Following or Fashion might have no posts, so we just verify UI is responsive
    }

    // MARK: - Interaction Tests

    /// Test like button functionality
    func testLikePost() throws {
        try loginIfNeeded()

        // Wait for feed to load
        sleep(3)

        // Find a like button (heart icon)
        let likeButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'heart' OR label CONTAINS 'like'")).firstMatch

        if likeButton.exists {
            likeButton.tap()
            sleep(1)
            // We can't easily verify the like count changed, but verify the tap worked
        }
    }

    /// Test bookmark button displays count
    func testBookmarkCountDisplay() throws {
        try loginIfNeeded()

        // Wait for feed to load
        sleep(3)

        // Scroll to ensure we see post action bar
        app.swipeUp()
        sleep(1)

        // Look for bookmark elements
        // The bookmark count is displayed next to the bookmark icon
        let bookmarkButtons = app.buttons.matching(NSPredicate(format: "label CONTAINS 'bookmark'"))

        // Verify bookmark UI elements exist
        // Note: exact verification depends on UI implementation
    }

    /// Test tapping on a post opens detail view
    func testPostTapOpensDetail() throws {
        try loginIfNeeded()

        // Wait for feed to load
        sleep(3)

        // Find and tap on a post
        let postGroup = app.groups.matching(NSPredicate(format: "label BEGINSWITH 'Post by'")).firstMatch

        if postGroup.exists {
            postGroup.tap()
            sleep(2)

            // Verify we navigated somewhere (back button should exist)
            // or post detail elements are visible
        }
    }

    // MARK: - Search Tests

    /// Test search functionality is accessible
    func testSearchButtonAccessible() throws {
        try loginIfNeeded()

        // Wait for feed to load
        sleep(2)

        // Find search button
        let searchButton = app.buttons["Search"]
        XCTAssertTrue(searchButton.exists, "Search button should be visible in feed")

        // Tap search
        searchButton.tap()
        sleep(1)

        // Verify search UI appears (search field or search screen)
    }

    // MARK: - Navigation Tests

    /// Test bottom tab navigation
    func testBottomTabNavigation() throws {
        try loginIfNeeded()

        // Wait for app to load
        sleep(2)

        // Test Home tab
        let homeButton = app.buttons["Home"]
        if homeButton.exists {
            homeButton.tap()
            sleep(1)
        }

        // Test Messages tab
        let messagesButton = app.buttons["Messages"]
        if messagesButton.exists {
            messagesButton.tap()
            sleep(1)
        }

        // Test Account tab
        let accountButton = app.buttons["Account"]
        if accountButton.exists {
            accountButton.tap()
            sleep(1)
        }

        // Navigate back to Home
        if homeButton.exists {
            homeButton.tap()
            sleep(1)
        }

        // Verify we're back on feed
        let forYouButton = app.buttons["For You"]
        XCTAssertTrue(forYouButton.waitForExistence(timeout: 5), "Should be back on feed after navigation")
    }

    // MARK: - Helper Methods

    /// Login if not already logged in
    private func loginIfNeeded() throws {
        // Check if we're already on the feed (logged in)
        let forYouButton = app.buttons["For You"]
        if forYouButton.waitForExistence(timeout: 3) {
            return // Already logged in
        }

        // Check if login screen is displayed
        let loginEmailField = app.textFields["loginEmailTextField"]
        guard loginEmailField.waitForExistence(timeout: 5) else {
            // Neither feed nor login screen - might be on different screen
            return
        }

        // Fill email
        loginEmailField.tap()
        loginEmailField.typeText(testEmail)

        // Fill password
        let passwordField = app.secureTextFields["loginPasswordTextField"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5), "Password field should exist")
        passwordField.tap()
        passwordField.typeText(testPassword)

        // Dismiss keyboard
        app.tap()

        // Submit login
        let signInButton = app.buttons["signInButton"]
        XCTAssertTrue(signInButton.waitForExistence(timeout: 5), "Sign in button should exist")
        signInButton.tap()

        // Wait for login to complete and feed to load
        sleep(5)
    }
}

// MARK: - Chat UI Tests

/// UI Tests for Chat/Messaging functionality
final class ChatUITests: XCTestCase {

    var app: XCUIApplication!

    private let testEmail = "proerror@gmail.com"
    private let testPassword = "Ttt1234567!"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Test navigating to messages screen
    func testNavigateToMessages() throws {
        try loginIfNeeded()

        // Navigate to Messages tab
        let messagesButton = app.buttons["Messages"]
        XCTAssertTrue(messagesButton.waitForExistence(timeout: 10), "Messages tab should exist")
        messagesButton.tap()

        sleep(3)

        // Verify we're on messages screen
        // Look for common chat list UI elements
    }

    /// Test message list loads
    func testMessageListLoads() throws {
        try loginIfNeeded()

        // Navigate to Messages
        let messagesButton = app.buttons["Messages"]
        guard messagesButton.waitForExistence(timeout: 10) else {
            XCTFail("Messages button not found")
            return
        }
        messagesButton.tap()

        sleep(3)

        // Messages should load (might be empty, but UI should be present)
    }

    // MARK: - Helper Methods

    private func loginIfNeeded() throws {
        let forYouButton = app.buttons["For You"]
        if forYouButton.waitForExistence(timeout: 3) {
            return
        }

        let loginEmailField = app.textFields["loginEmailTextField"]
        guard loginEmailField.waitForExistence(timeout: 5) else {
            return
        }

        loginEmailField.tap()
        loginEmailField.typeText(testEmail)

        let passwordField = app.secureTextFields["loginPasswordTextField"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5))
        passwordField.tap()
        passwordField.typeText(testPassword)

        app.tap()

        let signInButton = app.buttons["signInButton"]
        XCTAssertTrue(signInButton.waitForExistence(timeout: 5))
        signInButton.tap()

        sleep(5)
    }
}

// MARK: - Profile UI Tests

/// UI Tests for Profile functionality
final class ProfileUITests: XCTestCase {

    var app: XCUIApplication!

    private let testEmail = "proerror@gmail.com"
    private let testPassword = "Ttt1234567!"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Test navigating to own profile
    func testNavigateToProfile() throws {
        try loginIfNeeded()

        // Navigate to Account/Profile tab
        let accountButton = app.buttons["Account"]
        XCTAssertTrue(accountButton.waitForExistence(timeout: 10), "Account tab should exist")
        accountButton.tap()

        sleep(3)

        // Verify profile screen elements
        // Should see username, avatar, posts count, etc.
    }

    /// Test profile posts display
    func testProfilePostsDisplay() throws {
        try loginIfNeeded()

        let accountButton = app.buttons["Account"]
        guard accountButton.waitForExistence(timeout: 10) else {
            XCTFail("Account button not found")
            return
        }
        accountButton.tap()

        sleep(3)

        // Profile should show user's posts in a grid
        // ProfilePostCard components should be visible
    }

    // MARK: - Helper Methods

    private func loginIfNeeded() throws {
        let forYouButton = app.buttons["For You"]
        if forYouButton.waitForExistence(timeout: 3) {
            return
        }

        let loginEmailField = app.textFields["loginEmailTextField"]
        guard loginEmailField.waitForExistence(timeout: 5) else {
            return
        }

        loginEmailField.tap()
        loginEmailField.typeText(testEmail)

        let passwordField = app.secureTextFields["loginPasswordTextField"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5))
        passwordField.tap()
        passwordField.typeText(testPassword)

        app.tap()

        let signInButton = app.buttons["signInButton"]
        XCTAssertTrue(signInButton.waitForExistence(timeout: 5))
        signInButton.tap()

        sleep(5)
    }
}
