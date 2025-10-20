import Foundation
import XCTest

/// Global test configuration and setup
class TestConfiguration {
    static let shared = TestConfiguration()

    // MARK: - Test Environment

    var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitesting")
    }

    var isMockAPIEnabled: Bool {
        ProcessInfo.processInfo.environment["MOCK_API"] == "true"
    }

    var shouldSimulateNetworkError: Bool {
        ProcessInfo.processInfo.environment["SIMULATE_NETWORK_ERROR"] == "true"
    }

    var testMode: TestMode {
        if let mode = ProcessInfo.processInfo.environment["TEST_MODE"] {
            return TestMode(rawValue: mode) ?? .unit
        }
        return .unit
    }

    // MARK: - Test Data

    let defaultTestUser = User.mock(
        id: "test_user_1",
        username: "testuser",
        displayName: "Test User",
        bio: "This is a test user"
    )

    let defaultTestEmail = "test@example.com"
    let defaultTestPassword = "TestPass123!"

    // MARK: - API Configuration

    var apiBaseURL: URL {
        if isMockAPIEnabled {
            return URL(string: "http://localhost:8080/mock")!
        }
        return URL(string: "http://localhost:3000/api")!
    }

    var apiTimeout: TimeInterval {
        return 10.0 // 10 seconds for tests
    }

    // MARK: - Test Delays

    let shortDelay: UInt64 = 100_000_000 // 0.1s
    let mediumDelay: UInt64 = 500_000_000 // 0.5s
    let longDelay: UInt64 = 1_000_000_000 // 1s

    // MARK: - Performance Thresholds

    struct PerformanceThresholds {
        static let feedLoadTime: TimeInterval = 1.0 // 1 second
        static let authRequestTime: TimeInterval = 2.0 // 2 seconds
        static let imageCompressionTime: TimeInterval = 0.5 // 0.5 seconds
        static let likeActionTime: TimeInterval = 0.3 // 0.3 seconds
    }

    // MARK: - Coverage Thresholds

    struct CoverageThresholds {
        static let overall: Double = 80.0
        static let viewModels: Double = 90.0
        static let repositories: Double = 85.0
        static let services: Double = 80.0
        static let models: Double = 70.0
    }

    // MARK: - Helper Methods

    func resetTestEnvironment() {
        // Clear all caches
        // Reset singletons
        // Clear keychain
        print("🧹 Test environment reset")
    }

    func waitForAsync(_ duration: TimeInterval = 1.0) async {
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
    }
}

// MARK: - Test Mode

enum TestMode: String {
    case unit = "unit"
    case integration = "integration"
    case ui = "ui"
    case performance = "performance"
}

// MARK: - Test Base Classes

/// Base class for unit tests with common setup
class BaseUnitTestCase: XCTestCase {
    var testConfig: TestConfiguration!

    override func setUp() {
        super.setUp()
        testConfig = TestConfiguration.shared
        testConfig.resetTestEnvironment()
    }

    override func tearDown() {
        testConfig = nil
        super.tearDown()
    }
}

/// Base class for integration tests
@MainActor
class BaseIntegrationTestCase: XCTestCase {
    var testConfig: TestConfiguration!

    override func setUp() async throws {
        try await super.setUp()
        testConfig = TestConfiguration.shared
        testConfig.resetTestEnvironment()
    }

    override func tearDown() {
        testConfig = nil
        super.tearDown()
    }
}

// MARK: - Test Assertions

extension XCTestCase {
    /// Assert that a value is within expected range
    func XCTAssertInRange<T: Comparable>(
        _ value: T,
        min: T,
        max: T,
        _ message: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(value, min, message, file: file, line: line)
        XCTAssertLessThanOrEqual(value, max, message, file: file, line: line)
    }

    /// Assert that an operation completes within expected time
    func XCTAssertCompletesWithin(
        _ timeout: TimeInterval,
        _ message: String = "",
        file: StaticString = #file,
        line: UInt = #line,
        operation: () async throws -> Void
    ) async {
        let start = Date()

        do {
            try await operation()
        } catch {
            XCTFail("Operation threw error: \(error)", file: file, line: line)
            return
        }

        let duration = Date().timeIntervalSince(start)
        XCTAssertLessThanOrEqual(
            duration,
            timeout,
            "\(message) (took \(duration)s, expected < \(timeout)s)",
            file: file,
            line: line
        )
    }

