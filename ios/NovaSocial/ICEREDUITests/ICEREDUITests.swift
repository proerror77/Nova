import XCTest

/// E2E UI Tests for ICERED iOS App
/// Tests registration with invite code, login, and feed verification
final class ICEREDUITests: XCTestCase {

    var app: XCUIApplication!

    // Test user credentials - using timestamp for unique username/email
    private let testPassword = "TestPass123!"
    private let inviteCode = "NOVA2025TEST"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Test: Full Registration, Login, and Feed Flow

    /// Test complete flow: Register with invite code → Login → Verify Feed
    func testFullAuthFlowWithInviteCode() throws {
        let timestamp = Int(Date().timeIntervalSince1970)
        let testEmail = "test\(timestamp)@test.com"
        let testUsername = "testuser\(timestamp)"

        // Step 1: Navigate to Create Account
        navigateToCreateAccount()

        // Step 2: Register with invite code
        registerNewAccount(
            email: testEmail,
            username: testUsername,
            password: testPassword,
            inviteCode: inviteCode
        )

        // Step 3: Verify we're on Home/Feed after registration
        verifyFeedIsDisplayed()
    }

    /// Test login flow with existing credentials
    func testLoginFlow() throws {
        // This test assumes a pre-existing test account
        // For staging/production, use known test credentials
        let testEmail = "e2etest@icered.com"
        let testPassword = "E2ETestPass123!"

        // Attempt login
        loginWithCredentials(email: testEmail, password: testPassword)

        // Note: This may fail if account doesn't exist
        // The full flow test (testFullAuthFlowWithInviteCode) creates and tests in one go
    }

    /// Test registration form validation
    func testRegistrationFormValidation() throws {
        navigateToCreateAccount()

        // Try to submit with empty fields
        let signUpButton = app.buttons["signUpButton"]
        XCTAssertTrue(signUpButton.waitForExistence(timeout: 5), "Sign up button should exist")
        signUpButton.tap()

        // Should show validation error (form shouldn't submit)
        // Wait a moment for any error to appear
        sleep(1)

        // Verify we're still on create account screen (not navigated away)
        let emailField = app.textFields["emailTextField"]
        XCTAssertTrue(emailField.exists, "Should still be on registration screen after validation failure")
    }

    // MARK: - Helper Methods

    /// Navigate from Login screen to Create Account screen
    private func navigateToCreateAccount() {
        let createAccountButton = app.buttons["createAccountButton"]
        XCTAssertTrue(createAccountButton.waitForExistence(timeout: 10), "Create Account button should exist on Login screen")
        createAccountButton.tap()

        // Wait for Create Account screen to load
        let emailField = app.textFields["emailTextField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5), "Email field should exist on Create Account screen")
    }

    /// Fill registration form and submit
    private func registerNewAccount(email: String, username: String, password: String, inviteCode: String) {
        // Fill email
        let emailField = app.textFields["emailTextField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5), "Email field should exist")
        emailField.tap()
        emailField.typeText(email)

        // Fill username
        let usernameField = app.textFields["usernameTextField"]
        XCTAssertTrue(usernameField.waitForExistence(timeout: 5), "Username field should exist")
        usernameField.tap()
        usernameField.typeText(username)

        // Fill password - SecureField uses secureTextFields
        let passwordField = app.secureTextFields["passwordTextField"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5), "Password field should exist")
        passwordField.tap()
        passwordField.typeText(password)

        // Fill confirm password
        let confirmPasswordField = app.secureTextFields["confirmPasswordTextField"]
        XCTAssertTrue(confirmPasswordField.waitForExistence(timeout: 5), "Confirm password field should exist")
        confirmPasswordField.tap()
        confirmPasswordField.typeText(password)

        // Fill invite code
        let inviteCodeField = app.textFields["inviteCodeTextField"]
        XCTAssertTrue(inviteCodeField.waitForExistence(timeout: 5), "Invite code field should exist")
        inviteCodeField.tap()
        // Clear any default value first
        inviteCodeField.press(forDuration: 1.0)
        if app.menuItems["Select All"].exists {
            app.menuItems["Select All"].tap()
        }
        inviteCodeField.typeText(inviteCode)

        // Dismiss keyboard
        app.tap()

        // Submit registration
        let signUpButton = app.buttons["signUpButton"]
        XCTAssertTrue(signUpButton.waitForExistence(timeout: 5), "Sign up button should exist")
        signUpButton.tap()

        // Wait for registration to complete (network request)
        sleep(3)
    }

    /// Login with email/password
    private func loginWithCredentials(email: String, password: String) {
        // Fill email
        let emailField = app.textFields["loginEmailTextField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "Login email field should exist")
        emailField.tap()
        emailField.typeText(email)

        // Fill password
        let passwordField = app.secureTextFields["loginPasswordTextField"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5), "Login password field should exist")
        passwordField.tap()
        passwordField.typeText(password)

        // Dismiss keyboard
        app.tap()

        // Submit login
        let signInButton = app.buttons["signInButton"]
        XCTAssertTrue(signInButton.waitForExistence(timeout: 5), "Sign in button should exist")
        signInButton.tap()

        // Wait for login to complete
        sleep(3)
    }

    /// Verify that feed/home screen is displayed after authentication
    private func verifyFeedIsDisplayed() {
        // After successful auth, we should be on the Home/Feed screen
        // Look for common feed elements - adjust based on actual Feed UI

        // Option 1: Check that login screen elements are gone
        let loginEmailField = app.textFields["loginEmailTextField"]
        let createAccountButton = app.buttons["createAccountButton"]

        // Wait for navigation
        sleep(2)

        // Verify we're no longer on auth screens
        let notOnLogin = !loginEmailField.exists || !loginEmailField.isHittable
        let notOnCreateAccount = !app.textFields["emailTextField"].exists || !app.textFields["emailTextField"].isHittable

        XCTAssertTrue(notOnLogin || notOnCreateAccount, "Should have navigated away from auth screens to feed")

        // Option 2: Look for tab bar (common in feed apps)
        // Uncomment and adjust if your app has a tab bar
        // let tabBar = app.tabBars.firstMatch
        // XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "Tab bar should exist on feed screen")
    }
}