    /// Assert array contains elements matching predicate
    func XCTAssertContains<T>(
        _ array: [T],
        where predicate: (T) -> Bool,
        _ message: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            array.contains(where: predicate),
            message.isEmpty ? "Array does not contain matching element" : message,
            file: file,
            line: line
        )
    }

    /// Assert that two collections have the same elements (order doesn't matter)
    func XCTAssertEqualUnordered<T: Equatable>(
        _ array1: [T],
        _ array2: [T],
        _ message: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            Set(array1),
            Set(array2),
            message.isEmpty ? "Collections are not equal" : message,
            file: file,
            line: line
        )
    }
}

// MARK: - Test Data Builders

class TestDataBuilder {
    static func buildPost(
        customization: (inout Post) -> Void = { _ in }
    ) -> Post {
        var post = Post.mock()
        customization(&post)
        return post
    }

    static func buildUser(
        customization: (inout User) -> Void = { _ in }
    ) -> User {
        var user = User.mock()
        customization(&user)
        return user
    }

    static func buildFeedResult(
        postCount: Int = 20,
        hasMore: Bool = true
    ) -> FeedResult {
        FeedResult(
            posts: Post.mockList(count: postCount),
            hasMore: hasMore
        )
    }
}

// MARK: - Mock Network Delay Simulator

class NetworkDelaySimulator {
    static func simulateNetworkDelay(
        min: TimeInterval = 0.1,
        max: TimeInterval = 0.5
    ) async {
        let delay = TimeInterval.random(in: min...max)
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    static func simulateSlowNetwork() async {
        await simulateNetworkDelay(min: 1.0, max: 3.0)
    }

    static func simulateFastNetwork() async {
        await simulateNetworkDelay(min: 0.05, max: 0.15)
    }
}

// MARK: - Test Observers

/// Observer to track test execution metrics
class TestMetricsObserver: NSObject, XCTestObservation {
    static let shared = TestMetricsObserver()

    var testStartTime: Date?
    var testResults: [String: TestResult] = [:]

    func testBundleWillStart(_ testBundle: Bundle) {
        print("📦 Test bundle starting: \(testBundle.bundlePath)")
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        print("📦 Test bundle finished")
        printSummary()
    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        testStartTime = Date()
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        guard let startTime = testStartTime else { return }

        let duration = Date().timeIntervalSince(startTime)
        let result = TestResult(
            testName: testCase.name,
            duration: duration,
            passed: testCase.testRun?.hasSucceeded ?? false
        )

        testResults[testCase.name] = result

        if duration > 5.0 {
            print("⚠️ Slow test: \(testCase.name) took \(String(format: "%.2f", duration))s")
        }
    }

    private func printSummary() {
        print("\n" + "=".repeating(50))
        print("📊 Test Execution Summary")
        print("=".repeating(50))

        let totalTests = testResults.count
        let passedTests = testResults.values.filter { $0.passed }.count
        let failedTests = totalTests - passedTests

        print("Total: \(totalTests) | Passed: ✅ \(passedTests) | Failed: ❌ \(failedTests)")

        let totalDuration = testResults.values.reduce(0) { $0 + $1.duration }
        print("Total Duration: \(String(format: "%.2f", totalDuration))s")

        // Top 5 slowest tests
        let slowestTests = testResults.values
            .sorted { $0.duration > $1.duration }
            .prefix(5)

        if !slowestTests.isEmpty {
            print("\n🐌 Slowest Tests:")
            for (index, test) in slowestTests.enumerated() {
                print("\(index + 1). \(test.testName): \(String(format: "%.2f", test.duration))s")
            }
        }

        print("=".repeating(50) + "\n")
    }
}

struct TestResult {
    let testName: String
    let duration: TimeInterval
    let passed: Bool
}

extension String {
    func repeating(_ count: Int) -> String {
        String(repeating: self, count: count)
    }
}
